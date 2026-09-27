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

    function insertSettings() {
        vim.externalEdit(() => editor.insert(editor.cursorPosition, "Settings"));
        editor.forceActiveFocus();
    }

    Document {
        id: doc

        onLoaded: (path, text) => {
            editor.text = text;
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
        lineHeight: metrics.lineSpacing

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

            // Bumped on every edit, so bindings that call methods (which QML
            // can't track) re-evaluate.
            property int revision: 0

            font.family: root.isMac ? "Menlo" : "Consolas"
            font.pointSize: 13
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            readOnly: true // vim starts in normal mode
            focus: true
            onTextChanged: {
                root.modified = true;
                revision++;
            }
            onCursorPositionChanged: vim.syncFromEditor()
            onSelectedTextChanged: vim.syncFromEditor()
            Keys.onPressed: event => event.accepted = vim.handleKey(event)

            // Insert mode: a blinking bar.
            cursorDelegate: Rectangle {
                id: bar

                property bool blinkOn: true

                width: 2
                color: editor.color
                visible: vim.mode === "insert" && editor.activeFocus && blinkOn

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
                    cell = editor.positionToRectangle(pos);
                    const c = pos < editor.length ? editor.getText(pos, pos + 1) : "";
                    character = c === "\t" || c === "\n" || c === "\u2029" ? "" : c;
                }

                Connections {
                    target: editor

                    function onRevisionChanged() {
                        Qt.callLater(block.refresh);
                    }
                    // Also covers layout changes, like padding set by the style.
                    function onCursorRectangleChanged() {
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

                visible: vim.mode !== "insert"
                x: cell.x
                y: underline ? cell.y + cell.height - height : cell.y
                width: character ? metrics.advanceWidth(character) : metrics.averageCharacterWidth
                height: underline ? Math.max(2, Math.round(cell.height / 8)) : cell.height
                color: editor.color
                opacity: editor.activeFocus ? 1 : 0.4

                Text {
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
            anchors.left: parent.left
            anchors.right: position.left
            elide: Text.ElideRight
            font.family: editor.font.family
            color: vim.commandLine === "" && vim.message !== "" && vim.messageIsError ? "#d33" : palette.windowText
            text: vim.commandLine !== "" ? vim.commandLine + "\u2588" : vim.message || vim.modeLabel || " "
        }

        Label {
            id: position

            anchors.right: parent.right
            font.family: editor.font.family
            text: {
                editor.revision;
                return vim.pendingKeys + "    " + vim.positionLabel();
            }
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
                    shortcut: "Ctrl+Shift+S"
                    onTriggered: root.saveAs()
                }
                Platform.MenuItem {
                    text: qsTr("Settings…")
                    role: Platform.MenuItem.PreferencesRole
                    shortcut: "Ctrl+," // Ctrl is mapped to Cmd on macOS
                    onTriggered: root.insertSettings()
                }
                Platform.MenuItem {
                    text: qsTr("Quit VimEdit")
                    role: Platform.MenuItem.QuitRole
                    shortcut: StandardKey.Quit
                    onTriggered: Qt.quit()
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
                    shortcut: "Ctrl+Shift+S"
                    onTriggered: root.saveAs()
                }
                MenuSeparator {}
                Action {
                    text: qsTr("Se&ttings")
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
        }
    }

    Component.onCompleted: {
        if (isMac)
            macMenuBar.createObject(root, { window: root });
        else
            root.menuBar = windowMenuBar.createObject(root);

        const startup = doc.startupFile();
        if (startup)
            doc.openFile(startup);
    }
}
