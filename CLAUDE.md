# CLAUDE.md

VimEdit: a plain-text editor in Rust + Qt 6 via cxx-qt 0.10, with the UI in QML.

## Layout

- `src/main.rs`: creates the app, installs the "Settings…" translator, loads `qml/main.qml`.
- `src/document.rs`: `Document` QObject (QML element) that reads and writes files.
- `src/platform.rs` + `cpp/platform.{h,cpp}`: C++ helpers, namely the macOS `QFileOpenEvent`
  filter, the app-menu translator, and clipboard access.
- `qml/main.qml`: the window, the editor (`TextArea`), the vim cursor and status line,
  dialogs and menus.
- `qml/Vim.qml`: the vim emulation (modes, motions, operators, registers, undo, `:` and
  `/` command line). It drives the `TextArea` through `insert`/`remove`/`select`.
- `scripts/`: `bundle-macos.sh` (makes the `.app`), `package-macos.sh` (makes the `.dmg`),
  `package-windows.ps1` (runs windeployqt, then builds the Inno Setup installer).
- `packaging/`: `Info.plist` (with `@VERSION@` placeholder), `installer.iss`, and a
  dev-only Windows file-association script.

## Build and test

- Local Qt comes from Homebrew (`qtbase`, `qtdeclarative`); `qmake` must be on `PATH`.
- `cargo build` / `cargo run -- file.txt`. To test Open With locally, run
  `scripts/bundle-macos.sh`; it registers the `.app` with LaunchServices.
- Menus can be inspected and clicked with `osascript` / System Events on process `vim-edit`
  (or `VimEdit` when run from the bundle). Screen capture isn't permitted.

## Non-obvious decisions

- **Menus**: QtQuick Controls menus have no `role` property, so macOS uses
  `Qt.labs.platform` MenuBar with `PreferencesRole`/`QuitRole`, which moves the items
  into the app menu. Windows and Linux use an in-window Controls `MenuBar`. Both are
  created in `Component.onCompleted`, so only one exists at a time.
- Qt titles the PreferencesRole item "Preferences..."; a `QTranslator` for the
  `MAC_APPLICATION_MENU` context renames it to "Settings…".
- **Shortcuts**: use `StandardKey` where Qt has a binding. On macOS
  `StandardKey.ZoomIn` also fires on Cmd+= (tested), even though Qt lists only
  Ctrl++; on Windows it doesn't, so that menu uses "Ctrl+=" plus a `Shortcut` for
  Ctrl++. The Windows/Linux menu
  writes "Ctrl+," and "Ctrl+Q" as plain strings, because `Preferences` and `Quit` have no
  Ctrl binding on Windows. "Ctrl+0" has no `StandardKey`. In strings, Qt maps Ctrl to
  Cmd on macOS.
- **Open With**: macOS delivers a `QFileOpenEvent` (argv holds no path), which the C++
  filter forwards to `Document.openFile` by method name. Windows and Linux pass the
  path in argv, which `startupFile()` reads.
- **cxx-qt**: bridges containing a `#[qobject]` declare `QObject` implicitly (declaring
  it again fails); plain bridges like `platform.rs` must declare it themselves.
  `#[auto_cxx_name]` turns snake_case into camelCase for QML.
- **macOS**: `MACOSX_DEPLOYMENT_TARGET` is set to 13.0 in `bundle-macos.sh`. Without it,
  cc and rustc target the build machine's macOS version. `macdeployqt` breaks
  signatures, so the bundle is re-signed ad hoc. The Homebrew-only `macdeployqt` errors
  about QtSvg are harmless.
- **Windows**: `main.rs` sets `QT_QUICK_CONTROLS_STYLE=Fusion`, because the
  default "Windows" style has no dark theme (FluentWinUI3 left the title bar and
  menus light; Fusion doesn't). Its framed TextArea background is replaced with a
  plain one. The MSVC CRT DLLs are copied app-locally, so no VC++ Redistributable is
  needed. `package-windows.ps1` loads the VS dev shell itself; `ilammy/msvc-dev-cmd`
  was removed because it's stuck on Node 20.

- **Vim**: `Vim.qml` owns the cursor (`vim.cursor` is the character under the block) and
  draws it as an overlay inside the `TextArea`. Insert mode uses the `TextArea`'s own
  cursor (`cursorDelegate`). Outside insert mode the `TextArea` is `readOnly`, so macOS
  doesn't open the accent picker on held keys and only vim edits the text. Vim keeps its
  own undo stack (diffs per change), so native undo (Cmd+Z) is routed to it. Only the
  `"+`/`"*` registers use the system clipboard, via `Document.clipboardText()`.
- **Hidden text** (Cmd+J): the document holds a plain 💩, and `Vim.hidden` keeps
  the text beside it as `{ at, item }` entries. Vim's edits shift the entries in
  `replaceRange` (pass the entries of inserted text), editor-made edits (insert
  mode typing) by diffing against `trackedText`. Registers, undo steps and the
  `"+` register carry entries; the clipboard gets the revealed text as plain
  text and the entries as JSON in `application/x-vimedit-data`. Qt's native
  Backspace deletes one code point, so vim handles Backspace in insert mode, and
  cursor steps go through `charStart`/`charEnd` (never `±1`) so they don't split
  an emoji.
- **Line height**: emoji come from a taller font and would make their line
  taller, so `fixLineHeight` gives every block a fixed height (a block format,
  reapplied after setting `editor.text`). Qt's selection and `positionToRectangle`
  still use the natural (taller) height on emoji lines, so VimEdit draws the
  selection itself (under the text, `z: -0.5`), and all overlays use
  `editor.bandAt` (the font's height, snapped to the line grid).
- Don't make a QML binding depend on something by reading it as a bare statement
  (`editor.revision;`): the app's QML is compiled ahead of time, which can drop it,
  though `qmltestrunner` keeps it. Use the value, e.g. `TextMetrics.advanceWidth`
  instead of `FontMetrics.advanceWidth()`, or refresh imperatively.
- To test `Vim.qml` without the Rust app, load it from a `qmltestrunner` test
  (`import "file:/abs/path/qml"`) with a `TextArea` and send keys with `keyClick`.

## CI and releases

- `.github/workflows/build.yml` builds a `.dmg` (macos-latest, arm64 only) and a setup
  `.exe` (windows-latest) on every push. `v*` tags also publish a GitHub release.
- The Qt version is pinned per OS. macOS uses 6.11, because 6.8's headers fail with
  newer Apple clang. Windows uses 6.10, because Qt 6.11 for Windows uses a repository
  layout that aqtinstall 3.3 can't read. Move Windows up once aqtinstall supports it.
- Keep actions on Node 24 releases (checkout v7, upload-artifact v7, download-artifact
  v8, action-gh-release v3).
- Releases: `cargo release <level> --execute`. It's configured in `Cargo.toml` to skip
  crates.io and only run on `main`, and it needs a clean working tree.
