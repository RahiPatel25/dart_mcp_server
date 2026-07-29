import 'package:dart_mcp/server.dart';
import 'package:flutter_mcp_server/tools/hello_tool.dart';
import 'package:test/test.dart';

void main() {
  test('handleHello greets the given name', () async {
    final result = await handleHello(
      CallToolRequest(name: 'hello', arguments: {'name': 'World'}),
    );

    expect(result.isError, isNot(true));
    expect(result.content, hasLength(1));
    expect((result.content.single as TextContent).text, 'Hello World 👋');
  });
}
