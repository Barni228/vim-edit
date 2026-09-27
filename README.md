# VimEdit

A minimal plain-text editor in Rust + Qt 6 ([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

## Vim mode

The editor starts in normal mode. It supports the common vim commands:

- Modes: insert (`i a I A o O`), visual (`v V`), replace (`R`, `r`), with a block,
  bar or underline cursor to match.
- Motions: `h j k l w b e ge W B E 0 ^ $ gg G f t F T ; , % { } H M L n N * #`,
  `Ctrl-D/U/F/B`, all with counts.
- Operators `d c y > < g~ gu gU` with motions and text objects (`iw aw i" a" i( a(`
  `i{ a{ ip ap` and so on), plus `x X s S C D Y p P J r ~ u Ctrl-R .`
- Registers: yanks and deletes stay inside the editor. Use `"+` or `"*` for the
  system clipboard, and `"a`–`"z` for named registers.
- `/`, `?`, `:w`, `:q`, `:q!`, `:wq`, `:x`, `:<line>`, `ZZ`, `ZQ`.

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
