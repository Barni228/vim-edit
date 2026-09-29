pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Shapes
import Qt.labs.platform as Platform

import VimEdit

ApplicationWindow {
    id: root

    readonly property bool isMac: Qt.platform.os === "osx"
    property string filePath: ""
    readonly property string fileName: filePath ? filePath.split(/[\\/]/).pop() : "Untitled"
    property bool modified: false
    // Quit once the Save dialog has saved the file (:wq, or Save in the
    // :confirm q dialog, for a file that has no path yet).
    property bool quitAfterSave: false
    readonly property int defaultFontSize: 16
    readonly property int minFontSize: 6
    readonly property int maxFontSize: 72
    readonly property string defaultFontFamily: isMac ? "Menlo" : "Consolas"
    // The fonts the editor offers: the installed monospaced ones. Finding
    // them loads every font, which takes a moment, so it waits until
    // they're needed (loadFontFamilies).
    property var fontFamilies: []
    // The settings in use: the saved ones, unless changed for this session
    // (see settings.keepChanges). Vim keeps the font size and family for
    // :set fs and :set gfn.
    property alias fontSize: vim.fontSize
    property alias fontFamily: vim.fontFamily
    // "system", "light" or "dark".
    property string theme: settings.theme
    // Every line is this tall, even one with an emoji (see fixLineFormat).
    // The extra space keeps an emoji clear of the lines around it.
    readonly property int lineHeight: Math.ceil(metrics.lineSpacing * 1.25)
    // Where the baseline is in a line: the font's characters sit in the
    // middle of it (see fixLineFormat).
    readonly property real textBaseline: (lineHeight + metrics.ascent - metrics.descent) / 2

    width: 900
    height: 650
    visible: true
    title: fileName + (modified ? " •" : "") + " — VimEdit"

    function openFile() {
        openDialog.open();
    }

    // Saves the file, asking for a path if it has none, then quits if
    // `quit` is set and the save worked.
    function save(quit) {
        if (!filePath) {
            saveAs();
            quitAfterSave = !!quit;
            return;
        }
        if (doc.saveFile(filePath, editor.text)) {
            modified = false;
            if (quit)
                Qt.quit();
        }
    }

    function saveAs() {
        quitAfterSave = false;
        saveDialog.open();
    }

    function loadFontFamilies() {
        if (fontFamilies.length)
            return;
        const families = doc.monospaceFamilies();
        fontFamilies = families.includes(defaultFontFamily) ? families : families.concat(defaultFontFamily).sort((a, b) => a.localeCompare(b));
    }

    function zoom(step) {
        fontSize = Math.max(minFontSize, Math.min(maxFontSize, fontSize + step));
    }

    // An emoji comes from a taller font than the editor's, which makes its line
    // taller. Give every line the same height instead. Qt puts a fixed-height
    // line's baseline at 4/5 of it, so to center the text, the line is made
    // shorter and a bottom margin makes up the rest. The block format that
    // does this counts as an edit, but isn't one.
    function fixLineFormat() {
        const wasModified = modified;
        // Not textBaseline, which may not have caught up with the font yet.
        const baseline = (lineHeight + metrics.ascent - metrics.descent) / 2;
        const height = Math.min(lineHeight, baseline * 5 / 4);
        doc.setLineFormat(editor.textDocument, height, lineHeight - height);
        modified = wasModified;
    }

    onLineHeightChanged: fixLineFormat()
    onTextBaselineChanged: fixLineFormat()

    function toggleHidden() {
        vim.toggleHidden();
        editor.forceActiveFocus();
    }

    // Qt 6.8 and later can override the system's light or dark mode, which
    // also changes the palette, the title bar and the menus.
    function applyTheme() {
        Application.styleHints.colorScheme = theme === "light" ? Qt.ColorScheme.Light : theme === "dark" ? Qt.ColorScheme.Dark : Qt.ColorScheme.Unknown;
    }

    onThemeChanged: applyTheme()

    // The saved settings. The Settings window changes them along with the
    // ones in use; the zoom and :set nu / rnu change them only with
    // keepChanges, and otherwise just for this session.
    Settings {
        id: settings

        property int fontSize: root.defaultFontSize
        property string fontFamily: root.defaultFontFamily
        property string theme: "system"
        property bool number: false
        property bool relativeNumber: false
        property bool keepChanges: false

        // Turning it on saves what's in use, as if it had been on.
        onKeepChangesChanged: {
            if (keepChanges)
                ["fontSize", "fontFamily", "number", "relativeNumber"].forEach(name => root.keepChange(name));
        }
    }

    // Changes a setting now and saves it (fontSize, fontFamily, theme,
    // number or relativeNumber).
    function changeSetting(name, value) {
        (name in settingOwners ? settingOwners[name] : root)[name] = value;
        settings[name] = value;
    }

    // Where the settings in use live, other than in root.
    readonly property var settingOwners: ({
            number: vim,
            relativeNumber: vim
        })

    // Saves the setting in use after a zoom or :set, if keepChanges says to.
    function keepChange(name) {
        if (settings.keepChanges)
            settings[name] = (name in settingOwners ? settingOwners[name] : root)[name];
    }

    onFontSizeChanged: keepChange("fontSize")
    onFontFamilyChanged: keepChange("fontFamily")

    Connections {
        target: vim

        function onNumberChanged() {
            root.keepChange("number");
        }
        function onRelativeNumberChanged() {
            root.keepChange("relativeNumber");
        }
    }

    HelpPanel {
        id: help

        editor: editor
        zoom: root.fontSize / root.defaultFontSize
    }

    // :confirm q with unsaved changes.
    ConfirmDialog {
        id: confirmDialog

        editor: editor
        zoom: root.fontSize / root.defaultFontSize
        onYes: root.save(true)
        onNo: Qt.quit()
    }

    SettingsWindow {
        id: settingsWindow

        app: root
        vim: vim
        editor: editor
        settings: settings
    }

    Document {
        id: doc

        onLoaded: (path, text) => {
            editor.text = text;
            root.fixLineFormat(); // setting the text reset it
            vim.reset();
            root.filePath = path;
            root.modified = false;
            editor.forceActiveFocus();
        }
        onFailed: message => {
            errorDialog.text = message;
            errorDialog.open();
        }
    }

    Vim {
        id: vim

        editor: editor
        flickable: scrollView.contentItem as Flickable
        clipboard: doc
        lineHeight: root.lineHeight
        number: settings.number
        relativeNumber: settings.relativeNumber
        fontSize: settings.fontSize
        defaultFontSize: root.defaultFontSize
        minFontSize: root.minFontSize
        maxFontSize: root.maxFontSize
        fontFamily: settings.fontFamily
        defaultFontFamily: root.defaultFontFamily
        fontFamilies: root.fontFamilies

        onFontFamiliesNeeded: root.loadFontFamilies()
        onWriteRequested: quit => root.save(quit)
        onQuitRequested: (force, confirm) => {
            if (force || !root.modified)
                Qt.quit();
            else if (confirm)
                confirmDialog.ask("Save changes to “" + root.fileName + "”?");
            else
                vim.showError("E37: No write since last change (add ! to override)");
        }
        onHoverRequested: at => hover.show(at, false)
        onHelpRequested: topic => {
            if (!help.show(topic))
                vim.showError("E149: Sorry, no help for " + topic);
        }
        onCursorChanged: hover.hide()
    }

    FontMetrics {
        id: metrics

        font: editor.font
    }

    ScrollView {
        id: scrollView

        anchors.fill: parent

        TextArea {
            id: editor

            // Bumped on every edit, for things that must refresh after one.
            property int revision: 0
            // Whether the insert-mode bars are in the visible half of a blink.
            property bool blinkOn: true

            // The rectangle of the character at pos, as tall as the line. The
            // cursors and highlights use it rather than positionToRectangle,
            // which gives a line with an emoji its natural height, while every
            // line is root.lineHeight tall (see fixLineFormat).
            function cellAt(pos) {
                const r = positionToRectangle(pos);
                const h = root.lineHeight;
                const line = Math.round((r.y + r.height / 2 - topPadding - h / 2) / h);
                return Qt.rect(r.x, topPadding + line * h, r.width, h);
            }

            // The selection in the visible lines, as one { start, end, eol }
            // span per line, where eol means it includes the line break. A
            // visual block isn't the editor's selection, so vim gives it.
            function selectionSpans() {
                const block = vim.mode === "visualBlock";
                const s = selectionStart, e = selectionEnd;
                if (s === e && !block)
                    return [];
                const t = text, f = scrollView.contentItem as Flickable;
                const top = Math.floor((f.contentY - topPadding) / root.lineHeight);
                const bottom = Math.ceil((f.contentY + f.height - topPadding) / root.lineHeight);
                const last = vim.lineEnd(t, vim.lineToPos(t, Math.max(bottom, 0) + 1));
                if (block) {
                    const first = vim.lineToPos(t, Math.max(top, 0) + 1);
                    return vim.blockSpans().filter(r => r.start >= first && r.start <= last);
                }
                const to = Math.min(e, last);
                const spans = [];
                for (let p = Math.max(s, vim.lineToPos(t, Math.max(top, 0) + 1)); p <= to; ) {
                    const le = vim.lineEnd(t, p);
                    if (p === e)
                        break;
                    spans.push({
                        start: p,
                        end: Math.min(le, e),
                        eol: le < e
                    });
                    p = le + 1;
                }
                return spans;
            }

            font.family: root.fontFamily
            font.pointSize: root.fontSize
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            // The selection is drawn below (see `selection`), not by Qt.
            selectionColor: "transparent"
            selectedTextColor: color
            readOnly: true // vim starts in normal mode
            focus: true
            onTextChanged: {
                root.modified = true;
                revision++;
            }
            onCursorPositionChanged: {
                blinkOn = true;
                vim.syncFromEditor();
            }
            onSelectedTextChanged: vim.syncFromEditor()
            onRevisionChanged: hover.hide()
            onActiveFocusChanged: if (!activeFocus)
                hover.hide()
            // Make room for the line numbers beside the style's padding.
            Component.onCompleted: {
                const base = leftPadding;
                leftPadding = Qt.binding(() => base + gutter.columnWidth);
            }
            Keys.onPressed: event => {
                if (event.matches(StandardKey.Copy) && hover.copySelection()) {
                    event.accepted = true;
                    return;
                }
                // Not on a lone modifier, which may start Cmd+C.
                if (![Qt.Key_Shift, Qt.Key_Control, Qt.Key_Meta, Qt.Key_Alt, Qt.Key_AltGr].includes(event.key))
                    hover.hide(); // gh shows it again
                event.accepted = vim.handleKey(event);
            }

            // The pointer resting on a hidden-text 💩 shows its text, and on a
            // warning or error (or its message after the line) the message.
            HoverHandler {
                onPointChanged: hover.pointerAt(hovered ? point.position : null)
                onHoveredChanged: hover.pointerAt(hovered ? point.position : null)
            }

            // Insert mode: a blinking bar. The editor puts the delegate at its
            // cursor rectangle; the bar itself fills the line.
            cursorDelegate: Item {
                id: bar

                width: 2
                visible: vim.mode === "insert" && editor.activeFocus && editor.blinkOn

                Rectangle {
                    y: editor.cellAt(editor.cursorPosition).y - bar.y
                    width: parent.width
                    height: root.lineHeight
                    color: editor.color
                }
            }

            // The bars blink together: the one above and the extra cursors'.
            Timer {
                interval: 530
                repeat: true
                running: vim.mode === "insert" && editor.activeFocus
                onRunningChanged: editor.blinkOn = true
                onTriggered: editor.blinkOn = !editor.blinkOn
            }

            // Alt+click adds a cursor (or removes one). A plain click goes
            // back to one cursor and then does what it always does.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: mouse => {
                    if (mouse.modifiers & Qt.AltModifier) {
                        editor.forceActiveFocus();
                        vim.toggleCursor(editor.positionAt(mouse.x, mouse.y));
                    } else {
                        vim.clearCursors();
                        mouse.accepted = false;
                    }
                }
            }

            // The extra cursors (Alt+click, or a block insert's lines), shaped
            // like the main one. Like the block cursor below,
            // they refresh after an edit finishes rather than halfway through.
            Item {
                id: extraCursors

                property var spots: []
                readonly property var inputs: [vim.cursors, editor.revision, editor.font, editor.contentWidth, editor.contentHeight, editor.leftPadding]

                function refresh() {
                    const t = editor.text;
                    spots = vim.cursors.map(c => {
                        const pos = Math.min(c.pos, editor.length);
                        const ch = t.slice(pos, vim.charEnd(t, pos));
                        const shown = ch === "\t" || ch === "\n" || ch === "\u2029" ? "" : ch;
                        return {
                            cell: editor.cellAt(pos),
                            character: shown,
                            width: metrics.advanceWidth(shown || " ")
                        };
                    });
                }

                onInputsChanged: Qt.callLater(refresh)

                Repeater {
                    model: extraCursors.spots

                    Rectangle {
                        required property var modelData
                        // The main cursor's shape: "bar", "block" or "underline".
                        readonly property string shape: vim.cursorShape
                        readonly property rect cell: modelData.cell

                        x: cell.x
                        y: shape === "underline" ? cell.y + cell.height - height : cell.y
                        width: shape === "bar" ? 2 : modelData.width
                        height: shape === "underline" ? Math.max(2, Math.round(cell.height / 8)) : cell.height
                        color: editor.color
                        visible: shape !== "bar" || editor.activeFocus && editor.blinkOn
                        opacity: editor.activeFocus ? 1 : 0.4

                        Text {
                            y: root.textBaseline - baselineOffset
                            visible: parent.shape === "block"
                            text: parent.modelData.character
                            font: editor.font
                            color: editor.palette.base
                            textFormat: Text.PlainText
                        }
                    }
                }
            }

            // The lines with a cursor (the main one and the extras), a shade
            // off the background as in other editors, under the selection.
            // Not while there's a selection.
            Item {
                id: lineHighlights

                z: -0.6
                visible: !vim.isVisual

                Band {
                    row: block.cell
                }

                Repeater {
                    model: extraCursors.spots

                    Band {
                        required property var modelData

                        row: modelData.cell
                    }
                }
            }

            // The selection, drawn under the text (a negative z puts a child
            // below its parent's content) with the same height on every line.
            Item {
                id: selection

                property var spans: []
                readonly property var inputs: [editor.selectionStart, editor.selectionEnd, editor.revision, vim.mode, vim.anchor, vim.cursor, vim.wantCol, scrollView.contentItem.contentY, scrollView.contentItem.height, editor.contentWidth, editor.contentHeight, editor.leftPadding]

                function refresh() {
                    spans = []; // recompute every rectangle, as for `highlights`
                    spans = editor.selectionSpans();
                }

                z: -0.5
                onInputsChanged: Qt.callLater(refresh)

                TextMetrics {
                    id: spaceMetrics

                    font: editor.font
                    text: " "
                }

                Repeater {
                    model: selection.spans

                    Rectangle {
                        required property var modelData
                        readonly property rect startRect: editor.cellAt(modelData.start)
                        readonly property rect endRect: editor.cellAt(modelData.end)

                        x: startRect.x
                        y: startRect.y
                        // A selected line break shows as a space, as in Qt.
                        width: endRect.x - startRect.x + (modelData.eol ? spaceMetrics.advanceWidth : 0)
                        height: startRect.height
                        color: editor.palette.highlight
                    }
                }
            }

            // Search matches: the search being typed, else the find bar's
            // while it's open, else the last search until Esc. Like the
            // block cursor below, they refresh after an edit finishes rather
            // than halfway through one.
            Item {
                id: highlights

                property var spans: []
                readonly property var inputs: [editor.revision, vim.commandLine, vim.highlightPattern, vim.searchTarget, findBar.active, findBar.matches, findBar.current, scrollView.contentItem.contentY, scrollView.contentItem.height, editor.contentWidth, editor.contentHeight // these follow font size changes
                    , editor.leftPadding] // and this the line numbers

                function refresh() {
                    // The Repeater keeps its delegates when the new spans equal
                    // the old ones, but after a relayout their rectangles must
                    // be recomputed, so always start from an empty model.
                    spans = [];
                    spans = vim.typedSearch() === null && findBar.active ? findBar.highlightSpans() : vim.searchHighlights();
                }

                onInputsChanged: Qt.callLater(refresh)

                Repeater {
                    model: highlights.spans

                    Rectangle {
                        required property var modelData
                        readonly property rect startRect: editor.cellAt(modelData.start)
                        readonly property rect endRect: editor.cellAt(modelData.end)

                        x: startRect.x
                        y: startRect.y
                        width: endRect.x - startRect.x
                        height: startRect.height
                        color: modelData.current ? "#ff9f1a" : "#f5d547"

                        // Redraw the matched text on top, dark on the highlight.
                        Text {
                            y: root.textBaseline - baselineOffset
                            text: editor.getText(modelData.start, modelData.end)
                            font: editor.font
                            color: "black"
                            textFormat: Text.PlainText
                        }
                    }
                }
            }

            // Warnings and errors, as in VS Code: the whole words "warning"
            // and "error" (in any case) get a wavy underline, orange or red,
            // and their line shows a message after its end (an error's, if
            // there's one). The pointer resting on either (or gh) shows the
            // message in `hover`. Drawn for the visible lines, like the
            // highlights.
            Item {
                id: diagnostics

                readonly property int longest: 7 // "warning"
                readonly property real zoom: root.fontSize / root.defaultFontSize
                readonly property bool dark: editor.palette.base.hslLightness < 0.5
                property var spans: []
                // The one shown after each line's end, with that lineEnd.
                property var messages: []
                readonly property var inputs: [editor.revision, scrollView.contentItem.contentY, scrollView.contentItem.height, editor.contentWidth, editor.contentHeight, editor.leftPadding]

                // The warnings and errors within t from `from` to `to`, as
                // { start, end, severity }.
                function find(t, from, to) {
                    const re = /warning|error/gi, part = t.slice(from, to), list = [];
                    let m;
                    while ((m = re.exec(part))) {
                        const s = from + m.index, e = s + m[0].length;
                        if (vim.charClass(t[s - 1]) !== 2 && vim.charClass(t[e]) !== 2)
                            list.push({
                                start: s,
                                end: e,
                                severity: m[0].toLowerCase()
                            });
                    }
                    return list;
                }

                // The warning or error with the character at pos, or null.
                function at(pos) {
                    return find(editor.text, Math.max(0, pos - longest + 1), pos + longest).find(d => d.start <= pos && pos < d.end) || null;
                }

                function message(d) {
                    const word = "“" + editor.text.slice(d.start, d.end) + "”";
                    return d.severity === "error" ? word + " is an error." : word + " is a warning.";
                }

                function color(severity) {
                    if (severity === "error")
                        return dark ? "#f14c4c" : "#e51400";
                    return dark ? "#ff9d3b" : "#e07000";
                }

                // A zigzag `width` long, `step` high, with a peak every
                // other step. The last step ends partway at `width`.
                function wave(width, step) {
                    let path = "M0 " + step;
                    for (let x = step, up = true; x - step < width; x += step, up = !up) {
                        const end = Math.min(x, width), part = (end - x + step) / step;
                        path += " L" + end + " " + (up ? step * (1 - part) : step * part);
                    }
                    return path;
                }

                function refresh() {
                    const t = editor.text, f = scrollView.contentItem as Flickable, h = root.lineHeight;
                    const top = Math.floor((f.contentY - editor.topPadding) / h);
                    const bottom = Math.ceil((f.contentY + f.height - editor.topPadding) / h);
                    const last = vim.lineEnd(t, vim.lineToPos(t, Math.max(bottom, 0) + 1));
                    const found = find(t, vim.lineToPos(t, Math.max(top, 0) + 1), last);
                    const shown = [];
                    for (const d of found) {
                        const lineEnd = vim.lineEnd(t, d.start), prev = shown[shown.length - 1];
                        if (!prev || prev.lineEnd !== lineEnd)
                            shown.push(Object.assign({
                                lineEnd
                            }, d));
                        else if (prev.severity !== "error" && d.severity === "error")
                            shown[shown.length - 1] = Object.assign({
                                lineEnd
                            }, d);
                    }
                    // Recompute every rectangle, as for `highlights`.
                    spans = [];
                    messages = [];
                    spans = found;
                    messages = shown;
                }

                // The message shown after a line's end at point p, as
                // { start, rect } (its diagnostic's start), or null.
                function messageUnder(p) {
                    for (let i = 0; i < messageRepeater.count; i++) {
                        const m = messageRepeater.itemAt(i), cell = editor.cellAt(messages[i].lineEnd);
                        if (m && p.x >= m.x && p.x < m.x + m.width && p.y >= cell.y && p.y < cell.y + cell.height)
                            return {
                                start: messages[i].start,
                                rect: Qt.rect(m.x, cell.y, m.width, cell.height)
                            };
                    }
                    return null;
                }

                onInputsChanged: Qt.callLater(refresh)

                Repeater {
                    id: messageRepeater

                    model: diagnostics.messages

                    // Four spaces after the line's end.
                    Text {
                        required property var modelData
                        readonly property rect cell: editor.cellAt(modelData.lineEnd)

                        x: cell.x + 4 * spaceMetrics.advanceWidth
                        y: cell.y + root.textBaseline - baselineOffset
                        text: diagnostics.message(modelData)
                        font: editor.font
                        color: diagnostics.color(modelData.severity)
                        textFormat: Text.PlainText
                    }
                }

                Repeater {
                    model: diagnostics.spans

                    // Centered on the bottom of the font's descent.
                    Shape {
                        id: squiggle

                        required property var modelData
                        readonly property rect startRect: editor.cellAt(modelData.start)

                        x: startRect.x
                        y: startRect.y + root.textBaseline + metrics.descent - height / 2
                        width: editor.cellAt(modelData.end).x - startRect.x
                        height: 3 * diagnostics.zoom
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: diagnostics.color(squiggle.modelData.severity)
                            strokeWidth: diagnostics.zoom
                            fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin

                            PathSvg {
                                path: diagnostics.wave(squiggle.width, squiggle.height)
                            }
                        }
                    }
                }
            }

            // Other modes: a block over the character, or an underline in
            // replace mode (R, and r while it waits for the character).
            Rectangle {
                id: block

                property rect cell
                property string character
                readonly property bool underline: vim.cursorShape === "underline"

                // Runs after the current edit finishes: while editor.remove()
                // runs, the document is already shorter but editor.length isn't
                // updated yet, and asking for a position then warns.
                function refresh() {
                    const pos = Math.min(vim.cursor, editor.length);
                    cell = editor.cellAt(pos);
                    const t = editor.text;
                    const c = t.slice(pos, vim.charEnd(t, pos)); // e.g. a whole emoji
                    character = c === "\t" || c === "\n" || c === "\u2029" ? "" : c;
                }

                Connections {
                    target: editor

                    function onRevisionChanged() {
                        Qt.callLater(block.refresh);
                    }
                    // Also follow layout changes: padding set by the style or
                    // the line numbers, and font size changes (which move the
                    // cursor rectangle only once it's next updated, so also
                    // watch the content size).
                    function onCursorRectangleChanged() {
                        Qt.callLater(block.refresh);
                    }
                    function onFontChanged() {
                        Qt.callLater(block.refresh);
                    }
                    function onLeftPaddingChanged() {
                        Qt.callLater(block.refresh);
                    }
                    function onContentWidthChanged() {
                        Qt.callLater(block.refresh);
                    }
                    function onContentHeightChanged() {
                        Qt.callLater(block.refresh);
                    }
                }
                Connections {
                    target: vim

                    function onCursorChanged() {
                        Qt.callLater(block.refresh);
                    }
                }
                Component.onCompleted: refresh()

                TextMetrics {
                    id: charMetrics

                    font: editor.font
                    text: block.character || " "
                }

                visible: vim.mode !== "insert"
                x: cell.x
                y: underline ? cell.y + cell.height - height : cell.y
                width: charMetrics.advanceWidth
                height: underline ? Math.max(2, Math.round(cell.height / 8)) : cell.height
                color: editor.color
                opacity: editor.activeFocus ? 1 : 0.4

                Text {
                    y: root.textBaseline - baselineOffset
                    visible: !parent.underline
                    text: parent.character
                    font: editor.font
                    color: editor.palette.base
                    textFormat: Text.PlainText
                }
            }

            // Line numbers (:set number / relativenumber) for the visible
            // lines, in the left padding, two spaces before the text. It
            // stays put when the text scrolls sideways, and covers the text
            // that scrolls under it. As in vim, with both options the
            // cursor's line shows its own number, on the left.
            Rectangle {
                id: gutter

                readonly property bool shown: vim.number || vim.relativeNumber
                property int digits: 3
                // Room for the numbers and two spaces after them.
                readonly property real columnWidth: shown ? (digits + 2) * digitMetrics.advanceWidth : 0
                property var rows: []
                readonly property var inputs: [shown, vim.number, vim.relativeNumber, vim.cursor, editor.revision, scrollView.contentItem.contentY, scrollView.contentItem.height, editor.contentHeight, root.lineHeight]

                function refresh() {
                    if (!shown) {
                        rows = [];
                        return;
                    }
                    const t = editor.text, f = scrollView.contentItem, h = root.lineHeight;
                    const count = vim.countLines(t);
                    digits = Math.max(3, String(count).length);
                    const current = vim.lineOf(t, vim.cursor) - 1;
                    const top = Math.max(0, Math.floor((f.contentY - editor.topPadding) / h));
                    const bottom = Math.min(count - 1, Math.ceil((f.contentY + f.height - editor.topPadding) / h));
                    const list = [];
                    for (let i = top; i <= bottom; i++) {
                        const own = i === current && vim.number;
                        list.push({
                            line: i,
                            current: i === current,
                            left: own && vim.relativeNumber,
                            label: String(vim.relativeNumber && !own ? Math.abs(i - current) : i + 1)
                        });
                    }
                    rows = list;
                }

                onInputsChanged: Qt.callLater(refresh)

                visible: shown
                x: scrollView.contentItem.contentX
                width: editor.leftPadding
                height: editor.height
                color: (editor.background as Rectangle).color

                TextMetrics {
                    id: digitMetrics

                    font: editor.font
                    text: "0"
                }

                Repeater {
                    model: gutter.rows

                    Text {
                        required property var modelData

                        x: editor.leftPadding - gutter.columnWidth
                        y: editor.topPadding + modelData.line * root.lineHeight + root.textBaseline - baselineOffset
                        width: gutter.digits * digitMetrics.advanceWidth
                        horizontalAlignment: modelData.left ? Text.AlignLeft : Text.AlignRight
                        text: modelData.label
                        font: editor.font
                        color: modelData.current ? editor.color : Qt.tint(editor.palette.base, editor.palette.base.hslLightness < 0.5 ? "#80ffffff" : "#80000000")
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }

    component Band: Rectangle {
        required property rect row

        x: scrollView.contentItem.contentX
        y: row.y
        width: scrollView.contentItem.width
        height: row.height
        color: Qt.tint(editor.palette.base, editor.palette.base.hslLightness < 0.5 ? "#19ffffff" : "#0f000000")
    }

    // Clips the find bar as it slides in from above the editor.
    Item {
        anchors.fill: scrollView
        clip: true

        FindBar {
            id: findBar

            anchors.right: parent.right
            anchors.rightMargin: 16 // clear of the scroll bar
            zoom: root.fontSize / root.defaultFontSize
            editor: editor
            vim: vim
        }
    }

    Connections {
        target: scrollView.contentItem

        function onContentXChanged() {
            hover.hide();
        }
        function onContentYChanged() {
            hover.hide();
        }
    }

    // The text in a hidden-text 💩, or a warning's or error's message, shown
    // like VS Code's hover: after the pointer rests on it (or on the message
    // after its line), or on gh. Its text can be selected with the mouse and
    // copied. Any other key, a scroll or an edit hides it, and one the
    // pointer opened also hides once the pointer is on neither the target
    // (nor its message) nor the box. It lives in the window's overlay so the
    // editor doesn't clip it.
    Item {
        id: hover

        property int at: -1 // the start of the target
        property bool byMouse: false
        property string text: ""
        property string severity: "" // a diagnostic's: "warning" or "error"
        property rect anchorRect // what the box points at, in the overlay's coordinates
        property int mouseAt: -1 // the start of the target under the pointer
        property rect mouseRect // what's under the pointer: the target or its message
        readonly property bool dark: editor.palette.base.hslLightness < 0.5
        readonly property real maxWidth: Math.min(parent ? parent.width - 32 : 600, 640)
        readonly property real maxHeight: Math.min(parent ? parent.height / 2 : 400, 20 * root.lineHeight)
        readonly property bool held: mouseAt >= 0 && mouseAt === at || boxHover.hovered || press.active

        // Shows the target at pos, pointing at `rect` in the editor (the
        // target itself if not given).
        function show(pos, mouse, rect) {
            const target = targetAt(pos);
            if (!target)
                return;
            severity = target.severity;
            if (severity) {
                text = diagnostics.message(target);
            } else {
                const h = vim.hiddenAt(pos);
                text = vim.revealAll(h.item.text, h.item.hidden).replace(/\n$/, "");
            }
            const a = editor.cellAt(target.start), b = editor.cellAt(target.end);
            const r = rect || Qt.rect(a.x, a.y, b.x - a.x, a.height);
            anchorRect = editor.mapToItem(parent, r.x, r.y, r.width, r.height);
            scroller.contentY = 0;
            byMouse = mouse;
            at = target.start;
        }

        function hide() {
            at = -1;
            label.deselect();
            delay.stop();
            grace.stop();
        }

        // Copies the text selected in the box, if any.
        function copySelection() {
            if (at < 0 || label.selectedText === "")
                return false;
            label.copy();
            return true;
        }

        // What there is to show at pos, as { start, end, severity }: the 💩
        // with hidden text starting there (with no severity), or the warning
        // or error with the character there. Null if nothing.
        function targetAt(pos) {
            if (vim.hiddenAt(pos))
                return {
                    start: pos,
                    end: pos + vim.poop.length,
                    severity: ""
                };
            return diagnostics.at(pos);
        }

        // The target at point p in the editor, or with its message there, as
        // { start, rect } (the rectangle under p), or null.
        function targetUnder(p) {
            if (!p)
                return null;
            const t = editor.text, pos = editor.positionAt(p.x, p.y);
            // positionAt gives the nearest gap, which is after the character on its right half.
            for (const c of [pos, pos > 0 ? vim.charStart(t, pos - 1) : -1]) {
                const target = c >= 0 ? targetAt(c) : null;
                if (!target)
                    continue;
                const a = editor.cellAt(target.start), b = editor.cellAt(target.end);
                if (p.x >= a.x && p.x < b.x && p.y >= a.y && p.y < a.y + a.height)
                    return {
                        start: target.start,
                        rect: Qt.rect(a.x, a.y, b.x - a.x, a.height)
                    };
            }
            return diagnostics.messageUnder(p);
        }

        function pointerAt(p) {
            const under = targetUnder(p);
            const c = under ? under.start : -1;
            if (c === mouseAt)
                return;
            mouseAt = c;
            if (under)
                mouseRect = under.rect;
            delay.stop();
            if (c >= 0 && c !== at)
                delay.restart();
        }

        parent: Overlay.overlay
        visible: at >= 0
        width: frame.width
        height: frame.height
        // Above the target, or below it when there's no room.
        x: Math.max(8, Math.min(anchorRect.x, (parent ? parent.width : 0) - width - 8))
        y: anchorRect.y - height - 4 >= 4 ? anchorRect.y - height - 4 : anchorRect.y + anchorRect.height + 4
        // A little time to cross the gap between the target and the box.
        onHeldChanged: {
            if (held || at < 0 || !byMouse)
                grace.stop();
            else
                grace.restart();
        }

        Timer {
            id: delay

            interval: 300
            onTriggered: hover.show(hover.mouseAt, true, hover.mouseRect)
        }

        Timer {
            id: grace

            interval: 300
            onTriggered: hover.hide()
        }

        Rectangle {
            id: frame

            width: scroller.x + scroller.width + 8
            height: scroller.height + 8
            radius: 4
            color: Qt.tint(editor.palette.base, hover.dark ? "#12ffffff" : "#08000000")
            border.color: Qt.tint(editor.palette.base, hover.dark ? "#40ffffff" : "#30000000")
            layer.enabled: hover.visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.6
                shadowVerticalOffset: 2
                shadowColor: hover.dark ? "#a0000000" : "#40000000"
            }

            HoverHandler {
                id: boxHover

                cursorShape: Qt.IBeamCursor
            }
            // Held while a selection is dragged, even outside the box.
            PointHandler {
                id: press

                acceptedButtons: Qt.LeftButton
            }

            // A diagnostic's icon, as in VS Code: a triangle for a warning,
            // a circle for an error. Centered on the first line.
            Item {
                id: icon

                visible: hover.severity !== ""
                x: 8
                y: scroller.y + (metrics.height - height) / 2
                width: 16 * diagnostics.zoom
                height: width

                Shape {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    scale: diagnostics.zoom // a vector shape, so it stays sharp
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: diagnostics.color(hover.severity)
                        strokeWidth: 1.3
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: hover.severity === "error" ? "M1.5 8 A6.5 6.5 0 1 1 14.5 8 A6.5 6.5 0 1 1 1.5 8 Z M5.7 5.7 L10.3 10.3 M10.3 5.7 L5.7 10.3" : "M8 1.8 L14.5 13.8 L1.5 13.8 Z M8 6.2 L8 9.6 M8 11.8 L8 11.9"
                        }
                    }
                }
            }

            // Not interactive, since a drag selects text; the wheel scrolls it.
            Flickable {
                id: scroller

                x: icon.visible ? icon.x + icon.width + 6 * diagnostics.zoom : 8
                y: 4
                // Room beside the text for the scroll bar, when there is one.
                width: label.width + (contentHeight > height ? scrollBar.width + 4 : 0)
                height: Math.min(label.height, hover.maxHeight - 8)
                contentWidth: label.width
                contentHeight: label.height
                interactive: false
                clip: true

                ScrollBar.vertical: ScrollBar {
                    id: scrollBar
                }

                WheelHandler {
                    onWheel: event => {
                        const dy = event.pixelDelta.y || event.angleDelta.y / 120 * 3 * root.lineHeight;
                        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, scroller.contentY - dy));
                    }
                }

                TextEdit {
                    id: label

                    width: Math.min(implicitWidth, hover.maxWidth - scroller.x - 8)
                    text: hover.text
                    font: editor.font
                    color: editor.color
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    readOnly: true
                    selectByMouse: true
                    // Keys stay with the editor, which forwards Copy (see copySelection).
                    activeFocusOnPress: false
                    persistentSelection: true
                    selectionColor: editor.palette.highlight
                    selectedTextColor: editor.palette.highlightedText
                }
            }
        }
    }

    footer: Pane {
        contentHeight: position.implicitHeight
        padding: 4
        leftPadding: 8
        rightPadding: 8

        Label {
            id: status

            anchors.left: parent.left
            anchors.right: position.left
            elide: Text.ElideRight
            font.family: editor.font.family
            font.pointSize: editor.font.pointSize
            textFormat: Text.PlainText
            color: vim.commandLine === "" && vim.message !== "" && vim.messageIsError ? "#d33" : palette.windowText
            text: vim.commandLine || vim.message || vim.modeLabel || " "

            // Measured with TextMetrics, whose widths are properties, so they
            // follow font size changes (FontMetrics.advanceWidth() is a call).
            TextMetrics {
                id: beforeCursor

                font: status.font
                text: vim.commandLine.slice(0, vim.commandCursor)
            }
            TextMetrics {
                id: underCursor

                font: status.font
                text: commandCursor.character || " "
            }

            // Command-line cursor: a block over the character it's on.
            Rectangle {
                id: commandCursor

                readonly property string character: vim.commandLine.charAt(vim.commandCursor)

                visible: vim.commandLine !== ""
                x: beforeCursor.advanceWidth
                width: underCursor.advanceWidth
                height: parent.height
                color: status.color

                Text {
                    text: parent.character
                    font: status.font
                    color: status.palette.window
                    textFormat: Text.PlainText
                }
            }
        }

        Label {
            id: position

            anchors.right: parent.right
            font.family: editor.font.family
            font.pointSize: editor.font.pointSize
            text: vim.pendingKeys + "    " + vim.positionLabel()
        }
    }

    FileDialog {
        id: openDialog

        fileMode: FileDialog.OpenFile
        nameFilters: ["Text files (*.txt)", "All files (*)"]
        onAccepted: doc.openFile(doc.urlToPath(selectedFile))
    }

    FileDialog {
        id: saveDialog

        fileMode: FileDialog.SaveFile
        defaultSuffix: "txt"
        nameFilters: ["Text files (*.txt)", "All files (*)"]
        onAccepted: {
            const path = doc.urlToPath(selectedFile);
            if (doc.saveFile(path, editor.text)) {
                root.filePath = path;
                root.modified = false;
                if (root.quitAfterSave)
                    Qt.quit();
            }
            root.quitAfterSave = false;
        }
        onRejected: root.quitAfterSave = false
    }

    MessageDialog {
        id: errorDialog

        buttons: MessageDialog.Ok
    }

    // macOS: native menu bar. The Quit/Preferences roles make Qt move those
    // items into the application ("VimEdit") menu.
    Component {
        id: macMenuBar

        Platform.MenuBar {
            Platform.Menu {
                title: qsTr("File")

                Platform.MenuItem {
                    text: qsTr("Open…")
                    shortcut: StandardKey.Open
                    onTriggered: root.openFile()
                }
                Platform.MenuItem {
                    text: qsTr("Save")
                    shortcut: StandardKey.Save
                    onTriggered: root.save()
                }
                Platform.MenuItem {
                    text: qsTr("Save As…")
                    shortcut: StandardKey.SaveAs
                    onTriggered: root.saveAs()
                }
                Platform.MenuItem {
                    text: qsTr("Settings…")
                    role: Platform.MenuItem.PreferencesRole
                    shortcut: StandardKey.Preferences
                    onTriggered: settingsWindow.open()
                }
                Platform.MenuItem {
                    text: qsTr("Quit VimEdit")
                    role: Platform.MenuItem.QuitRole
                    shortcut: StandardKey.Quit
                    onTriggered: Qt.quit()
                }
            }
            Platform.Menu {
                title: qsTr("Edit")

                Platform.MenuItem {
                    text: qsTr("Hide or Reveal Text")
                    shortcut: "Ctrl+J" // Qt maps Ctrl to Cmd
                    onTriggered: root.toggleHidden()
                }
                Platform.MenuSeparator {}
                Platform.MenuItem {
                    text: qsTr("Find")
                    shortcut: StandardKey.Find
                    onTriggered: findBar.open(false)
                }
                Platform.MenuItem {
                    text: qsTr("Replace")
                    shortcut: "Ctrl+Alt+F" // Cmd+Option+F, as in VS Code
                    onTriggered: findBar.open(true)
                }
                Platform.MenuItem {
                    text: qsTr("Find Next")
                    shortcut: StandardKey.FindNext
                    onTriggered: findBar.findNext(1)
                }
                Platform.MenuItem {
                    text: qsTr("Find Previous")
                    shortcut: StandardKey.FindPrevious
                    onTriggered: findBar.findNext(-1)
                }
            }
            Platform.Menu {
                title: qsTr("View")

                Platform.MenuItem {
                    text: qsTr("Zoom In")
                    shortcut: StandardKey.ZoomIn
                    onTriggered: root.zoom(1)
                }
                Platform.MenuItem {
                    text: qsTr("Zoom Out")
                    shortcut: StandardKey.ZoomOut
                    onTriggered: root.zoom(-1)
                }
                Platform.MenuItem {
                    text: qsTr("Actual Size")
                    shortcut: "Ctrl+0" // no StandardKey; Qt maps Ctrl to Cmd
                    onTriggered: root.fontSize = root.defaultFontSize
                }
            }
        }
    }

    // Windows / Linux: regular in-window menu bar.
    Component {
        id: windowMenuBar

        MenuBar {
            Menu {
                title: qsTr("&File")

                Action {
                    text: qsTr("&Open…")
                    shortcut: StandardKey.Open
                    onTriggered: root.openFile()
                }
                Action {
                    text: qsTr("&Save")
                    shortcut: StandardKey.Save
                    onTriggered: root.save()
                }
                Action {
                    text: qsTr("Save &As…")
                    shortcut: StandardKey.SaveAs
                    onTriggered: root.saveAs()
                }
                MenuSeparator {}
                Action {
                    text: qsTr("Se&ttings")
                    // Preferences and Quit have no Ctrl binding on Windows.
                    shortcut: "Ctrl+,"
                    onTriggered: settingsWindow.open()
                }
                MenuSeparator {}
                Action {
                    text: qsTr("E&xit")
                    shortcut: "Ctrl+Q"
                    onTriggered: Qt.quit()
                }
            }
            Menu {
                title: qsTr("&Edit")

                Action {
                    text: qsTr("&Hide or Reveal Text")
                    shortcut: "Ctrl+J"
                    onTriggered: root.toggleHidden()
                }
                MenuSeparator {}
                Action {
                    text: qsTr("&Find")
                    shortcut: StandardKey.Find
                    onTriggered: findBar.open(false)
                }
                Action {
                    text: qsTr("&Replace")
                    shortcut: StandardKey.Replace // Ctrl+H, as in VS Code
                    onTriggered: findBar.open(true)
                }
                // F3, plus Ctrl+G from findNextShortcut. Written out, since
                // an Action takes only the first of a StandardKey's keys.
                Action {
                    text: qsTr("Find &Next")
                    shortcut: "F3"
                    onTriggered: findBar.findNext(1)
                }
                Action {
                    text: qsTr("Find &Previous")
                    shortcut: "Shift+F3"
                    onTriggered: findBar.findNext(-1)
                }
            }
            Menu {
                title: qsTr("&View")

                Action {
                    text: qsTr("Zoom &In")
                    // StandardKey.ZoomIn is only Ctrl++ (Ctrl+Shift+=) here;
                    // zoomInShortcut adds that.
                    shortcut: "Ctrl+="
                    onTriggered: root.zoom(1)
                }
                Action {
                    text: qsTr("Zoom &Out")
                    shortcut: StandardKey.ZoomOut
                    onTriggered: root.zoom(-1)
                }
                Action {
                    text: qsTr("&Actual Size")
                    shortcut: "Ctrl+0" // no StandardKey for this
                    onTriggered: root.fontSize = root.defaultFontSize
                }
            }
        }
    }

    // Windows / Linux: the menu's Zoom In is Ctrl+=; this keeps Ctrl++ too.
    // On macOS, StandardKey.ZoomIn already covers both.
    Shortcut {
        id: zoomInShortcut

        enabled: !root.isMac
        sequences: [StandardKey.ZoomIn]
        onActivated: root.zoom(1)
    }

    // Windows / Linux: the menu's Find Next and Find Previous are F3 and
    // Shift+F3; these add Ctrl+G and Ctrl+Shift+G, like Cmd+G on macOS.
    Shortcut {
        id: findNextShortcut

        enabled: !root.isMac
        sequence: "Ctrl+G"
        onActivated: findBar.findNext(1)
    }
    Shortcut {
        enabled: !root.isMac
        sequence: "Ctrl+Shift+G"
        onActivated: findBar.findNext(-1)
    }

    // Windows / Linux: Fusion frames a TextArea like a text field, which
    // doesn't suit a full-window editor.
    Component {
        id: plainBackground

        Rectangle {
            color: editor.palette.base
        }
    }

    Component.onCompleted: {
        if (isMac) {
            macMenuBar.createObject(root, {
                window: root
            });
        } else {
            root.menuBar = windowMenuBar.createObject(root);
            editor.background = plainBackground.createObject(editor);
        }

        // The editor sits in a ScrollView, which is its own focus scope, so
        // `focus: true` alone doesn't give it the keyboard.
        editor.forceActiveFocus();
        fixLineFormat();
        applyTheme();

        const startup = doc.startupFile();
        if (startup)
            doc.openFile(startup);
    }
}
