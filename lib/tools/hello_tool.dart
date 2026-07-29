import 'dart:async';

import 'package:dart_mcp/server.dart';

final helloTool = Tool(
  name: 'hello',
  description: 'Returns a friendly greeting for the given name.',
  inputSchema: Schema.object(
    properties: {'name': Schema.string(description: 'Name to greet')},
    required: ['name'],
  ),
);

/// Handles calls to [helloTool].
FutureOr<CallToolResult> handleHello(CallToolRequest request) {
  final name = request.arguments!['name'] as String;
  return CallToolResult(content: [TextContent(text: 'Hello $name 👋')]);
}
