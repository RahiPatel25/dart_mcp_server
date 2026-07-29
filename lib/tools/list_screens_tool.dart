import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_mcp_server/analysis/screen_scanner.dart';

/// Directories (relative to the project root) scanned for screens.
const _scanDirs = ['lib'];

/// Suffixes of generated files that should be ignored entirely.
const _generatedSuffixes = ['.g.dart', '.freezed.dart', '.mocks.dart', '.config.dart'];

/// Definition of the `list_screens` tool.
final listScreensTool = Tool(
  name: 'list_screens',
  description:
      'Scans a Flutter project and lists every screen widget declared in lib/. '
      'A widget is a screen when its class name ends in Screen, Page, or View, '
      'or when it (or its companion State) builds a Scaffold / '
      'CupertinoPageScaffold. Detects classes extending StatelessWidget, '
      'StatefulWidget, and common Riverpod/hooks base classes. Note: syntactic '
      'detection only — a custom base class that itself extends a widget is not '
      'followed.',
  inputSchema: Schema.object(properties: {}),
);

/// Handles calls to [listScreensTool]. [projectPath] is the configured project
/// root injected by the server.
FutureOr<CallToolResult> handleListScreens(
  CallToolRequest request,
  String projectPath,
) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    return _error('Project path does not exist: $projectPath');
  }
  final libDir = Directory(p.join(projectPath, 'lib'));
  if (!libDir.existsSync()) {
    return _error('No lib/ directory found under: $projectPath');
  }

  final sources = <String, String>{};
  final libPaths = <String>{};
  for (final dirName in _scanDirs) {
    final dir = Directory(p.join(projectPath, dirName));
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_isGenerated(entity.path)) continue;
      final abs = entity.absolute.path;
      sources[abs] = entity.readAsStringSync();
      if (dirName == 'lib') libPaths.add(abs);
    }
  }

  final result = analyzeScreens(sources, libPaths.contains);

  return CallToolResult(content: [TextContent(text: _format(result, projectPath))]);
}

bool _isGenerated(String path) => _generatedSuffixes.any((suffix) => path.endsWith(suffix));

String _format(ScreenListResult result, String projectPath) {
  if (result.screens.isEmpty) {
    return 'No screens found (scanned ${result.fileCount} files).';
  }

  final buffer = StringBuffer()
    ..writeln(
      'Found ${result.screens.length} screen'
      '${result.screens.length == 1 ? '' : 's'} '
      '(scanned ${result.fileCount} files):',
    );
  for (final s in result.screens) {
    final rel = p.relative(s.path, from: projectPath);
    buffer.writeln('• ${s.name}  —  $rel:${s.line}  (${_reason(s)})');
  }
  return buffer.toString().trimRight();
}

/// A short human-readable reason describing why the class was classed a screen.
String _reason(ScreenEntry s) {
  if (s.matchedBySuffix && s.buildsScaffold) return 'name + Scaffold';
  if (s.matchedBySuffix) return 'name';
  return 'Scaffold';
}

CallToolResult _error(String message) => CallToolResult(isError: true, content: [TextContent(text: message)]);
