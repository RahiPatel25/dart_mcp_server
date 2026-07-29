import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_mcp_server/analysis/widget_scanner.dart';

/// Directories (relative to the project root) scanned for widget *usages*.
/// Only `lib/` is scanned for widget *declarations*.
const _usageDirs = ['lib', 'test', 'bin', 'example'];

/// Suffixes of generated files that should be ignored entirely.
const _generatedSuffixes = ['.g.dart', '.freezed.dart', '.mocks.dart', '.config.dart'];

/// Definition of the `find_unused_widgets` tool.
final findUnusedWidgetsTool = Tool(
  name: 'find_unused_widgets',
  description:
      'Scans a Flutter project and lists widget classes declared in lib/ that '
      'are never referenced anywhere in the project (lib/, test/, bin/, '
      'example/). Detects classes extending StatelessWidget, StatefulWidget, '
      'and common Riverpod/hooks base classes. Note: dynamic/reflection/'
      'string-route references and exported public-API widgets may show as '
      'false positives; only the direct superclass is matched.',
  inputSchema: Schema.object(properties: {}),
);

/// Handles calls to [findUnusedWidgetsTool]. [projectPath] is the configured
/// project root injected by the server.
FutureOr<CallToolResult> handleFindUnusedWidgets(
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

  // Gather every scannable .dart file, remembering which live under lib/.
  final sources = <String, String>{};
  final libPaths = <String>{};
  for (final dirName in _usageDirs) {
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

  final result = analyzeSources(sources, libPaths.contains);

  return CallToolResult(content: [TextContent(text: _format(result, projectPath))]);
}

bool _isGenerated(String path) => _generatedSuffixes.any((suffix) => path.endsWith(suffix));

String _format(ScanResult result, String projectPath) {
  if (result.unused.isEmpty) {
    return '✅ No unused widgets found '
        '(scanned ${result.fileCount} files, ${result.widgetCount} widgets).';
  }

  final buffer = StringBuffer()
    ..writeln(
      'Found ${result.unused.length} unused widget'
      '${result.unused.length == 1 ? '' : 's'} '
      '(scanned ${result.fileCount} files, ${result.widgetCount} widgets):',
    );
  for (final w in result.unused) {
    final rel = p.relative(w.path, from: projectPath);
    buffer.writeln('• ${w.name}  —  $rel:${w.line}');
  }
  return buffer.toString().trimRight();
}

CallToolResult _error(String message) => CallToolResult(isError: true, content: [TextContent(text: message)]);
