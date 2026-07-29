import 'package:dart_mcp/server.dart';

import 'package:flutter_mcp_server/tools/analyze_project_tool.dart';
import 'package:flutter_mcp_server/tools/find_large_widgets_tool.dart';
import 'package:flutter_mcp_server/tools/find_unlocalized_screens_tool.dart';
import 'package:flutter_mcp_server/tools/find_unused_assets_tool.dart';
import 'package:flutter_mcp_server/tools/find_unused_widgets_tool.dart';
import 'package:flutter_mcp_server/tools/hello_tool.dart';
import 'package:flutter_mcp_server/tools/list_screens_tool.dart';

base class FlutterMcpServer extends MCPServer with ToolsSupport {
  FlutterMcpServer(super.channel, {required String projectRoot})
    : super.fromStreamChannel(
        implementation: Implementation(name: 'flutter_mcp_server', version: '1.0.0'),
        instructions: 'MCP server providing tools for Flutter projects.',
      ) {
    // The project tools are bound to a single configured project — the root is
    // injected into each handler so callers never supply a path.
    registerTool(helloTool, handleHello);
    registerTool(findUnusedWidgetsTool, (r) => handleFindUnusedWidgets(r, projectRoot));
    registerTool(findUnlocalizedScreensTool, (r) => handleFindUnlocalizedScreens(r, projectRoot));
    registerTool(analyzeProjectTool, (r) => handleAnalyzeProject(r, projectRoot));
    registerTool(listScreensTool, (r) => handleListScreens(r, projectRoot));
    registerTool(findUnusedAssetsTool, (r) => handleFindUnusedAssets(r, projectRoot));
    registerTool(findLargeWidgetsTool, (r) => handleFindLargeWidgets(r, projectRoot));
  }
}
