# VimEdit

A minimal plain-text editor in Rust + Qt 6 (via [CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

## Requirements

- Rust (stable)
- Qt 6 with Qt Quick / Qt Quick Controls / Qt Quick Dialogs, and `qmake` on `PATH`
  (or set `QMAKE=/path/to/qmake`)
  - macOS: `brew install qtbase qtdeclarative`
  - Windows: Qt online installer (MSVC kit), plus the MSVC toolchain

## Run

```sh
cargo run -- path/to/file.txt
```

## Installers

CI (`.github/workflows/build.yml`) builds both installers on every push and
uploads them as workflow artifacts. Pushing a `v*` tag also publishes them as
a GitHub release.

- **macOS**: `dist/VimEdit-<version>-macos-arm64.dmg`, a drag-to-Applications
  disk image. Built locally with `scripts/package-macos.sh`.
- **Windows**: `dist/VimEdit-<version>-windows-x64-setup.exe`, an Inno Setup
  installer that registers VimEdit under *Open with* for `.txt` files. Built
  locally with `scripts/package-windows.ps1` from a Developer PowerShell (it
  needs Qt on `PATH` and Inno Setup 6).

The builds are not code-signed. On first launch, Windows SmartScreen needs
*More info → Run anyway*. macOS needs *System Settings → Privacy & Security →
Open Anyway*, or `xattr -dr com.apple.quarantine /Applications/VimEdit.app`.

## Open With during development

**macOS**: `scripts/bundle-macos.sh` builds `target/release/VimEdit.app`
against the local Qt and registers it with LaunchServices, so it shows up in
Finder's *Open With* menu.

**Windows**: build, copy the Qt runtime next to the exe, and register the
per-user file association:

```powershell
cargo build --release
windeployqt --qmldir qml target\release\vim-edit.exe
powershell -ExecutionPolicy Bypass -File packaging\windows\register-file-association.ps1
```

## Layout

- `src/main.rs`: creates the application and loads the QML
- `src/document.rs`: `Document` QObject for reading and saving files
- `src/platform.rs`, `cpp/platform.cpp`: macOS file-open events and the
  "Settings…" app-menu title
- `qml/main.qml`: the window, editor, and menus (native on macOS, in-window
  elsewhere)
