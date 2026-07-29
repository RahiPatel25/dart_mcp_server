import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'package:flutter_mcp_server/analysis/widget_scanner.dart'
    show kWidgetBaseClasses;

/// Class-name suffixes that mark a widget as a "screen" regardless of what it
/// builds. A widget that builds a [Scaffold] is also treated as a screen.
const kScreenSuffixes = {'Screen', 'Page', 'View'};

/// Widget type names whose first positional string argument is user-visible
/// text (e.g. `Text('Hello')`).
const _textWidgets = {'Text', 'SelectableText', 'Tooltip'};

/// Named argument labels whose string-literal value is user-visible text
/// (e.g. `hintText: 'Search'`, `title: 'Home'`).
const _textArgNames = {
  'title',
  'label',
  'labelText',
  'hintText',
  'helperText',
  'errorText',
  'tooltip',
  'content',
  'message',
};

/// Widget type names that count as a screen scaffold.
const _scaffoldTypes = {'Scaffold', 'CupertinoPageScaffold'};

/// A screen widget that contains hardcoded, user-visible strings but makes no
/// use of any localization mechanism.
class ScreenInfo {
  ScreenInfo({
    required this.name,
    required this.path,
    required this.line,
    required this.hardcodedCount,
    required this.samples,
  });

  /// The screen widget class name.
  final String name;

  /// The (usually relative) path of the file declaring the screen.
  final String path;

  /// The 1-based line number of the class declaration.
  final int line;

  /// How many hardcoded user-visible strings were found in the screen.
  final int hardcodedCount;

  /// Up to a few example hardcoded strings, for context in the report.
  final List<String> samples;
}

/// The result of an [analyzeLocalization] scan.
class LocalizationScanResult {
  LocalizationScanResult({
    required this.unlocalized,
    required this.screenCount,
    required this.fileCount,
  });

  /// Screens that have hardcoded strings and no localization usage.
  final List<ScreenInfo> unlocalized;

  /// Total number of screen widgets discovered in lib.
  final int screenCount;

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

/// A point (path + offset) where a signal of interest occurs.
class _Point {
  _Point(this.path, this.offset);
  final String path;
  final int offset;
}

/// A hardcoded user-visible string literal found at a location.
class _StringHit {
  _StringHit(this.path, this.offset, this.value);
  final String path;
  final int offset;
  final String value;
}

/// Analyzes [sources] (path -> file content for every scanned `.dart` file) and
/// returns the screen widgets declared in lib files that contain hardcoded,
/// user-visible strings but do not use any localization mechanism.
///
/// [isLibFile] returns true for paths under `lib/`; only those files are scanned
/// for screen declarations and their contents.
LocalizationScanResult analyzeLocalization(
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

  // Signal pass (lib only): scaffolds, localization usages, hardcoded strings.
  final scaffolds = <_Point>[];
  final l10n = <_Point>[];
  final strings = <_StringHit>[];
  for (final entry in units.entries) {
    if (!isLibFile(entry.key)) continue;
    final visitor = _SignalVisitor(entry.key);
    entry.value.accept(visitor);
    scaffolds.addAll(visitor.scaffolds);
    l10n.addAll(visitor.l10n);
    strings.addAll(visitor.strings);
  }

  var screenCount = 0;
  final unlocalized = <ScreenInfo>[];
  for (final w in widgets) {
    // A screen spans its own class body plus any companion State<W> bodies.
    final ranges = <_Range>[
      _Range(w.path, w.start, w.end),
      ...?stateRangesByWidget[w.name],
    ];
    bool within(_Point pt) =>
        ranges.any((r) => r.contains(pt.path, pt.offset));

    final isScreen = kScreenSuffixes.any((s) => w.name.endsWith(s)) ||
        scaffolds.any(within);
    if (!isScreen) continue;
    screenCount++;

    final hasL10n = l10n.any(within);
    if (hasL10n) continue;

    final hits = strings
        .where((h) => ranges.any((r) => r.contains(h.path, h.offset)))
        .toList();
    if (hits.isEmpty) continue;

    unlocalized.add(
      ScreenInfo(
        name: w.name,
        path: w.path,
        line: w.line,
        hardcodedCount: hits.length,
        samples: hits.take(3).map((h) => h.value).toList(),
      ),
    );
  }

  unlocalized.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });

  return LocalizationScanResult(
    unlocalized: unlocalized,
    screenCount: screenCount,
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

/// Records scaffold usages, localization usages, and hardcoded user-visible
/// string literals within one unit.
class _SignalVisitor extends RecursiveAstVisitor<void> {
  _SignalVisitor(this.path);

  final String path;
  final List<_Point> scaffolds = [];
  final List<_Point> l10n = [];
  final List<_StringHit> strings = [];

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (_scaffoldTypes.contains(name)) {
      scaffolds.add(_Point(path, node.offset));
    }
    if (name == 'AppLocalizations') {
      l10n.add(_Point(path, node.offset));
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // `context.l10n`, `ref.watch(...).l10n`, bare `AppLocalizations`.
    if (node.name == 'l10n' ||
        node.name == 'L10n' ||
        node.name == 'AppLocalizations') {
      l10n.add(_Point(path, node.offset));
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // `S.current` (intl_utils).
    if (node.prefix.name == 'S' && node.identifier.name == 'current') {
      l10n.add(_Point(path, node.offset));
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target;

    // easy_localization: `'key'.tr()`, `tr('key')`, `context.tr('key')`.
    if (method == 'tr' || method == 'translate') {
      l10n.add(_Point(path, node.offset));
    }

    // `AppLocalizations.of(context)`, `Localizations.of(...)`, `S.of(context)`.
    if (method == 'of' &&
        target is SimpleIdentifier &&
        (target.name == 'AppLocalizations' ||
            target.name == 'Localizations' ||
            target.name == 'S')) {
      l10n.add(_Point(path, node.offset));
    }

    // `Intl.message(...)`, `Intl.plural(...)`, etc.
    if (target is SimpleIdentifier &&
        target.name == 'Intl' &&
        (method == 'message' ||
            method == 'plural' ||
            method == 'select' ||
            method == 'gender')) {
      l10n.add(_Point(path, node.offset));
    }

    // Without `const`/`new`, `Scaffold(...)` and `Text('x')` parse as function
    // invocations rather than instance creations, so handle them here too.
    if (target == null) {
      if (_scaffoldTypes.contains(method)) {
        scaffolds.add(_Point(path, node.offset));
      }
      _recordTextArgs(method, node.argumentList);
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `const Text('x')` / `new Text('x')` parse as instance creations.
    _recordTextArgs(node.constructorName.type.name.lexeme, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  /// If [typeName] is a text-bearing widget, record its first user-visible
  /// positional string argument.
  void _recordTextArgs(String typeName, ArgumentList args) {
    if (!_textWidgets.contains(typeName)) return;
    for (final arg in args.arguments) {
      if (arg is SimpleStringLiteral && _isUserText(arg.value)) {
        strings.add(_StringHit(path, arg.offset, arg.value));
        break; // one hit per text widget is enough
      }
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final label = node.name.lexeme;
    final value = node.argumentExpression;
    if (_textArgNames.contains(label) &&
        value is SimpleStringLiteral &&
        _isUserText(value.value)) {
      strings.add(_StringHit(path, value.offset, value.value));
    }
    super.visitNamedArgument(node);
  }
}

/// Heuristic: is [s] a human-facing string (vs. an asset path, URL, key, etc.)?
bool _isUserText(String s) {
  final t = s.trim();
  if (t.length < 2) return false;
  if (!t.contains(RegExp('[A-Za-z]'))) return false;
  if (t.contains('://')) return false;
  if (t.startsWith('assets/') || t.startsWith('/')) return false;
  return true;
}
