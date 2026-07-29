import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_mcp_server/analysis/project_analyzer.dart';

/// Definition of the `analyze_project` tool.
final analyzeProjectTool = Tool(
  name: 'analyze_project',
  description:
      'Analyzes a Flutter project and returns a high-level profile as JSON: '
      'project name, Flutter and Dart SDK versions, the state-management '
      'library (Riverpod, BLoC, Provider, GetX, MobX, ...), router, networking '
      'and localization libraries, and dependency counts. Flutter version is '
      'read from FVM config (.fvmrc / .fvm/fvm_config.json) when present, then '
      'pubspec.lock, then pubspec.yaml; the resolved package count comes from '
      'pubspec.lock when available.',
  inputSchema: Schema.object(properties: {}),
);

/// Handles calls to [analyzeProjectTool]. [projectPath] is the configured
/// project root injected by the server.
FutureOr<CallToolResult> handleAnalyzeProject(
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

  final analysis = analyzeProject(
    pubspecContent: pubspecFile.readAsStringSync(),
    pubspecLockContent: _readIfExists(p.join(projectPath, 'pubspec.lock')),
    fvmrcContent: _readIfExists(p.join(projectPath, '.fvmrc')),
    fvmConfigContent: _readIfExists(p.join(projectPath, '.fvm', 'fvm_config.json')),
  );

  final json = const JsonEncoder.withIndent('  ').convert(analysis.toJson());
  return CallToolResult(content: [TextContent(text: json)]);
}

/// Reads [path] if it exists, otherwise returns null.
String? _readIfExists(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : null;
}

CallToolResult _error(String message) => CallToolResult(isError: true, content: [TextContent(text: message)]);
