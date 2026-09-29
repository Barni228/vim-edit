# VimEdit

A minimal plain-text editor in Rust + Qt 6 ([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

## Vim mode

The editor starts in normal mode. It supports the common vim commands, and
`:help` (or `:h`) lists the ones that aren't standard vim or aren't obvious:
`:set` and its forms, search, registers and macros, multiple cursors, hidden
text and other keys. `:h topic` goes straight to one, e.g. `:h set` or
`:h macros`.

- Modes: insert (`i a I A o O`), visual (`v V Ctrl-V`), replace (`R`, `r`), with a
  block, bar or underline cursor to match.
- Visual block (`Ctrl-V`): `I`, `A` and `c` type on every line of the block at
  once, `$A` appends to every line, and `d y p x r ~ u U o O` work on the block.
  A yanked block pastes as a block. In insert mode Ctrl-V still pastes.
- Multiple cursors: Alt-click (Option-click on macOS) adds a cursor, or removes
  one. In insert mode, typing, Backspace, Delete, Enter, paste and the arrow keys
  work at every cursor, and Esc goes back to one cursor. In normal mode motions,
  operators and edits (`w`, `dw`, `x`, `r`, `R`, `Ctrl-A`, `p`, `.`, `i`, `o` and so
  on) happen at every cursor, as one undo step. Each cursor has its own
  registers, so `yyp` copies every cursor's line. Esc or a plain click removes
  them. The status line shows MULTI CURSOR while there's more than one.
- Motions: `h j k l w b e ge W B E 0 ^ $ gg G f t F T ; , % { } H M L n N * #`,
  `Ctrl-D/U/F/B`, all with counts.
- Operators `d c y > < g~ gu gU g?` with motions and text objects (`iw aw i" a" i( a(`
  `i{ a{ ip ap` and so on), plus `x X s S C D Y p P J gJ r ~ u Ctrl-R . gv`
- `Ctrl-A` / `Ctrl-X` add to or subtract from the number under or after the
  cursor. `Ctrl-E` / `Ctrl-Y` scroll a line, and `zz zt zb` put the cursor's line
  in the middle, top or bottom of the view.
- Registers: yanks and deletes stay inside the editor. Use `"+` or `"*` for the
  system clipboard, and `"a`–`"z` for named registers.
- Macros: `q{a-z}` records, `q` stops (`qA` appends), `@{a-z}` runs, `@@` runs
  the last one again and `@:` repeats the last `:` command. A macro stops at the
  first command that fails, so recursive macros end on their own.
- `/`, `?`, `:w`, `:q`, `:q!`, `:wq`, `:x`, `:<line>`, `ZZ`, `ZQ`, `:noh`, `:help`.
  Up and Down on the command line go through earlier commands or searches that
  start with what you've typed.
- Search patterns are JavaScript regular expressions, not vim's, and match case
  (`\bword\b`, `(a|b)+`). While you type a search, matches are highlighted and
  the view scrolls to the one Enter would jump to. They stay highlighted until
  you press Esc (or `:noh`).
- `:set number` (`nu`), `:set relativenumber` (`rnu`) and `:set fontsize=16`
  (`fs`), with vim's forms: `nonu`, `nu!`, `nu?`, `nu&`, `fs+=2`, `fs-=2` and so
  on. Plain `:set` lists the options that aren't at their default.
- The command line can be edited with Left/Right, Home/End, Delete, `Ctrl-W` and
  `Ctrl-U`.

## Find and replace

Cmd+F opens a find bar like VS Code's, and Cmd+Option+F (Ctrl+H on Windows and
Linux) opens it with a replace field. Enter and Shift+Enter go to the next and
previous match, which moves vim's cursor there, and so do Cmd+G and Shift+Cmd+G
(F3 and Shift+F3, or Ctrl+G and Ctrl+Shift+G, on Windows and Linux), even with
the editor focused. In the replace field Enter replaces the current match, and
Cmd+Enter (Ctrl+Alt+Enter) replaces them all. Ctrl+Option+C, W and R (Alt+C, W
and R) toggle Match Case, Match Whole Word and Use Regular Expression. Esc
closes it.

## Settings

Cmd+, (Ctrl+, on Windows and Linux) opens Settings: font size, line numbers
(off, on, relative or hybrid) and theme (system, light or dark). Changes apply
at once and are saved. Each setting has a button that resets it, and Restore
Defaults resets them all.

View > Zoom In, Zoom Out and Actual Size (Cmd+= / Cmd+- / Cmd+0) change the font
size, and all the text in the app follows it. The zoom and `:set` change the
font size and line numbers only until VimEdit quits, unless Settings > Zoom and
:set is set to Change Settings.

Settings are kept in `~/Library/Preferences/com.vimedit.VimEdit.plist` on macOS,
the registry (`HKEY_CURRENT_USER\Software\VimEdit\VimEdit`) on Windows, and
`~/.config/VimEdit/VimEdit.conf` on Linux.

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
