# VimEdit

A minimal plain-text editor in Rust + Qt 6 ([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

## Install

Download the installer from the
[latest release](https://github.com/Barni228/vim-edit/releases/latest).

**macOS**: open the `.dmg` and drag VimEdit to Applications. The app isn't
signed, so clear the quarantine flag before the first launch:

```sh
xattr -cr "/Applications/VimEdit.app"
```

**Windows**: run the setup `.exe`. If SmartScreen blocks it, choose
*More info → Run anyway*.

## Build

Needs Rust and Qt 6 with `qmake` on `PATH` (macOS: `brew install qtbase qtdeclarative`).

```sh
cargo run -- path/to/file.txt
```

## Release

```sh
cargo release patch --execute   # or minor / major
```

This bumps the version, tags it and pushes. CI then builds both installers
and publishes them as a GitHub release.
