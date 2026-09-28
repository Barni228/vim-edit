# VimEdit

A minimal plain-text editor in Rust + Qt 6 ([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

## Vim mode

The editor starts in normal mode. It supports the common vim commands:

- Modes: insert (`i a I A o O`), visual (`v V Ctrl-V`), replace (`R`, `r`), with a
  block, bar or underline cursor to match.
- Visual block (`Ctrl-V`): `I`, `A` and `c` type on every line of the block at
  once, `$A` appends to every line, and `d y p x r ~ u U o O` work on the block.
  A yanked block pastes as a block. In insert mode Ctrl-V still pastes.
- Motions: `h j k l w b e ge W B E 0 ^ $ gg G f t F T ; , % { } H M L n N * #`,
  `Ctrl-D/U/F/B`, all with counts.
- Operators `d c y > < g~ gu gU` with motions and text objects (`iw aw i" a" i( a(`
  `i{ a{ ip ap` and so on), plus `x X s S C D Y p P J r ~ u Ctrl-R .`
- Registers: yanks and deletes stay inside the editor. Use `"+` or `"*` for the
  system clipboard, and `"a`–`"z` for named registers.
- Macros: `q{a-z}` records, `q` stops (`qA` appends), `@{a-z}` runs, `@@` runs
  the last one again and `@:` repeats the last `:` command. A macro stops at the
  first command that fails, so recursive macros end on their own.
- `/`, `?`, `:w`, `:q`, `:q!`, `:wq`, `:x`, `:<line>`, `ZZ`, `ZQ`. Up and Down on
  the command line go through earlier commands or searches that start with what
  you've typed.
- While you type a search, matches are highlighted and the view scrolls to the
  one Enter would jump to. They stay highlighted until you press Esc (or `:noh`).
- The command line can be edited with Left/Right, Home/End, Delete, `Ctrl-W` and
  `Ctrl-U`.

## Hidden text

Select some text and press Cmd+J (Ctrl+J on Windows and Linux) to turn it into a 💩.
The 💩 acts like any other character: you can move over it, select it, delete it,
yank it and paste it. Copying it to the system clipboard (`"+y` or Cmd+C) gives
other apps the hidden text, while pasting it back into VimEdit gives the 💩 again.
Press Cmd+J on a 💩 to reveal its text. To peek without revealing it, rest the
mouse on the 💩, or press `gh` with the cursor on it. Hidden text is never saved:
in the file it's a plain 💩.

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
