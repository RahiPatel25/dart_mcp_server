import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// Superclasses that mark a class as a "widget" for the purposes of this scan.
///
/// Only the *direct* superclass is matched (syntactic parse — no type
/// resolution), which covers standard Flutter plus the common Riverpod /
/// flutter_hooks base classes.
const kWidgetBaseClasses = {
  'StatelessWidget',
  'StatefulWidget',
  'ConsumerWidget',
  'ConsumerStatefulWidget',
  'HookWidget',
  'HookConsumerWidget',
  'StatefulHookConsumerWidget',
};

/// A widget class that the scan found to be declared but never referenced.
class WidgetInfo {
  WidgetInfo({required this.name, required this.path, required this.line});

  /// The widget class name.
  final String name;

  /// The (usually relative) path of the file declaring the widget.
  final String path;

  /// The 1-based line number of the class declaration.
  final int line;
}

/// The result of a [analyzeSources] scan.
class ScanResult {
  ScanResult({
    required this.unused,
    required this.widgetCount,
    required this.fileCount,
  });

  /// Widgets declared in lib but never referenced anywhere in the project.
  final List<WidgetInfo> unused;

  /// Total number of widget classes discovered in lib.
  final int widgetCount;

  /// Total number of `.dart` files scanned.
  final int fileCount;
}

/// A recorded declaration of a widget class, with its source range so that
/// self-references can be excluded when counting usages.
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

/// A source range within a single file (used for widget/State declaration
/// spans that should be excluded from usage counting).
class _Range {
  _Range(this.path, this.start, this.end);
  final String path;
  final int start;
  final int end;

  bool contains(String p, int offset) =>
      p == path && offset >= start && offset < end;
}

/// A single reference to a widget name at a given location.
class _Ref {
  _Ref(this.path, this.offset);
  final String path;
  final int offset;
}

/// Analyzes [sources] (path -> file content for every scanned `.dart` file) and
/// returns the widgets declared in lib files that are never referenced.
///
/// [isLibFile] returns true for paths that live under `lib/`; only those files
/// are scanned for widget *declarations*, while *usages* are counted across all
/// [sources].
ScanResult analyzeSources(
  Map<String, String> sources,
  bool Function(String path) isLibFile,
) {
  // Parse every source once (tolerant: a file with parse errors still yields a
  // partial unit rather than throwing).
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

  // Declaration pass: widgets (from lib only) and companion State<W> ranges.
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

  final widgetNames = {for (final w in widgets) w.name};

  // Reference pass: record occurrences of any widget name across ALL sources.
  final refs = <String, List<_Ref>>{};
  for (final entry in units.entries) {
    final visitor = _ReferenceVisitor(entry.key, widgetNames);
    entry.value.accept(visitor);
    visitor.refs.forEach((name, list) {
      (refs[name] ??= []).addAll(list);
    });
  }

  // A widget is used if it is referenced outside its own declaration range and
  // outside its companion State<W> range.
  final unused = <WidgetInfo>[];
  for (final w in widgets) {
    final ownRange = _Range(w.path, w.start, w.end);
    final excluded = [ownRange, ...?stateRangesByWidget[w.name]];
    final widgetRefs = refs[w.name] ?? const [];
    final isUsed = widgetRefs.any(
      (ref) => !excluded.any((range) => range.contains(ref.path, ref.offset)),
    );
    if (!isUsed) {
      unused.add(WidgetInfo(name: w.name, path: w.path, line: w.line));
    }
  }

  unused.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });

  return ScanResult(
    unused: unused,
    widgetCount: widgets.length,
    fileCount: sources.length,
  );
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
      // `class _FooState extends State<Foo>` links this range to widget `Foo`.
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

/// Records references to any name in [widgetNames] within one unit.
///
/// [NamedType] covers instantiation (`Foo()`), type annotations, and generics;
/// [SimpleIdentifier] covers tear-offs and static access.
class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  _ReferenceVisitor(this.path, this.widgetNames);

  final String path;
  final Set<String> widgetNames;
  final Map<String, List<_Ref>> refs = {};

  void _record(String name, int offset) {
    if (widgetNames.contains(name)) {
      (refs[name] ??= []).add(_Ref(path, offset));
    }
  }

  @override
  void visitNamedType(NamedType node) {
    _record(node.name.lexeme, node.name.offset);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _record(node.name, node.offset);
    super.visitSimpleIdentifier(node);
  }
}
