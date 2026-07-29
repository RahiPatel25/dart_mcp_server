import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A bundled asset file that is never referenced from Dart code.
class UnusedAsset {
  UnusedAsset({required this.path});

  /// The asset path, relative to the project root and using `/` separators
  /// (e.g. `assets/images/logo.png`).
  final String path;
}

/// The result of an [analyzeAssets] scan.
class AssetScanResult {
  AssetScanResult({required this.unused, required this.assetCount, required this.fileCount});

  /// The bundled assets that are never referenced, sorted by path.
  final List<UnusedAsset> unused;

  /// Total number of bundled asset files considered.
  final int assetCount;

  /// Total number of `.dart` files scanned for references.
  final int fileCount;
}

/// Analyzes [assetPaths] (relative paths of every bundled asset file) against
/// [dartSources] (path -> file content) and returns the assets that are never
/// referenced from Dart code.
///
/// An asset is considered *used* when its full relative path, or its file name,
/// appears inside any string literal (including the fixed parts of an
/// interpolation) in the Dart sources. Matching only within string literals
/// avoids coincidental matches against identifiers or comments.
///
/// The function is pure so it can be unit-tested against in-memory sources; the
/// caller is responsible for discovering bundled assets and reading files.
AssetScanResult analyzeAssets({required Set<String> assetPaths, required Map<String, String> dartSources}) {
  // Collect every string-literal value from the Dart sources into one haystack.
  final literals = <String>[];
  for (final content in dartSources.values) {
    final result = parseString(content: content, throwIfDiagnostics: false);
    final visitor = _StringLiteralVisitor();
    result.unit.accept(visitor);
    literals.addAll(visitor.values);
  }
  final haystack = literals.join('\n');

  final unused = <UnusedAsset>[];
  for (final asset in assetPaths) {
    final normalized = asset.replaceAll(r'\', '/');
    final fileName = normalized.split('/').last;
    // Match on the full path first; fall back to the file name so that assets
    // referenced via an interpolated directory (e.g. '$base/logo.png') are not
    // reported as unused.
    final used = haystack.contains(normalized) || haystack.contains(fileName);
    if (!used) unused.add(UnusedAsset(path: normalized));
  }

  unused.sort((a, b) => a.path.compareTo(b.path));

  return AssetScanResult(unused: unused, assetCount: assetPaths.length, fileCount: dartSources.length);
}

/// Collects the values of every string literal in a compilation unit.
///
/// [SimpleStringLiteral] covers plain strings and the pieces of adjacent
/// strings; [InterpolationString] covers the fixed text between `$…`
/// expressions inside an interpolated string.
class _StringLiteralVisitor extends RecursiveAstVisitor<void> {
  final List<String> values = [];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    values.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    values.add(node.value);
    super.visitInterpolationString(node);
  }
}
