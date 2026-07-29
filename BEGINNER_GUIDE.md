# Flutter MCP Server – Quick Start Guide

A lightweight MCP server that provides **7 static analysis tools** for Flutter projects. It runs locally on your machine and analyzes only the Flutter project you connect it to.

---

# 1. Prerequisites

Before you begin, ensure you have:

- **FVM** installed
- The correct **Flutter/Dart SDK** (from `.fvmrc`)
- A local copy of the `flutter_mcp_server` project

---

# 2. One-Time Setup

Build the MCP server:

```bash
cd flutter_mcp_server
fvm install
fvm dart pub get
mkdir -p build
fvm dart compile exe bin/flutter_mcp_server.dart -o build/flutter_mcp_server
```

After the build completes, note the executable path:

```text
/path/to/flutter_mcp_server/build/flutter_mcp_server
```

> **Note:** FVM is only required for building the executable. Once built, the server runs without Flutter or Dart installed.

---

# 3. Connect the MCP

From inside the Flutter project you want to analyze:

```bash
cd /path/to/your/flutter_project

claude mcp add flutter --scope local \
  --env FLUTTER_PROJECT_PATH="$(pwd)" \
  -- /path/to/flutter_mcp_server/build/flutter_mcp_server
```

Verify the connection:

```bash
claude mcp list
claude mcp get flutter
```

You should see:

- ✅ Server connected
- ✅ `FLUTTER_PROJECT_PATH` pointing to your Flutter project

---

# 4. Available Tools

| Tool                       | Purpose                                                                                                                      |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `analyze_project`          | Analyze project architecture, Flutter/Dart versions, dependencies, state management, routing, networking, localization, etc. |
| `list_screens`             | List all screens/pages/views in the project                                                                                  |
| `find_unused_widgets`      | Find widgets that are never referenced                                                                                       |
| `find_unused_assets`       | Find unused assets from `pubspec.yaml`                                                                                       |
| `find_unlocalized_screens` | Detect screens containing hardcoded user-facing strings                                                                      |
| `find_large_widgets`       | Find widgets with large `build()` methods (default threshold: 100 lines)                                                     |
| `hello`                    | Simple connectivity test                                                                                                     |

---

# 5. Common Prompts for All 7 Tools

Simply ask your AI assistant using prompts like these:

### 1. `analyze_project`

- `Run analyze_project`
- `Analyze this Flutter project`
- `Give me an overview of this project`
- `What Flutter version, state management, routing, networking, and localization does this project use?`

---

### 2. `list_screens`

- `List all screens in this app`
- `Show me every screen in the project`
- `What screens are available?`

---

### 3. `find_unused_widgets`

- `Find unused widgets`
- `Which widgets are never referenced?`
- `Show me dead widgets I can review`

---

### 4. `find_unused_assets`

- `Find unused assets`
- `Which assets are not used?`
- `Show assets that can potentially be removed`

---

### 5. `find_unlocalized_screens`

- `Find unlocalized screens`
- `Which screens still contain hardcoded strings?`
- `Show screens that need localization`

---

### 6. `find_large_widgets`

- `Find large widgets`
- `Find large widgets over 80 lines`
- `Show build methods larger than 100 lines`
- `Which widgets should be refactored because they're too large?`

> **Note:** If no threshold is provided, the default is **100** lines.

---

### 7. `hello` (Connectivity Test)

- `Run hello`
- `Run hello with my name`
- `Test the MCP connection`

Example:

```text
hello(name: "John")
```

Expected output:

```text
Hello, John!
```

---

# 6. Verify Everything Works

Run either:

```text
Run hello with my name
```

or

```text
Run analyze_project
```

If you receive project information (Flutter version, dependencies, architecture, etc.), the MCP is connected correctly.

---

# 7. Important Notes

- One MCP server analyzes **one Flutter project only**.
- The project is fixed using the `FLUTTER_PROJECT_PATH` environment variable.
- **Always use `--scope local`** (recommended) so the server only loads for that project.
- Tools perform **static analysis**, so review results before deleting widgets or assets.
- Generated files (`.g.dart`, `.freezed.dart`, `.mocks.dart`, `.config.dart`) are automatically ignored.
- If you modify the MCP server code, rebuild the executable and reconnect/restart your MCP session.
