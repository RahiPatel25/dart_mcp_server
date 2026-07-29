# Flutter Dart MCP Server – Overview

I created a **Dart-based MCP server for Flutter projects** that helps AI assistants understand and analyze our codebase through simple prompts.

The MCP server runs **locally on each developer's machine** because it needs direct access to the current Flutter project files. This keeps our source code private, avoids maintaining a shared server, removes authentication/deployment overhead, and ensures the AI always analyzes the latest local changes.

A remote/shared MCP server would require managing multiple projects, branches, access permissions, and code synchronization. Since every developer works with different projects and local changes, running it locally provides a simpler and more reliable workflow.

## Use Cases

With this MCP server, developers can quickly:

- Understand an existing Flutter project (`analyze_project`)
- List all application screens (`list_screens`)
- Find unused widgets and assets (`find_unused_widgets`, `find_unused_assets`)
- Identify missing localization (`find_unlocalized_screens`)
- Find large widgets that need refactoring (`find_large_widgets`)
- Verify MCP connectivity (`hello`)

## Current Status

**Currently, this MCP server is in beta.**

The current version focuses on static Flutter code analysis and providing useful insights to developers. We are collecting feedback and identifying areas where it can become more powerful and useful for daily development.

## Future Improvements

Some possible future enhancements:

- **Deeper code understanding**
  Improve analysis by using Dart AST/type resolution to reduce false positives and provide more accurate results.

- **Architecture insights**
  Detect project patterns, feature structures, dependency flow, and suggest architecture improvements.

- **Code quality checks**
  Add tools for detecting code smells, duplicate code, complex logic, and potential performance issues.

- **Test coverage insights**
  Analyze missing tests, untested screens, and critical areas that need better coverage.

- **AI-powered recommendations**
  Provide actionable suggestions such as refactoring ideas, optimization tips, and migration guidance.

- **CI/CD integration**
  Run MCP analysis automatically during pull requests to catch issues before merging.

The goal is to make AI-assisted Flutter development faster by giving AI assistants better project context while keeping everything secure and local.
