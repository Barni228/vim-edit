import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Qt.labs.platform as Platform

import VimEdit

ApplicationWindow {
    id: root

    readonly property bool isMac: Qt.platform.os === "osx"
    property string filePath: ""
    property bool modified: false
    readonly property int defaultFontSize: 16
    property int fontSize: defaultFontSize
    // Every line is this tall, even one with an emoji (see fixLineHeight).
    // The extra space keeps an emoji clear of the lines around it.
    readonly property int lineHeight: Math.ceil(metrics.lineSpacing * 1.25)

    width: 900
    height: 650
    visible: true
    title: (filePath ? filePath.split(/[\\/]/).pop() : "Untitled") + (modified ? " •" : "") + " — VimEdit"

    function openFile() {
        openDialog.open();
    }

    function save() {
        if (!filePath) {
            saveAs();
            return;
        }
        if (doc.saveFile(filePath, editor.text))
            modified = false;
    }

    function saveAs() {
        saveDialog.open();
    }

    function zoom(step) {
        fontSize = Math.max(6, Math.min(72, fontSize + step));
    }

    // An emoji comes from a taller font than the editor's, which makes its line
    // taller. Give every line the same height instead. The block format that
    // does this counts as an edit, but isn't one.
    function fixLineHeight() {
        const wasModified = modified;
        doc.setLineHeight(editor.textDocument, lineHeight);
        modified = wasModified;
    }

    onLineHeightChanged: fixLineHeight()

    function toggleHidden() {
        vim.toggleHidden();
        editor.forceActiveFocus();
    }

    function insertSettings() {
        vim.externalEdit(() => editor.insert(editor.cursorPosition, "Settings"));
        editor.forceActiveFocus();
    }

    Document {
        id: doc

        onLoaded: (path, text) => {
            editor.text = text;
            root.fixLineHeight(); // setting the text reset it
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
        flickable: scrollView.contentItem
        clipboard: doc
        lineHeight: root.lineHeight

        onWriteRequested: quit => {
            root.save();
            if (quit && !root.modified)
                Qt.quit();
        }
        onQuitRequested: force => {
            if (force || !root.modified)
                Qt.quit();
            else
                vim.showError("E37: No write since last change (add ! to override)");
        }
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

            // The rectangle of the character at pos. positionToRectangle gives
            // a line with an emoji its natural height, but every line is
            // root.lineHeight tall (see fixLineHeight), so snap to that.
            function cellAt(pos) {
                const r = positionToRectangle(pos);
                const h = root.lineHeight;
                const line = Math.round((r.y + r.height / 2 - topPadding - h / 2) / h);
                return Qt.rect(r.x, topPadding + line * h, r.width, h);
            }

            // Where the baseline is in a cell: Qt puts a fixed-height line's
            // baseline at 4/5.
            readonly property real textBaseline: root.lineHeight * 0.8

            // The part of the cell at pos that the font's characters take up.
            // The cursors and highlights use it rather than Qt's rectangles,
            // which on a line with an emoji are as tall as the emoji.
            function bandAt(pos) {
                const c = cellAt(pos);
                return Qt.rect(c.x, c.y + textBaseline - metrics.ascent, c.width, metrics.height);
            }

            // The selection in the visible lines, as one { start, end, eol }
            // span per line, where eol means it includes the line break.
            function selectionSpans() {
                const s = selectionStart, e = selectionEnd;
                if (s === e)
                    return [];
                const t = text, f = scrollView.contentItem;
                const top = Math.floor((f.contentY - topPadding) / root.lineHeight);
                const bottom = Math.ceil((f.contentY + f.height - topPadding) / root.lineHeight);
                const to = Math.min(e, vim.lineEnd(t, vim.lineToPos(t, Math.max(bottom, 0) + 1)));
                const spans = [];
                for (let p = Math.max(s, vim.lineToPos(t, Math.max(top, 0) + 1)); p <= to;) {
                    const le = vim.lineEnd(t, p);
                    if (p === e)
                        break;
                    spans.push({ start: p, end: Math.min(le, e), eol: le < e });
                    p = le + 1;
                }
                return spans;
            }

            font.family: root.isMac ? "Menlo" : "Consolas"
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
            onCursorPositionChanged: vim.syncFromEditor()
            onSelectedTextChanged: vim.syncFromEditor()
            Keys.onPressed: event => event.accepted = vim.handleKey(event)

            // Insert mode: a blinking bar. The editor puts the delegate at its
            // cursor rectangle; the bar itself fills the text band.
            cursorDelegate: Item {
                id: bar

                property bool blinkOn: true

                width: 2
                visible: vim.mode === "insert" && editor.activeFocus && blinkOn

                Rectangle {
                    y: editor.bandAt(editor.cursorPosition).y - bar.y
                    width: parent.width
                    height: metrics.height
                    color: editor.color
                }

                Timer {
                    interval: 530
                    repeat: true
                    running: vim.mode === "insert" && editor.activeFocus
                    onRunningChanged: bar.blinkOn = true
                    onTriggered: bar.blinkOn = !bar.blinkOn
                }
                Connections {
                    target: editor

                    function onCursorPositionChanged() {
                        bar.blinkOn = true;
                    }
                }
            }

            // The selection, drawn under the text (a negative z puts a child
            // below its parent's content) with the same height on every line.
            Item {
                id: selection

                property var spans: []
                readonly property var inputs: [editor.selectionStart, editor.selectionEnd, editor.revision,
                    scrollView.contentItem.contentY, scrollView.contentItem.height,
                    editor.contentWidth, editor.contentHeight]

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
                        readonly property rect startRect: editor.bandAt(modelData.start)
                        readonly property rect endRect: editor.bandAt(modelData.end)

                        x: startRect.x
                        y: startRect.y
                        // A selected line break shows as a space, as in Qt.
                        width: endRect.x - startRect.x + (modelData.eol ? spaceMetrics.advanceWidth : 0)
                        height: startRect.height
                        color: editor.palette.highlight
                    }
                }
            }

            // Search matches: the search being typed, or the last one until
            // Esc. Like the block cursor below, they refresh after an edit
            // finishes rather than halfway through one.
            Item {
                id: highlights

                property var spans: []
                readonly property var inputs: [editor.revision, vim.commandLine, vim.highlightPattern,
                    vim.searchTarget, scrollView.contentItem.contentY, scrollView.contentItem.height,
                    editor.contentWidth, editor.contentHeight] // these follow font size changes

                function refresh() {
                    // The Repeater keeps its delegates when the new spans equal
                    // the old ones, but after a relayout their rectangles must
                    // be recomputed, so always start from an empty model.
                    spans = [];
                    spans = vim.searchHighlights();
                }

                onInputsChanged: Qt.callLater(refresh)

                Repeater {
                    model: highlights.spans

                    Rectangle {
                        required property var modelData
                        readonly property rect startRect: editor.bandAt(modelData.start)
                        readonly property rect endRect: editor.bandAt(modelData.end)

                        x: startRect.x
                        y: startRect.y
                        width: endRect.x - startRect.x
                        height: startRect.height
                        color: modelData.match === vim.highlightTarget ? "#ff9f1a" : "#f5d547"

                        // Redraw the matched text on top, dark on the highlight.
                        Text {
                            y: metrics.ascent - baselineOffset
                            text: editor.getText(modelData.start, modelData.end)
                            font: editor.font
                            color: "black"
                            textFormat: Text.PlainText
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
                    cell = editor.bandAt(pos);
                    const t = editor.text;
                    const c = t.slice(pos, vim.charEnd(t, pos)); // e.g. a whole emoji
                    character = c === "\t" || c === "\n" || c === "\u2029" ? "" : c;
                }

                Connections {
                    target: editor

                    function onRevisionChanged() {
                        Qt.callLater(block.refresh);
                    }
                    // Also follow layout changes: padding set by the style, and
                    // font size changes (which move the cursor rectangle only
                    // once it's next updated, so also watch the content size).
                    function onCursorRectangleChanged() {
                        Qt.callLater(block.refresh);
                    }
                    function onFontChanged() {
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
                    y: metrics.ascent - baselineOffset
                    visible: !parent.underline
                    text: parent.character
                    font: editor.font
                    color: editor.palette.base
                    textFormat: Text.PlainText
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
            }
        }
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
                    onTriggered: root.insertSettings()
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
                    onTriggered: root.insertSettings()
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
            }
            Menu {
                title: qsTr("&View")

                Action {
                    text: qsTr("Zoom &In")
                    shortcut: StandardKey.ZoomIn
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

    Component.onCompleted: {
        if (isMac)
            macMenuBar.createObject(root, { window: root });
        else
            root.menuBar = windowMenuBar.createObject(root);

        // The editor sits in a ScrollView, which is its own focus scope, so
        // `focus: true` alone doesn't give it the keyboard.
        editor.forceActiveFocus();
        fixLineHeight();

        const startup = doc.startupFile();
        if (startup)
            doc.openFile(startup);
    }
}
