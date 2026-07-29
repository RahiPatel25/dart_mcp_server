import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'package:flutter_mcp_server/analysis/localization_scanner.dart'
    show kScreenSuffixes;
import 'package:flutter_mcp_server/analysis/widget_scanner.dart'
    show kWidgetBaseClasses;

/// Widget type names that count as a screen scaffold.
const _scaffoldTypes = {'Scaffold', 'CupertinoPageScaffold'};

/// A screen widget discovered in the project.
class ScreenEntry {
  ScreenEntry({
    required this.name,
    required this.path,
    required this.line,
    required this.matchedBySuffix,
    required this.buildsScaffold,
  });

  /// The screen widget class name.
  final String name;

  /// The (usually relative) path of the file declaring the screen.
  final String path;

  /// The 1-based line number of the class declaration.
  final int line;

  /// Whether the class name ends in one of [kScreenSuffixes].
  final bool matchedBySuffix;

  /// Whether the widget (or its companion `State`) builds a [Scaffold].
  final bool buildsScaffold;
}

/// The result of an [analyzeScreens] scan.
class ScreenListResult {
  ScreenListResult({required this.screens, required this.fileCount});

  /// The screen widgets found, sorted by path then line.
  final List<ScreenEntry> screens;

  /// Total number of `.dart` files scanned.
  final int fileCount;
}

/// A source range within a single file.
class _Range {
  _Range(this.path, this.start, this.end);
  final String path;
  final int start;
  final int end;

  bool contains(String p, int offset) =>
      p == path && offset >= start && offset < end;
}

/// A widget class declaration recorded during the declaration pass.
class _WidgetDecl {
  _WidgetDecl({
    required this.name,
    required this.path,
    required this.line,
    required this.start,
    required this.end,
  });

  final String name;
  final String path;
  final int line;
  final int start;
  final int end;
}

/// A point (path + offset) where a scaffold is created.
class _Point {
  _Point(this.path, this.offset);
  final String path;
  final int offset;
}

/// Analyzes [sources] (path -> file content for every scanned `.dart` file) and
/// returns the screen widgets declared in lib files.
///
/// A widget class is a "screen" when its name ends in one of [kScreenSuffixes]
/// (`Screen`/`Page`/`View`), or when it (or its companion `State`) builds a
/// [Scaffold]. [isLibFile] returns true for paths under `lib/`; only those files
/// are scanned for declarations.
ScreenListResult analyzeScreens(
  Map<String, String> sources,
  bool Function(String path) isLibFile,
) {
  final units = <String, CompilationUnit>{};
  final lineInfos = <String, LineInfo>{};
  for (final entry in sources.entries) {
    final result = parseString(
      content: entry.value,
      path: entry.key,
      throwIfDiagnostics: false,
    );
    units[entry.key] = result.unit;
    lineInfos[entry.key] = result.lineInfo;
  }

  // Declaration pass (lib only): widget classes + companion State<W> ranges.
  final widgets = <_WidgetDecl>[];
  final stateRangesByWidget = <String, List<_Range>>{};
  for (final entry in units.entries) {
    if (!isLibFile(entry.key)) continue;
    final visitor = _DeclarationVisitor(entry.key, lineInfos[entry.key]!);
    entry.value.accept(visitor);
    widgets.addAll(visitor.widgets);
    visitor.stateRangesByWidget.forEach((widget, ranges) {
      (stateRangesByWidget[widget] ??= []).addAll(ranges);
    });
  }

  // Signal pass (lib only): scaffold creations.
  final scaffolds = <_Point>[];
  for (final entry in units.entries) {
    if (!isLibFile(entry.key)) continue;
    final visitor = _ScaffoldVisitor(entry.key);
    entry.value.accept(visitor);
    scaffolds.addAll(visitor.scaffolds);
  }

  final screens = <ScreenEntry>[];
  for (final w in widgets) {
    // A screen spans its own class body plus any companion State<W> bodies.
    final ranges = <_Range>[
      _Range(w.path, w.start, w.end),
      ...?stateRangesByWidget[w.name],
    ];
    final buildsScaffold = scaffolds.any(
      (pt) => ranges.any((r) => r.contains(pt.path, pt.offset)),
    );
    final matchedBySuffix = kScreenSuffixes.any((s) => w.name.endsWith(s));

    if (!matchedBySuffix && !buildsScaffold) continue;

    screens.add(
      ScreenEntry(
        name: w.name,
        path: w.path,
        line: w.line,
        matchedBySuffix: matchedBySuffix,
        buildsScaffold: buildsScaffold,
      ),
    );
  }

  screens.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });

  return ScreenListResult(screens: screens, fileCount: sources.length);
}

/// Collects widget declarations and companion `State<W>` ranges from one unit.
class _DeclarationVisitor extends RecursiveAstVisitor<void> {
  _DeclarationVisitor(this.path, this.lineInfo);

  final String path;
  final LineInfo lineInfo;
  final List<_WidgetDecl> widgets = [];
  final Map<String, List<_Range>> stateRangesByWidget = {};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass;
    final superName = superclass?.name.lexeme;

    if (superName != null && kWidgetBaseClasses.contains(superName)) {
      final nameToken = node.namePart.typeName;
      widgets.add(
        _WidgetDecl(
          name: nameToken.lexeme,
          path: path,
          line: lineInfo.getLocation(nameToken.offset).lineNumber,
          start: node.offset,
          end: node.end,
        ),
      );
    } else if (superName == 'State') {
      final typeArgs = superclass?.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        final first = typeArgs.first;
        if (first is NamedType) {
          (stateRangesByWidget[first.name.lexeme] ??= []).add(
            _Range(path, node.offset, node.end),
          );
        }
      }
    }

    super.visitClassDeclaration(node);
  }
}

/// Records scaffold creations within one unit. Without `const`/`new`,
/// `Scaffold(...)` parses as a method invocation; with them, as an instance
/// creation — so both node kinds are handled.
class _ScaffoldVisitor extends RecursiveAstVisitor<void> {
  _ScaffoldVisitor(this.path);

  final String path;
  final List<_Point> scaffolds = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && _scaffoldTypes.contains(node.methodName.name)) {
      scaffolds.add(_Point(path, node.offset));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_scaffoldTypes.contains(node.constructorName.type.name.lexeme)) {
      scaffolds.add(_Point(path, node.offset));
    }
    super.visitInstanceCreationExpression(node);
  }
}
