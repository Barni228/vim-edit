pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// :help, a box over the editor with what isn't obvious: :set and its forms,
// the commands, search, registers and macros, visual block and multiple
// cursors, hidden text and other keys. :help topic scrolls to a section.
// Keys scroll it as in a vim help buffer; Esc or q closes it. Its text can be
// selected with the mouse and copied.
Popup {
    id: help

    required property TextArea editor

    // Follows the editor's zoom (Cmd+ and Cmd-), like every text in the app.
    property real zoom: 1

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property bool dark: editor.palette.base.hslLightness < 0.5
    readonly property string monoFamily: editor.font.family
    readonly property color dimColor: Qt.tint(editor.palette.base, dark ? "#a0ffffff" : "#a0000000")
    // Modifier keys as the OS writes them.
    readonly property string cmdKey: isMac ? "⌘" : "Ctrl+"
    readonly property string altKey: isMac ? "⌥" : "Alt+"
    readonly property real lineStep: Math.round(20 * zoom)

    // Each section: a title, the :help topics that go to it, an optional
    // intro and note, and rows of [keys, what they do]. `code` in text is
    // shown in the editor's font.
    readonly property var sections: [
        {
            title: "Options (:set)",
            tags: ["set", "se", "options", "option", "fontsize", "fs", "number", "nu",
                "relativenumber", "rnu"],
            intro: "`:set` with no arguments lists the options that aren't at their default. "
                + "Several can be set at once: `:set nu rnu fs=18`.",
            rows: [
                ["fontsize, fs", "Font size in points, 6 to 72. Default 16."],
                ["number, nu", "Line numbers."],
                ["relativenumber, rnu", "Line numbers counted from the cursor's line. With `nu` too, "
                    + "the cursor's line shows its own number."]
            ]
        },
        {
            title: "Setting an on/off option",
            tags: [],
            rows: [
                [":set nu", "Turn it on."],
                [":set nonu", "Turn it off."],
                [":set nu!  :set invnu", "Toggle it."],
                [":set nu?", "Show it: `number` or `nonumber`."],
                [":set nu&", "Back to the default (off)."]
            ]
        },
        {
            title: "Setting a number option",
            tags: [],
            rows: [
                [":set fs=16  :set fs:16", "Set it."],
                [":set fs+=2  fs-=2  fs^=2", "Add, subtract, multiply."],
                [":set fs  :set fs?", "Show it: `fontsize=16`."],
                [":set fs&", "Back to the default (16)."]
            ],
            note: "Zoom and `:set` changes last until VimEdit quits, unless Settings (" + cmdKey
                + ",) > Zoom and :set is Change Settings."
        },
        {
            title: "Commands",
            tags: ["commands", "command", "ex", "w", "write", "quit", "wq", "x", "confirm", "conf", "noh",
                "nohlsearch", "help", "h", "history"],
            rows: [
                [":w", "Save."],
                [":wq  :x  ZZ", "Save and quit."],
                [":q", "Quit, unless there are unsaved changes."],
                [":q!  ZQ", "Quit without saving."],
                [":conf q  :confirm q", "Quit, asking whether to save unsaved changes: `y`, `n`, or `c` (or "
                    + "Esc) to cancel. Left and Right pick a choice for Enter."],
                [":42  :$", "Go to line 42, or the last line."],
                [":noh", "Clear the search highlights (so does Esc in normal mode)."],
                [":h  :help [topic]", "This help, e.g. `:h set`, `:h search`, `:h macros`."],
                ["↑ ↓", "In the command line: earlier and later commands (or searches)."],
                ["Ctrl-U  Ctrl-W", "In the command line: delete to the start, or the word before the cursor."],
                ["@:", "Run the last command again."]
            ]
        },
        {
            title: "Search",
            tags: ["search", "/", "?", "regex", "regexp", "pattern", "find", "replace", "n", "*"],
            rows: [
                ["/pattern  ?pattern", "Search forward or backward. Patterns are JavaScript regular "
                    + "expressions, not vim's, and match case: `\\bword\\b`, `(a|b)+`, `\\d{3}`. "
                    + "One that isn't valid (yet) is searched for as plain text."],
                ["n  N", "Next or previous match."],
                ["*  #", "Search for the word under the cursor."],
                [cmdKey + "F", "The find bar. Its matches are highlighted while it's open."],
                [isMac ? "⌘G  ⇧⌘G" : "F3  Shift+F3  Ctrl+G  Ctrl+Shift+G",
                    "Next or previous find bar match (opens the bar if it has nothing to find)."],
                [isMac ? "⌘⌥F" : "Ctrl+H", "Find and replace."],
                [isMac ? "⌃⌥C  ⌃⌥W  ⌃⌥R" : "Alt+C  Alt+W  Alt+R",
                    "In the find bar: match case, whole word, regular expression."]
            ]
        },
        {
            title: "Registers and macros",
            tags: ["registers", "register", "reg", "clipboard", "\"", "\"+", "+", "*", "macros", "macro",
                "q", "@", "@@", "record", "recording", "yank", "paste", "p", "y"],
            rows: [
                ["\"+  \"*", "The system clipboard, e.g. `\"+yy` or `\"+p`. Other registers (and "
                    + "plain `y`, `d`, `p`) don't touch the clipboard; " + (isMac ? "⌘C and ⌘V do."
                    : "Ctrl+C does (on a selection), and so does Ctrl+V in insert mode. Elsewhere "
                    + "Ctrl+V starts a visual block, and Shift+Insert pastes.")],
                ["\"a … \"z", "Named registers, e.g. `\"ayw`. `\"A` appends to `a`."],
                ["\"0  \"_", "The last yank; and the black hole, e.g. `\"_dd` deletes without "
                    + "changing any register."],
                ["qa … q", "Record the keys you type into register `a`. `qA` appends to it."],
                ["@a  3@a  @@", "Run the macro in `a`, three times, or the last one run again."]
            ]
        },
        {
            title: "Visual block and multiple cursors",
            tags: ["block", "visualblock", "ctrl-v", "<c-v>", "cursors", "cursor", "multiple", "multi",
                "alt-click", "click"],
            rows: [
                ["Ctrl-V", "Visual block. On Windows too, where Ctrl+V pastes only in insert mode."],
                ["I  A  c", "In a block: type on every line of it at once."],
                ["$", "In a block: reach the end of every line."],
                [altKey + "click", "Add a cursor, or remove one. A plain click goes back to one."],
                ["", "With several cursors, motions and edits happen at each, each with its own "
                    + "registers. Esc goes back to one cursor."]
            ]
        },
        {
            title: "Hidden text",
            tags: ["hidden", "hide", "reveal", "poop", "💩", "gh", "ctrl-j"],
            rows: [
                [cmdKey + "J", "Hide the selected text behind a 💩, or reveal the one under the cursor."],
                ["gh", "Show the text in the 💩 under the cursor (so does resting the mouse on it)."],
                ["", "Yanks, undo and copying keep the hidden text. Other apps get the text revealed."]
            ]
        },
        {
            title: "Warnings and errors",
            tags: ["warning", "warnings", "error", "errors", "diagnostics", "squiggle"],
            rows: [
                ["", "The words `warning` and `error` (in any case) get a wavy underline, orange or red, "
                    + "and a message after the end of their line, as in VS Code."],
                ["gh", "Show the message of the warning or error under the cursor (so does resting the "
                    + "mouse on it, or on the message)."]
            ]
        },
        {
            title: "Other keys",
            tags: ["keys", "other", "ctrl-a", "ctrl-x", "g?", "rot13", "ctrl-e", "ctrl-y", "scroll", "zoom",
                "settings", "undo", "gv", "zz"],
            rows: [
                ["Ctrl-A  Ctrl-X", "Add to or subtract from the number under or after the cursor."],
                ["g?  g~  gu  gU", "ROT13, toggle case, lowercase, uppercase (with a motion, e.g. `g?w`)."],
                ["Ctrl-E  Ctrl-Y", "Scroll a line down or up. The cursor stays, unless it would leave the screen."],
                ["zz  zt  zb", "Scroll the cursor's line to the middle, top or bottom."],
                ["gv", "Select the last visual selection again."],
                [isMac ? "⌘Z  ⇧⌘Z" : "Ctrl+Z  Ctrl+Shift+Z", "Undo and redo, the same as `u` and `Ctrl-R`."],
                [isMac ? "⌘+  ⌘-  ⌘0" : "Ctrl+=  Ctrl+-  Ctrl+0", "Zoom in, out, back to the default size."],
                [cmdKey + ",", "Settings: font size, line numbers, theme."]
            ]
        }
    ]

    // Opens the help at the section for `topic` (all of it if ""). False if
    // there's no help for it.
    function show(topic) {
        const t = topic.trim().toLowerCase().replace(/^:/, "").replace(/^'(.*)'$/, "$1");
        const i = t === "" ? 0 : sections.findIndex(s => s.tags.includes(t));
        if (i < 0)
            return false;
        open();
        shownSection = i;
        showSection();
        return true;
    }

    // The section :help went to. Its text is laid out over the first frames,
    // so it's scrolled to again as the layout changes, until the user scrolls.
    property int shownSection: -1

    function showSection() {
        const item = shownSection >= 0 ? sectionRepeater.itemAt(shownSection) : null;
        if (item)
            scroller.contentY = Math.min(item.y, scroller.maxY);
    }

    function scrollBy(dy) {
        shownSection = -1;
        scroller.contentY = Math.max(0, Math.min(scroller.maxY, scroller.contentY + dy));
    }

    // The text with a selection. Each text selects on its own, so selecting
    // in one clears the last one.
    property TextEdit selected: null

    function copySelection() {
        if (selected && selected.selectedText !== "")
            selected.copy();
    }

    // `code` in the editor's font, the rest as plain text.
    function styled(text) {
        const escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return escaped.replace(/`([^`]+)`/g, "<span style=\"font-family:'" + monoFamily + "'\">$1</span>");
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 48 * zoom : 700, 760 * zoom)
    height: Math.min(parent ? parent.height - 48 * zoom : 500, body.height + header.height + 2 * padding)
    padding: 16 * zoom
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: {
        if (selected)
            selected.deselect();
        editor.forceActiveFocus();
    }

    Overlay.modal: Rectangle {
        color: help.dark ? "#60000000" : "#30000000"
    }

    background: Rectangle {
        radius: 6 * help.zoom
        color: Qt.tint(help.editor.palette.base, help.dark ? "#12ffffff" : "#08000000")
        border.color: Qt.tint(help.editor.palette.base, help.dark ? "#40ffffff" : "#30000000")
        layer.enabled: help.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.8
            shadowVerticalOffset: 4
            shadowColor: help.dark ? "#a0000000" : "#50000000"
        }
    }

    // Selectable, but never focused, so keys stay with the help (which
    // forwards Copy, see copySelection).
    component HelpText: TextEdit {
        id: helpText

        readOnly: true
        selectByMouse: true
        activeFocusOnPress: false
        persistentSelection: true
        selectionColor: help.editor.palette.highlight
        selectedTextColor: help.editor.palette.highlightedText
        onSelectedTextChanged: {
            if (selectedText === "" || help.selected === helpText)
                return;
            if (help.selected)
                help.selected.deselect();
            help.selected = helpText;
        }

        HoverHandler {
            cursorShape: Qt.IBeamCursor
        }
    }

    contentItem: Item {
        Item {
            id: header

            width: parent.width
            height: title.height + 12 * help.zoom

            HelpText {
                id: title

                text: "VimEdit Help"
                font.pixelSize: Math.round(18 * help.zoom)
                font.bold: true
                color: help.editor.color
            }
            HelpText {
                anchors.right: parent.right
                anchors.baseline: title.baseline
                text: "Esc or q to close · j k to scroll"
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.dimColor
            }
        }

        Flickable {
            id: scroller

            readonly property real maxY: Math.max(0, contentHeight - height)

            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            contentWidth: width
            contentHeight: body.height
            clip: true
            focus: true
            // Not interactive, since a drag selects text; the wheel scrolls it.
            interactive: false

            ScrollBar.vertical: ScrollBar {
                id: scrollBar

                onPressedChanged: help.shownSection = -1
            }

            onMaxYChanged: help.showSection()

            WheelHandler {
                onWheel: event => help.scrollBy(-(event.pixelDelta.y || event.angleDelta.y / 120 * 3 * help.lineStep))
            }

            // As in a vim help buffer, and the usual keys.
            Keys.onPressed: event => {
                const ctrl = event.modifiers & (help.isMac ? Qt.MetaModifier : Qt.ControlModifier);
                const page = height - help.lineStep;
                if (event.matches(StandardKey.Copy))
                    help.copySelection();
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q && !event.modifiers)
                    help.close();
                else if (event.key === Qt.Key_J && !ctrl || event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_E)
                    help.scrollBy(help.lineStep);
                else if (event.key === Qt.Key_K && !ctrl || event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_Y)
                    help.scrollBy(-help.lineStep);
                else if (ctrl && event.key === Qt.Key_D)
                    help.scrollBy(height / 2);
                else if (ctrl && event.key === Qt.Key_U)
                    help.scrollBy(-height / 2);
                else if (ctrl && event.key === Qt.Key_F || event.key === Qt.Key_PageDown || event.key === Qt.Key_Space)
                    help.scrollBy(page);
                else if (ctrl && event.key === Qt.Key_B || event.key === Qt.Key_PageUp)
                    help.scrollBy(-page);
                else if (event.key === Qt.Key_G && event.modifiers & Qt.ShiftModifier || event.key === Qt.Key_End)
                    help.scrollBy(maxY);
                else if (event.key === Qt.Key_G || event.key === Qt.Key_Home)
                    help.scrollBy(-contentY);
                else
                    return;
                event.accepted = true;
            }

            Column {
                id: body

                width: scroller.width - 12 * help.zoom // clear of the scroll bar
                spacing: 18 * help.zoom
                onHeightChanged: help.showSection()

                Repeater {
                    id: sectionRepeater

                    model: help.sections

                    Column {
                        id: section

                        required property var modelData

                        width: body.width
                        spacing: 6 * help.zoom

                        HelpText {
                            text: section.modelData.title
                            font.pixelSize: Math.round(15 * help.zoom)
                            font.bold: true
                            color: help.editor.palette.accent
                        }
                        HelpText {
                            width: parent.width
                            visible: !!section.modelData.intro
                            text: help.styled(section.modelData.intro || "")
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: Math.round(13 * help.zoom)
                            color: help.editor.color
                        }
                        Repeater {
                            model: section.modelData.rows

                            Row {
                                id: row

                                required property var modelData

                                spacing: 12 * help.zoom

                                HelpText {
                                    id: keysText

                                    width: Math.round(body.width * 0.34)
                                    text: row.modelData[0]
                                    textFormat: TextEdit.PlainText
                                    wrapMode: TextEdit.Wrap
                                    font.family: help.monoFamily
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.editor.color
                                }
                                HelpText {
                                    width: body.width - keysText.width - row.spacing
                                    text: help.styled(row.modelData[1])
                                    textFormat: TextEdit.RichText
                                    wrapMode: TextEdit.Wrap
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.editor.color
                                }
                            }
                        }
                        HelpText {
                            width: parent.width
                            visible: !!section.modelData.note
                            text: help.styled(section.modelData.note || "")
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: Math.round(12 * help.zoom)
                            color: help.dimColor
                        }
                    }
                }
            }
        }

        // A press anywhere but on the selected text (or the scroll bar)
        // clears the selection, as in other apps. The handler only watches,
        // so the press goes on to what's under it. Not a MouseArea, which
        // would show its arrow cursor over the text's I-beam.
        Item {
            id: pressWatcher

            anchors.fill: parent
            anchors.margins: -help.padding
            z: 1

            PointHandler {
                acceptedButtons: Qt.LeftButton
                onActiveChanged: {
                    const s = help.selected, p = point.position;
                    if (active && s && !s.contains(pressWatcher.mapToItem(s, p))
                        && !scrollBar.contains(pressWatcher.mapToItem(scrollBar, p)))
                        s.deselect();
                }
            }
        }
    }
}
