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
        editor.insert(editor.cursorPosition, "Settings");
        editor.forceActiveFocus();
    }

    Document {
        id: doc

        onLoaded: (path, text) => {
            editor.text = text;
            editor.cursorPosition = 0;
            root.filePath = path;
            root.modified = false;
            editor.forceActiveFocus();
        }
        onFailed: message => {
            errorDialog.text = message;
            errorDialog.open();
        }
    }

    ScrollView {
        anchors.fill: parent

        TextArea {
            id: editor

            font.family: root.isMac ? "Menlo" : "Consolas"
            font.pointSize: 13
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            focus: true
            onTextChanged: root.modified = true
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
