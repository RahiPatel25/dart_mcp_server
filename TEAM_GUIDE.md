# flutter_mcp_server — Team Guide

A local [MCP](https://modelcontextprotocol.io) server that gives your AI assistant seven
static-analysis tools for Flutter codebases: project profile, screen inventory, dead widgets, dead
assets, unlocalized screens, oversized `build` methods.

It runs on your machine as a subprocess of your editor/CLI, reads the source on your disk, and sends
nothing anywhere. There is no service to deploy and no credentials to manage.

> **The one rule that explains everything else:** one server instance analyzes exactly one Flutter
> project. The project is fixed at launch by the `FLUTTER_PROJECT_PATH` environment variable. Tools
> never take a path argument, so nobody — including the AI — can redirect a running server at another
> directory. To cover two projects, you register two servers.

This guide is for *using* the server. If you want to change it, see [`README.md`](README.md).

---

## 1. One-time setup

**Prerequisites:** [fvm](https://fvm.app) and the Dart/Flutter SDK pinned in `.fvmrc`.

```bash
git clone <REPO_URL> flutter_mcp_server
cd flutter_mcp_server
fvm install
fvm dart pub get
mkdir -p build
fvm dart compile exe bin/flutter_mcp_server.dart -o build/flutter_mcp_server
```

> **Note:** this project is not yet in version control, so `<REPO_URL>` does not exist. Until it's
> pushed, copy the folder directly and start from `fvm install`.

Every dependency is pure Dart (`path`, `dart_mcp`, `analyzer`, `yaml` — no `flutter` dependency), so
the output is a single self-contained ~9 MB executable. **fvm is only needed to build it.** Running
it needs nothing installed at all, and startup is instant.

Note the absolute path to your binary — you'll use it in every registration below:

```
/path/to/flutter_mcp_server/build/flutter_mcp_server
```

---

## 2. Register it for your project

Do this **from inside the Flutter project** you want analyzed. `$(pwd)` is expanded by your shell at
registration time, so the server gets a concrete absolute path.

```bash
cd /path/to/your/flutter_project

claude mcp add flutter --scope local \
  --env FLUTTER_PROJECT_PATH="$(pwd)" \
  -- /path/to/flutter_mcp_server/build/flutter_mcp_server
```

Verify:

```bash
claude mcp list          # flutter: … - ✔ Connected
claude mcp get flutter   # check FLUTTER_PROJECT_PATH is the project you expect
```

That's it. Repeat for each project you work on, reusing the same name `flutter` every time.

### Why `--scope local`, and why the name can repeat

Local scope binds the server to the directory you registered it from. It only loads when you're
actually working in that project — so you always see exactly 7 tools, and they always analyze the
code you're looking at. Because the binding is per-directory, the name `flutter` never collides
across projects.

Choose deliberately:

| Scope | Loads when | Use it for |
|---|---|---|
| `local` | you're in that directory (private to you) | **Default.** One entry per project you work on |
| `project` | anyone working in that repo | Sharing the binding with the team via a committed `.mcp.json` |
| `user` | **every session, everywhere** | Rarely worth it here — see below |

**Avoid `--scope user` for this server.** User scope means "available in all your projects," so the
server loads even in sessions that have nothing to do with Flutter. Register 4 projects that way and
all 4 servers load every time — 28 tools permanently in context, four near-identical names to pick
between, and each one silently pinned to a *different* project. That's how you end up running
`find_unused_widgets` against the wrong app.

### Sharing the binding with your team

`--scope project` writes `.mcp.json` into the repo, so teammates get the server automatically:

```bash
cd /path/to/your/flutter_project
claude mcp add flutter --scope project \
  --env FLUTTER_PROJECT_PATH="$(pwd)" \
  -- /path/to/flutter_mcp_server/build/flutter_mcp_server
```

Caveat: both paths are absolute and machine-specific. This works cleanly only if everyone keeps the
repo and the binary at the same locations. Otherwise have each person register at `local` scope.

### Other clients

Claude Desktop, Cursor, and Windsurf use a JSON config with an `mcpServers` block:

```json
{
  "mcpServers": {
    "flutter": {
      "command": "/path/to/flutter_mcp_server/build/flutter_mcp_server",
      "env": { "FLUTTER_PROJECT_PATH": "/path/to/your/flutter_project" }
    }
  }
}
```

These configs are global, so give each project a distinct name (`flutter-checkout`,
`flutter-admin`) — the per-directory trick isn't available.

---

## 3. The tools

| Tool | Answers | Arguments |
|---|---|---|
| `analyze_project` | What is this project built with? Name, Flutter/Dart versions, state management (Riverpod, BLoC, Provider, GetX, MobX…), router, networking, localization, dependency counts. Returns JSON | none |
| `list_screens` | What screens exist? Classes named `*Screen`/`*Page`/`*View`, or that build a `Scaffold`/`CupertinoPageScaffold` | none |
| `find_unused_widgets` | Which widgets in `lib/` are never referenced anywhere (`lib/`, `test/`, `bin/`, `example/`)? | none |
| `find_unlocalized_screens` | Which screens have hardcoded user-facing strings and no localization? | none |
| `find_unused_assets` | Which bundled assets (pubspec `flutter/assets`) are never referenced from Dart? | none |
| `find_large_widgets` | Which `build` methods are too long to maintain? Sorted largest-first, with total class size | `threshold` — optional int, min 1, **default 100** |
| `hello` | Connectivity smoke test | `name` — **required** string |

`find_unlocalized_screens` recognizes `AppLocalizations.of(context)`, `context.l10n`,
`S.of(context)`/`S.current`, easy_localization `.tr()`, and `Intl.message`.

Generated files (`.g.dart`, `.freezed.dart`, `.mocks.dart`, `.config.dart`) are excluded from scans.

---

## 4. Everyday use

You never pass a path — the server already knows its project. Just ask:

- *"run analyze_project"*
- *"list the screens in this app"*
- *"find large widgets over 80 lines"* → calls `find_large_widgets` with `threshold: 80`
- *"are there any unused assets I can delete?"*
- *"which screens still have hardcoded strings?"*

Type `/mcp` in a session to see the connected servers and their tools.

Some combinations worth knowing:

- **Joining a project** — `analyze_project` then `list_screens` gives you the stack and the surface
  area in two calls.
- **Before a refactor sprint** — `find_large_widgets` with a threshold tuned to your codebase
  (try 150 on an older project, 60 if you're strict) to rank candidates by pain.
- **Pre-release cleanup** — `find_unused_assets` and `find_unused_widgets` to find bundle weight and
  dead code. Read §5 first.
- **Localization push** — `find_unlocalized_screens` to scope the work.

---

## 5. Read the results critically

Every tool is a **syntactic** scan — it parses source text and does not resolve types, follow class
hierarchies, or evaluate code. That makes it fast and dependency-free, and it means the output is a
prioritized list to investigate, not a verdict. Know the blind spots before you delete anything.

**`find_unused_widgets` — verify before deleting.** Only the direct superclass is matched, and only
literal references count. Expect false positives for widgets referenced by string route names or
reflection, and for widgets exported as public API of a package or module. Grep for the name before
removing it.

**`find_unused_assets` — verify before deleting.** An asset counts as used when its full relative
path *or* its file name appears in a string literal. Assets built up dynamically
(`'assets/icons/$name.png'`) have no literal filename and will be reported as unused. Also, asset
*directory* entries in pubspec resolve non-recursively, matching Flutter's own bundling behaviour.
All file types are checked (images, fonts, JSON, Lottie, audio); only OS junk (`.DS_Store`,
`Thumbs.db`, `.gitkeep`) is skipped.

**`find_unlocalized_screens` — a starting point, not an audit.** Only user-visible text in common
`Text` widgets and text arguments (`title`, `label`, `hintText`, …) is inspected. Dynamic and
interpolated strings are ignored. A clean result does not mean a screen is fully localized.

**`list_screens` and `find_large_widgets` — custom base classes aren't followed.** Both detect
`StatelessWidget`, `StatefulWidget`, and common Riverpod/hooks bases. If your team has
`class BaseScreen extends StatefulWidget` and screens extend `BaseScreen`, those screens won't be
detected. For `StatefulWidget`, the `build` is measured in the companion `State` but attributed to
the widget.

**`analyze_project` — where the Flutter version comes from.** Resolution order is FVM config
(`.fvmrc`, `.fvm/fvm_config.json`), then `pubspec.lock`, then `pubspec.yaml`. The resolved package
count comes from `pubspec.lock` when present. A project with no FVM config and no lockfile will
report less precise versions.

---

## 6. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Server not connected / won't start | It exits with code **64** and a message on stderr when `FLUTTER_PROJECT_PATH` is unset, points at a nonexistent directory, or points at a directory with no `pubspec.yaml`. Run `claude mcp get <name>` and check the env value. This is deliberate — it fails loudly rather than silently serving an empty project |
| Wrong project's results | `claude mcp get <name>` and read back `FLUTTER_PROJECT_PATH`. If several `flutter-*` servers are registered, you likely called the wrong one |
| Server shows up in unrelated projects | It's registered at user scope. `claude mcp remove <name> -s user`, then re-add from inside the project with `--scope local` |
| Edited a tool, changes don't appear | The registered binary is a compiled snapshot. Recompile (`fvm dart compile exe bin/flutter_mcp_server.dart -o build/flutter_mcp_server`), then reconnect via `/mcp` or restart the session |
| `No lib/ directory found under: …` | `FLUTTER_PROJECT_PATH` points at a parent folder or a monorepo root instead of the Flutter package itself. It must be the directory containing `pubspec.yaml` and `lib/` |
| Registration silently misbehaves | Quote paths containing spaces: `--env FLUTTER_PROJECT_PATH="/Users/me/My Projects/app"`. Unquoted, the path splits into arguments |

**There is no enable/disable toggle.** As of Claude Code 2.1.220, `claude mcp` supports only `add`
and `remove` — to turn a server off you remove it and re-add it later. This is the main practical
reason to prefer local scope: correct servers load automatically and wrong ones never load, so you
never need a toggle.

---

## 7. Contributing

```
lib/analysis/   pure analysis logic — no MCP dependency, unit-tested
lib/tools/      thin MCP wrappers: schema, argument validation, output formatting
lib/server/     tool registration
bin/            entrypoint: env validation + stdio wiring
test/           unit tests for the analysis layer
```

The layering is the point: analysis functions take a `Map<String, String>` of file contents and
return plain data, so they're tested without spawning a server. Put logic in `lib/analysis/` with
tests, keep `lib/tools/` to schema and formatting, and register in `lib/server/flutter_server.dart`.

```bash
fvm dart analyze
fvm dart test
```

Recompile and reconnect after any change. See [`README.md`](README.md) for details.
