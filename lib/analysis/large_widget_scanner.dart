import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'package:flutter_mcp_server/analysis/widget_scanner.dart'
    show kWidgetBaseClasses;

/// Default threshold (in source lines) above which a `build` method is
/// considered "large".
const kDefaultBuildLineThreshold = 100;

/// A widget whose `build` method is longer than the configured threshold.
class LargeWidget {
  LargeWidget({
    required this.name,
    required this.path,
    required this.line,
    required this.buildLines,
    required this.classLines,
    required this.isStateful,
  });

  /// The widget class name (for a `StatefulWidget`, the widget — not its
  /// `State` — is reported).
  final String name;

  /// The path of the file declaring the class that contains the `build` method
  /// (the widget itself, or its companion `State`).
  final String path;

  /// The 1-based line of the `build` method.
  final int line;

  /// Number of source lines spanned by the `build` method.
  final int buildLines;

  /// Number of source lines spanned by the class that declares `build`.
  final int classLines;

  /// Whether the `build` method lives in a companion `State` class.
  final bool isStateful;
}

/// The result of an [analyzeLargeWidgets] scan.
class LargeWidgetResult {
  LargeWidgetResult({
    required this.widgets,
    required this.widgetCount,
    required this.fileCount,
    required this.threshold,
  });

  /// Widgets over the threshold, sorted by `build` size (largest first).
  final List<LargeWidget> widgets;

  /// Total number of widget classes considered.
  final int widgetCount;

  /// Total number of `.dart` files scanned.
  final int fileCount;

  /// The threshold used, in source lines.
  final int threshold;
}

/// Analyzes [sources] (path -> file content) and returns widgets declared in
/// lib files whose `build` method spans more than [threshold] source lines.
///
/// For a `StatefulWidget`, `build` lives in the companion `State` class; it is
/// still attributed to the widget (`Foo`, not `_FooState`). [isLibFile] returns
/// true for paths under `lib/`; only those files are scanned for declarations.
LargeWidgetResult analyzeLargeWidgets(
  Map<String, String> sources,
  bool Function(String path) isLibFile, {
  int threshold = kDefaultBuildLineThreshold,
}) {
  final widgetClasses = <_WidgetClass>[];
  // widget name -> its companion State class (first one that declares build).
  final stateByWidget = <String, _StateClass>{};

  for (final entry in sources.entries) {
    if (!isLibFile(entry.key)) continue;
    final result = parseString(
      content: entry.value,
      path: entry.key,
      throwIfDiagnostics: false,
    );
    final visitor = _DeclarationVisitor(entry.key, result.lineInfo);
    result.unit.accept(visitor);
    widgetClasses.addAll(visitor.widgetClasses);
    for (final state in visitor.stateClasses) {
      final existing = stateByWidget[state.widget];
      if (existing == null || (existing.build == null && state.build != null)) {
        stateByWidget[state.widget] = state;
      }
    }
  }

  final widgets = <LargeWidget>[];
  for (final w in widgetClasses) {
    // Resolve where build lives: the widget's own class, else its State.
    final _BuildInfo? build;
    final String path;
    final int classLines;
    final bool isStateful;

    if (w.build != null) {
      build = w.build;
      path = w.path;
      classLines = w.classLines;
      isStateful = false;
    } else {
      final state = stateByWidget[w.name];
      if (state?.build != null) {
        build = state!.build;
        path = state.path;
        classLines = state.classLines;
        isStateful = true;
      } else {
        continue; // No build method found — nothing to measure.
      }
    }

    if (build!.lineCount <= threshold) continue;

    widgets.add(
      LargeWidget(
        name: w.name,
        path: path,
        line: build.line,
        buildLines: build.lineCount,
        classLines: classLines,
        isStateful: isStateful,
      ),
    );
  }

  widgets.sort((a, b) {
    final byBuild = b.buildLines.compareTo(a.buildLines);
    if (byBuild != 0) return byBuild;
    final byClass = b.classLines.compareTo(a.classLines);
    if (byClass != 0) return byClass;
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });

  return LargeWidgetResult(
    widgets: widgets,
    widgetCount: widgetClasses.length,
    fileCount: sources.length,
    threshold: threshold,
  );
}

/// Line span and location of a `build` method.
class _BuildInfo {
  _BuildInfo({required this.line, required this.lineCount});
  final int line;
  final int lineCount;
}

/// A widget class (extends a known widget base class), with its own `build` if
/// it declares one.
class _WidgetClass {
  _WidgetClass({
    required this.name,
    required this.path,
    required this.classLines,
    required this.build,
  });
  final String name;
  final String path;
  final int classLines;
  final _BuildInfo? build;
}

/// A `State<W>` class, linked to its widget `W`, with its `build` if present.
class _StateClass {
  _StateClass({
    required this.widget,
    required this.path,
    required this.classLines,
    required this.build,
  });
  final String widget;
  final String path;
  final int classLines;
  final _BuildInfo? build;
}

/// Collects widget and `State<W>` classes (with their `build` spans) from one
/// compilation unit.
class _DeclarationVisitor extends RecursiveAstVisitor<void> {
  _DeclarationVisitor(this.path, this.lineInfo);

  final String path;
  final LineInfo lineInfo;
  final List<_WidgetClass> widgetClasses = [];
  final List<_StateClass> stateClasses = [];

  int _lineOf(int offset) => lineInfo.getLocation(offset).lineNumber;
  int _spanLines(int offset, int end) => _lineOf(end) - _lineOf(offset) + 1;

  /// Finds the `build` method declared directly in [node], if any.
  _BuildInfo? _buildOf(ClassDeclaration node) {
    for (final member in node.body.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        return _BuildInfo(
          line: _lineOf(member.offset),
          lineCount: _spanLines(member.offset, member.end),
        );
      }
    }
    return null;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass;
    final superName = superclass?.name.lexeme;
    final classLines = _spanLines(node.offset, node.end);

    if (superName != null && kWidgetBaseClasses.contains(superName)) {
      widgetClasses.add(
        _WidgetClass(
          name: node.namePart.typeName.lexeme,
          path: path,
          classLines: classLines,
          build: _buildOf(node),
        ),
      );
    } else if (superName == 'State') {
      final typeArgs = superclass?.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        final first = typeArgs.first;
        if (first is NamedType) {
          stateClasses.add(
            _StateClass(
              widget: first.name.lexeme,
              path: path,
              classLines: classLines,
              build: _buildOf(node),
            ),
          );
        }
      }
    }

    super.visitClassDeclaration(node);
  }
}
