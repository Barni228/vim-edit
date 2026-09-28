# Hidden text (Cmd+J)

Select text and press Cmd+J (Ctrl+J on Windows and Linux) to replace it with a 💩.
The 💩 behaves like any other character, but it remembers the text it replaced:
Cmd+J on it brings the text back, and copying it to the system clipboard gives
other apps that text. Hidden text lasts only while VimEdit runs. It is never
written to a file; a saved 💩 is a plain emoji.

Most of the code is in `qml/Vim.qml`, in the "Hidden text" section. The
clipboard and line-height helpers are in `cpp/platform.cpp`.

## Data model

The document holds only the emoji itself: `vim.poop`, U+1F4A9, which takes two
UTF-16 code units in `editor.text`. The hidden text is kept outside the
document, in `vim.hidden`:

```js
hidden = [
  { at: 4, item: { text: "hello", hidden: [] } },
  {
    at: 12,
    item: {
      text: "a💩b",
      hidden: [{ at: 1, item: { text: "x", hidden: [] } }],
    },
  },
];
```

- `at` is the position of the 💩 in the document, as a UTF-16 index. The list is
  sorted by `at`.
- `item` is the hidden text, together with the entries for any 💩s inside it. A
  selection that contains 💩s can be hidden, which nests them, and revealing
  removes one level at a time.
- A text fragment with its entries (a register, an undo step, the clipboard)
  uses the same shape, with `at` relative to the start of the fragment.
  `hiddenIn(list, start, end)` cuts such a fragment out of a list, and
  `shifted(list, by)` moves one.

`hidden` is never changed in place. Every update assigns a new array (the
entries are shared), so keeping a reference to it is enough to snapshot it.
Undo relies on this.

An entry is only ever looked up by exact position (`hiddenAt(p)`). A 💩 without
an entry is an ordinary emoji. That covers a 💩 typed by the user, one pasted
from another app, and one in a file that was opened.

## Keeping positions in sync

Every edit to the text must shift the entries after it. An edit can come from
two places.

**Vim's own edits** all go through `replaceRange(start, end, text, entries)`,
which knows exactly what changed. After editing, it calls
`shiftHidden(start, end, text.length, entries)`, which works like this:

- An entry that ends at or before `start` is kept.
- An entry that starts inside `[start, end)` is dropped. This includes a 💩
  whose two code units the edit splits.
- `entries`, the entries for the inserted text, are added at `start`.
- An entry at or after `end` moves by the change in length.

A caller that inserts text with 💩s must pass that text's entries. The callers
that do are: paste (from a register, repeated `count` times with `repeated()`),
undo and redo, Cmd+J itself, and the restore when Backspace is pressed in
replace mode. Callers that rewrite text in place (`~`, `gu`/`gU`/`g~`, `>`/`<`)
pass `carriedHidden(start, end, newText)`. It matches the k-th 💩 of the old
text to the k-th 💩 of the new one, because those rewrites never add or remove
emoji.

**The editor's own edits** are the ones Qt makes in insert mode: typed
characters, IME input, Delete, and `editor.insert` calls from `main.qml`. These
arrive only as `textChanged`. `trackEdit()` compares the new text against
`trackedText` (the text that `hidden` last matched): it takes the common prefix
and suffix, and applies the span between them as one edit. `replaceRange` sets
`editing` so that its own changes aren't counted twice. Both functions skip all
of this while `hidden` is empty, so documents without hidden text pay nothing.

The diff can't tell which of two identical neighbours changed. Typing a 💩 right
next to a hidden 💩 may leave the entry on the wrong one of the two. The result
looks the same, and only which 💩 reveals changes.

## Undo

Vim's undo stores each change as a span, found by diffing the text before and
after it (`beginChange`/`commitChange`). With hidden text, two texts can be
equal while their entries differ. For example, deleting the first of two
adjacent 💩s gives the same text as deleting the second. So `diff()` also
compares the entries:

- An entry in the unchanged prefix or suffix must exist on both sides, at the
  same place and with the same `item` (compared by identity).
- The first entry that doesn't match pulls the edges of the changed span in
  around it.

Each undo record keeps `removedHidden` and `insertedHidden`, and undo and redo
pass them back to `replaceRange`. A 💩 that is deleted and then undone gets its
text back.

## Registers and the clipboard

Register entries are `{ text, linewise, hidden }`. The `hidden` list comes from
`yank` and `deleteRange` (taken before the text is removed), from `c`, and from
the text that visual `p` replaces. Appending to a register (`"A`) shifts the new
entries by the length of the old text.

The `"+` and `"*` registers (and Cmd+C/X/V, which use `"+` in every mode,
including insert mode) write two formats with `setClipboardText(text, data)`:

- **Plain text**: `revealAll(text, entries)`, with every hidden text revealed
  recursively. Other apps get this, so copying a 💩 elsewhere gives the text it
  hides.
- **`application/x-vimedit-data`**: JSON `{ text, hidden }`, written only when
  there are entries. When pasting, `getRegister("+")` prefers it, so the 💩
  comes back with its text, even in another VimEdit window. Any app can write
  to the clipboard, so `validHidden` checks the structure first: positions are
  sorted, each one points at a 💩, and nested items are valid. If the check
  fails, VimEdit pastes the plain text.

Other registers never touch the system clipboard (see the Vim section in
`CLAUDE.md`).

## Cmd+J

`toggleHidden()` decides between hiding and revealing:

| State                                         | Action                                                                  |
| --------------------------------------------- | ----------------------------------------------------------------------- |
| Visual or visual-line selection               | Hide the selection (visual-line: whole lines, without the last newline) |
| Mouse selection in insert mode                | Hide the selection                                                      |
| Selection that is exactly one hidden 💩       | Reveal it                                                               |
| No selection, cursor on a hidden 💩           | Reveal it                                                               |
| Insert mode, hidden 💩 just before the cursor | Reveal it                                                               |
| Anything else                                 | Nothing                                                                 |

Revealing leaves the revealed text selected: a visual selection in normal mode,
or the editor's own selection in insert mode. Pressing Cmd+J again hides it
again. Hiding leaves the cursor on the 💩. Either way the change is a single
undo step (`externalEdit`), and in insert mode it first ends the current insert
(`breakInsert`), as moving the cursor does.

The shortcut is a menu item (Edit → Hide or Reveal Text) in both menu bars in
`main.qml`.

## Making the 💩 act like one character

The 💩 takes two UTF-16 code units. Vim's code used to step through the text
with `±1`, which could leave the cursor between the two halves. Cursor steps now
go through two helpers:

- `charEnd(t, p)` returns the end of the character at `p`.
- `charStart(t, p)` returns the start of the character that `p` is in.

Here a character is one code point plus the code points that attach to it:
combining marks, variation selectors, emoji skin tones and tags, and anything
after a zero-width joiner. This matches what Qt treats as one character, so
regular emoji (👍🏽, 👨‍👩‍👧) also move as one character now. The helpers are used
in:

- Motions: `h`, `l`, `e`, `ge`, `t`, `T`, `|`.
- Edits: `a`, `x`, `s`, `r`, `~`, and replace mode.
- Selections: visual selection ends, and `clampNormal`.
- The block cursor in `main.qml`, which draws the whole character.

Columns (for `j`/`k`, `|` and the status line) count characters rather than code
units, using `column()` and `atColumn()`.

Qt's own Backspace deletes a single code point, which would leave half an emoji
behind. So vim handles Backspace itself in insert mode, when there's no
selection and no modifier (`insertKey` → `typeKey`). Arrow keys, Delete and
mouse clicks are left to Qt, which already moves over whole characters.

## Line height

Menlo has no emoji, so Qt draws the 💩 from Apple Color Emoji, which is taller,
and the 💩's line grows (27 px instead of 19 px at 16 pt). This affects any
emoji, not just hidden text, but the 💩 made it obvious.

`fixLineHeight()` in `main.qml` calls `setLineHeight` in C++, which gives every
block of the `QTextDocument` a `FixedHeight` block format of
`root.lineHeight`: Menlo's line spacing × 1.25, rounded up. At × 1.0, emoji
touch the descenders of the line above; the extra space keeps them clear.
Some details:

- New lines inherit the format from the block they split off. Setting
  `editor.text` resets it, so it is applied again after a file loads, and when
  the font size changes.
- A format change emits `textChanged` like an edit would, so `fixLineHeight`
  restores `modified` afterwards.
- With a fixed height, Qt puts every line's baseline at 4/5 of the line height,
  so the spacing between lines is even.

Qt also sizes its own highlights to each line's tallest glyph. The selection,
and the rectangle `positionToRectangle` returns, are taller and shifted on a
line with an emoji. So VimEdit draws all of these itself, at one height, the
"text band" that Menlo's characters occupy:

- `editor.cellAt(pos)` snaps Qt's rectangle to the fixed line grid.
- `editor.bandAt(pos)` is the part of that cell from the font's ascent above
  the baseline to its descent below it. On a line without emoji, this matches
  what Qt's own selection would cover.
- The selection is drawn by the `selection` item, one rectangle per visible
  line (`editor.selectionSpans()`). The item has a negative `z`, which puts it
  under the editor's text, as Qt's selection would be. Qt's selection is made
  invisible (`selectionColor: "transparent"`, `selectedTextColor: color`). A
  selected line break shows as a space's width, as in Qt.
- The block cursor, the insert-mode bar (inside the editor's cursor delegate)
  and the search highlights use `bandAt`. Their `Text` items are placed by
  baseline (`metrics.ascent - baselineOffset`), not by the top of the band.

An emoji is taller than the band, so it sticks out of a selection or cursor a
little. That is on purpose: every line's highlight then has the same height.

## Testing

`Vim.qml` can be tested with `qmltestrunner`, with a `TextArea` and a mock
`clipboard` object that has `clipboardText()`, `clipboardData()` and
`setClipboardText(text, data)` (see "To test `Vim.qml`" in `CLAUDE.md`). The
cases worth covering:

- Hiding and revealing, and hiding again right after a reveal.
- Motions over a 💩, counts, `r`, `R` followed by Backspace, `cw`, `.`.
- Typing before a 💩 in insert mode.
- Two different 💩s side by side, deleted and undone.
- `>>`, `gUU`, and appending to a register.
- `"+y`/`"+p` and Cmd+C/Cmd+V.
- Clipboard data that fails validation.
- A mouse drag over the 💩.
- A `Label` bound to `vim.positionLabel()`, as in the app. Without it, a bug
  that hangs the app while typing can go unnoticed.

The line-height code needs the real app, because it calls into C++.
