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
- `qml/FindBar.qml`: the VS Code-style find and replace bar (Cmd+F, Cmd+Option+F).
- `qml/SettingsWindow.qml`: the Settings window (Cmd+,): font size, line numbers, theme.
- `qml/ConfirmDialog.qml`: the `:confirm` question, a box over the editor with
  vim's [Y]es/(N)o/(C)ancel (keys `y`, `n`, `c`/Esc; Left/Right move the
  highlight, Enter answers it) and selectable text.
- `qml/HelpPanel.qml`: `:help` (`:h topic`), a box over the editor listing what isn't
  obvious (`:set` forms, search, registers, multiple cursors, hidden text, keys).
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
- **Windows**: `main.rs` sets the Fusion style (`QQuickStyle::setStyle`, unless
  `QT_QUICK_CONTROLS_STYLE` is set; setting that variable from Rust doesn't
  reach Qt, which reads the C runtime's startup copy), because the
  default "Windows" style has no dark theme (FluentWinUI3 left the title bar and
  menus light; Fusion doesn't). Its framed TextArea background is replaced with a
  plain one. The MSVC CRT DLLs are copied app-locally, so no VC++ Redistributable is
  needed. `package-windows.ps1` loads the VS dev shell itself; `ilammy/msvc-dev-cmd`
  was removed because it's stuck on Node 20.

- **Vim**: `Vim.qml` owns the cursor (`vim.cursor` is the character under the block) and
  draws it as an overlay inside the `TextArea`. Insert mode uses the `TextArea`'s own
  cursor (`cursorDelegate`). Outside insert mode the `TextArea` is `readOnly`, so macOS
  doesn't open the accent picker on held keys and only vim edits the text.
  Changing `readOnly` makes the editor scroll to a stale cursor position, so
  `setMode` restores the view and then scrolls only if the cursor is out of it
  (`showCursor`). Vim keeps its
  own undo stack (diffs per change), so native undo (Cmd+Z) is routed to it. Only the
  `"+`/`"*` registers use the system clipboard, via `Document.clipboardText()`.
- **Macros**: typed keys are recorded as tokens (`"<Esc>"`, `"x"`); the register
  keeps them as `keys` next to the text, so literal "<CR>" typed in insert mode
  stays text. `@` puts the keys in `typeahead`, which `runMacro` runs through
  `runKey` with no key event, so vim types insert-mode keys itself (`typeKey`,
  `insertMove`). A failing command (bad keys, failed motion, `showError`)
  empties `typeahead`, and a run stops after `maxMacroKeys` keys.
- **Visual block** (`visualBlock`): the editor's selection can't be a block, so
  it's cleared and `main.qml` draws `vim.blockSpans()`. Columns count characters,
  and `wantCol === Infinity` (after `$`) makes the block reach every line end.
  `I`/`A`/`c` put an extra cursor on each other line (see below); `blockHome`
  makes Esc remove them and go back to the start. Ctrl+V is Paste on Windows,
  so `handleKey` lets it through as `<C-v>` outside insert mode; in insert mode
  it pastes on every OS. Likewise Ctrl+Y (Redo on Windows, Paste in Qt's
  macOS bindings) scrolls outside insert mode.
- **Multiple cursors**: `vim.cursors` holds the extra ones (Alt+click via a
  `MouseArea` over the editor, which passes plain clicks through). The editor
  knows one cursor, so with extras vim handles insert-mode typing and arrows
  itself: `editAll` runs an edit at every cursor from last to first, and
  `replaceRange` (or `trackEdit`, for the editor's own edits) moves the cursors
  after each edit. Leaving insert mode removes them. In normal mode `moveBy`
  moves them too (`moveCursors`; each keeps its own `col` for j/k, and
  `motion(..., quiet)` doesn't scroll), and `execute` runs operators and
  `everyCursorActions` once per cursor (`atEveryCursor`), swapping in each
  extra cursor's own `registers`. `main.qml` draws them: bars in insert mode,
  blocks otherwise, blinking with the real bar via `editor.blinkOn`.
- **Hidden text** (Cmd+J): the document holds a plain 💩, and `Vim.hidden` keeps
  the text beside it as `{ at, item }` entries. Vim's edits shift the entries in
  `replaceRange` (pass the entries of inserted text), editor-made edits (insert
  mode typing) by diffing against `trackedText`. Registers, undo steps and the
  `"+` register carry entries; the clipboard gets the revealed text as plain
  text and the entries as JSON in `application/x-vimedit-data`. Qt's native
  Backspace deletes one code point, so vim handles Backspace in insert mode, and
  cursor steps go through `charStart`/`charEnd` (never `±1`) so they don't split
  an emoji.
  Resting the mouse on a 💩 (a `HoverHandler`) or `gh` shows its text in `hover`,
  a VS Code-style box in the window's `Overlay` (so the editor doesn't clip it).
  Its text is a read-only `TextEdit` that never takes focus, so keys stay with
  the editor, which forwards Copy to it. Any other key, a scroll or an edit
  hides it; one the mouse opened also hides 300 ms after the pointer is on
  neither the 💩 nor the box (and isn't dragging a selection).
- **Warnings and errors** (`diagnostics` in `main.qml`): the whole words
  "warning" and "error", in any case, get a VS Code-style squiggle, found
  in the visible lines like the search highlights, and their line shows a
  message four spaces after its end (an error's before a warning's). The
  `hover` box shows the message (with an icon) as it does a 💩's text:
  `targetAt` finds either, `targetUnder` also finds the message after the
  line (the box then points at it), and `gh` asks for whatever is under
  the cursor.
- **Quitting**: `:q` with unsaved changes fails (E37); `:confirm q` asks
  instead, in a `ConfirmDialog` rather than a `MessageDialog` (which is
  native on macOS, can't use the editor's font or vim's keys, and warns that
  the macOS style can't be customized). Saving a file that has no path
  opens the Save dialog, so `root.save(quit)` sets `quitAfterSave` to quit
  once it's saved (also for `:wq`).
- **Find bar**: moving to a match moves vim's cursor to its start
  (`vim.jumpTo`, which leaves visual mode and breaks an insert); it doesn't
  select it. The current match is the one starting at the cursor
  (`currentStart`), however the cursor got there (e.g. an undo). Its matches take over the search highlights while it's open;
  Esc in normal mode (`highlightsCleared`) closes it. Replace All is one
  `replaceRange` over the first to last match, keeping hidden text between
  matches. On Windows, Ctrl+F is Find, not vim's page down.
- **Zoom**: every text in the app grows and shrinks with View > Zoom
  (Cmd+ / Cmd- / Cmd+0), not just the editor: the status line, the hover box,
  the find bar and its tooltips. Text in the editor's font uses
  `editor.font`; other UI (like `FindBar`) scales its sizes by `zoom`
  (`root.fontSize / root.defaultFontSize`). New UI must do the same.
- **Line height**: emoji come from a taller font and would make their line
  taller, so `fixLineFormat` gives every block a fixed height (a block format,
  reapplied after setting `editor.text`). Qt puts a fixed-height line's baseline
  at 4/5 of it, so to center the text the block gets a shorter line plus a
  bottom margin that makes up `root.lineHeight` (`root.textBaseline` is where
  the baseline ends up). Qt's selection and `positionToRectangle` still use the
  natural (taller) height on emoji lines, so VimEdit draws the selection itself
  (under the text, `z: -0.5`), and all overlays use `editor.cellAt` (the whole
  line, snapped to the line grid). The current-line highlight is at `z: -0.6`.
- **Line numbers** (`:set nu`/`rnu`, `vim.number`/`vim.relativeNumber`): the
  `gutter` is a child of the `TextArea` (so it scrolls with the text), kept at
  `contentX` and drawn over text scrolled under it. The styles hard-code
  `leftPadding` (7 on macOS, `padding + 4` in Fusion), so the editor keeps the
  style's value and adds the gutter width (the digits and two spaces) to it.
  The gutter has the editor's background color. Only visible lines get a row.
- **Settings**: `settings` (a QtCore `Settings` in `main.qml`) holds the
  saved values; `root.fontSize` (an alias of `vim.fontSize`, for `:set fs`),
  `root.theme` and `vim.number`/`relativeNumber` are the ones in use, bound to
  them at startup. The Settings window shows the ones in use and changes both
  (`changeSetting`). The zoom and `:set fs`/`nu`/`rnu` change only the ones in
  use, and `keepChange` saves them when `settings.keepChanges` is on (the
  "Zoom and :set" setting, off by default). The theme sets
  `Application.styleHints.colorScheme` (Qt 6.8+), which also switches the
  palette, title bar and menus; "system" unsets it. The window's size follows
  the zoom, so it isn't resizable.
- **Help**: `HelpPanel.sections` is the `:help` text, with the topics each
  section answers (`:h macros`). When adding a feature or key that isn't
  standard vim or obvious, add it there. Wrapped text settles over the first
  frames, so `:h topic` keeps scrolling to its section as the layout changes,
  until the user scrolls. Each text is a read-only `TextEdit` (`HelpText`)
  that selects on its own (selecting one clears the last, and a
  `PointHandler` on top clears it on a press elsewhere, only watching the
  press; a `MouseArea` there would show its arrow over the I-beam). The
  keys stay with the help, which forwards Copy. A drag selects, so its
  `Flickable` isn't interactive and a `WheelHandler` scrolls it.
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
