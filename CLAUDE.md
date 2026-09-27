# CLAUDE.md

VimEdit: a plain-text editor in Rust + Qt 6 via cxx-qt 0.10, with the UI in QML.

## Layout

- `src/main.rs`: creates the app, installs the "Settings…" translator, loads `qml/main.qml`.
- `src/document.rs`: `Document` QObject (QML element) that reads and writes files.
- `src/platform.rs` + `cpp/platform.{h,cpp}`: C++ helpers, namely the macOS `QFileOpenEvent`
  filter and the app-menu translator.
- `qml/main.qml`: the window, the editor (`TextArea`), dialogs and menus.
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
- "Ctrl+," is written as a plain string: Qt maps Ctrl to Cmd on macOS, and
  `StandardKey.Preferences` is empty on Windows.
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
- **Windows**: the MSVC CRT DLLs are copied app-locally, so no VC++ Redistributable is
  needed. `package-windows.ps1` loads the VS dev shell itself; `ilammy/msvc-dev-cmd`
  was removed because it's stuck on Node 20.

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
