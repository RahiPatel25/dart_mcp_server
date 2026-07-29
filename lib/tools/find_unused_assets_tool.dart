import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:flutter_mcp_server/analysis/asset_scanner.dart';

/// Directories (relative to the project root) scanned for asset *references*.
const _usageDirs = ['lib', 'test', 'bin', 'example'];

/// Definition of the `find_unused_assets` tool.
final findUnusedAssetsTool = Tool(
  name: 'find_unused_assets',
  description:
      'Scans a Flutter project and lists bundled asset files (declared under '
      'flutter/assets in pubspec.yaml) that are never referenced from Dart code '
      '(lib/, test/, bin/, example/). An asset counts as used when its full '
      'relative path or file name appears in a string literal. Every file type '
      'is considered (images, fonts, json, lottie, audio, ...), since Flutter '
      'bundles all of them; only OS junk and hidden dotfiles (.DS_Store, '
      'Thumbs.db, .gitkeep, ...) are skipped. Note: asset directory entries are '
      'resolved non-recursively (matching Flutter\'s bundling); fully dynamic '
      'paths with no literal file name may show as false positives — verify '
      'before deleting.',
  inputSchema: Schema.object(properties: {}),
);

/// Handles calls to [findUnusedAssetsTool]. [projectPath] is the configured
/// project root injected by the server.
FutureOr<CallToolResult> handleFindUnusedAssets(
  CallToolRequest request,
  String projectPath,
) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    return _error('Project path does not exist: $projectPath');
  }
  final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return _error('No pubspec.yaml found under: $projectPath');
  }

  final declared = _declaredAssetEntries(pubspecFile.readAsStringSync());
  if (declared.isEmpty) {
    return CallToolResult(
      content: [
        TextContent(
          text:
              'No bundled assets declared under flutter/assets '
              'in pubspec.yaml.',
        ),
      ],
    );
  }

  // Resolve declared entries to actual asset files on disk (relative paths).
  final assetPaths = <String>{};
  for (final entry in declared) {
    final full = p.normalize(p.join(projectPath, entry));
    final dir = Directory(full);
    final file = File(full);
    if (entry.endsWith('/') || dir.existsSync()) {
      // Flutter bundles files directly inside a declared directory, not its
      // subdirectories — list non-recursively.
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File && !_isJunkFile(e.path)) {
          assetPaths.add(_rel(projectPath, e.path));
        }
      }
    } else if (file.existsSync()) {
      assetPaths.add(_rel(projectPath, full));
    }
    // Declared-but-missing entries are ignored (a different kind of problem).
  }

  // Gather every scannable .dart file to search for asset references.
  final dartSources = <String, String>{};
  for (final dirName in _usageDirs) {
    final dir = Directory(p.join(projectPath, dirName));
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      dartSources[entity.absolute.path] = entity.readAsStringSync();
    }
  }

  final result = analyzeAssets(assetPaths: assetPaths, dartSources: dartSources);

  return CallToolResult(content: [TextContent(text: _format(result))]);
}

/// Extracts the `flutter: assets:` entries from [pubspecContent], returning each
/// entry as a normalized (`/`-separated) string. Returns an empty list on any
/// parse failure or when no assets are declared.
List<String> _declaredAssetEntries(String pubspecContent) {
  dynamic doc;
  try {
    doc = loadYaml(pubspecContent);
  } catch (_) {
    return const [];
  }
  if (doc is! Map) return const [];
  final flutter = doc['flutter'];
  if (flutter is! Map) return const [];
  final assets = flutter['assets'];
  if (assets is! List) return const [];

  return [
    for (final a in assets)
      if (a != null) a.toString().trim().replaceAll(r'\', '/'),
  ]..removeWhere((e) => e.isEmpty);
}

String _rel(String projectPath, String path) => p.relative(path, from: projectPath).replaceAll(r'\', '/');

/// Non-asset filesystem noise that OSes drop into folders (`.DS_Store`,
/// `Thumbs.db`) plus any hidden dotfile (`.gitkeep`, `.gitignore`, ...). These
/// are never real assets, so they are skipped when scanning declared asset
/// directories. Explicitly declared file entries are honored regardless.
bool _isJunkFile(String path) {
  final name = p.basename(path);
  if (name.startsWith('.')) return true;
  const junkNames = {'thumbs.db', 'desktop.ini'};
  return junkNames.contains(name.toLowerCase());
}

String _format(AssetScanResult result) {
  if (result.unused.isEmpty) {
    return '✅ No unused assets found '
        '(${result.assetCount} assets, scanned ${result.fileCount} Dart files).';
  }

  final buffer = StringBuffer()
    ..writeln(
      'Found ${result.unused.length} unused asset'
      '${result.unused.length == 1 ? '' : 's'} '
      '(${result.assetCount} assets, scanned ${result.fileCount} Dart files):',
    );
  for (final a in result.unused) {
    buffer.writeln('• ${a.path}');
  }
  return buffer.toString().trimRight();
}

CallToolResult _error(String message) => CallToolResult(isError: true, content: [TextContent(text: message)]);
