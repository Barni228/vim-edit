pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Templates as T

// The Settings window (Cmd+,): font, font size, line numbers and theme, and
// whether the zoom and :set change them. It shows the settings in use, and
// changes here apply at once and are saved (app.changeSetting). Each setting
// has a button that resets it to its default, and Restore Defaults resets
// them all.
Window {
    id: win

    required property var app // main.qml's window: fontFamily, fontSize, theme
    required property var vim // number, relativeNumber
    required property TextArea editor
    required property var settings // the saved settings: keepChanges

    // Follows the editor's zoom (Cmd+ and Cmd-), like every text in the app.
    readonly property real zoom: app.fontSize / app.defaultFontSize
    readonly property bool dark: editor.palette.base.hslLightness < 0.5
    readonly property color textColor: editor.palette.windowText
    readonly property color accent: editor.palette.accent
    readonly property color hoverColor: dark ? "#26ffffff" : "#1a000000"
    readonly property color fieldColor: dark ? Qt.tint(editor.palette.base, "#1effffff") : editor.palette.base
    readonly property color borderColor: dark ? Qt.tint(editor.palette.window, "#30ffffff") : "#cecece"

    // Line numbers as one choice: :set nonu nornu, nu, rnu, or both.
    readonly property var lineNumberModes: [
        { label: qsTr("Off"), number: false, relative: false },
        { label: qsTr("On"), number: true, relative: false },
        { label: qsTr("Relative"), number: false, relative: true },
        { label: qsTr("Hybrid"), number: true, relative: true }
    ]
    readonly property int lineNumberMode: lineNumberModes.findIndex(
        m => m.number === vim.number && m.relative === vim.relativeNumber)
    readonly property var themes: [
        { label: qsTr("System"), value: "system" },
        { label: qsTr("Light"), value: "light" },
        { label: qsTr("Dark"), value: "dark" }
    ]

    readonly property bool customFontFamily: app.fontFamily !== app.defaultFontFamily
    readonly property bool customFontSize: app.fontSize !== app.defaultFontSize
    readonly property bool customLineNumbers: lineNumberMode !== 0
    readonly property bool customTheme: app.theme !== "system"
    readonly property bool customKeepChanges: settings.keepChanges

    function setFontSize(size) {
        app.changeSetting("fontSize", Math.max(app.minFontSize, Math.min(app.maxFontSize, size)));
    }
    function setLineNumberMode(i) {
        app.changeSetting("number", lineNumberModes[i].number);
        app.changeSetting("relativeNumber", lineNumberModes[i].relative);
    }
    function restoreDefaults() {
        app.changeSetting("fontFamily", app.defaultFontFamily);
        setFontSize(app.defaultFontSize);
        setLineNumberMode(0);
        app.changeSetting("theme", "system");
        settings.keepChanges = false;
    }

    // Shows the window, centered near the top of the main window the first
    // time and whenever it was closed.
    function open() {
        if (!visible) {
            x = app.x + Math.round((app.width - width) / 2);
            y = app.y + Math.round(Math.min(80 * zoom, Math.max(0, (app.height - height) / 2)));
        }
        show();
        raise();
        requestActivate();
    }

    title: qsTr("Settings")
    flags: Qt.Dialog
    color: editor.palette.window
    // Its size follows the zoom, so it isn't resizable.
    readonly property int fitWidth: Math.ceil(content.implicitWidth + 2 * content.x)
    readonly property int fitHeight: Math.ceil(content.implicitHeight + 2 * content.y)

    width: fitWidth
    height: fitHeight
    minimumWidth: fitWidth
    maximumWidth: fitWidth
    minimumHeight: fitHeight
    maximumHeight: fitHeight

    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: win.close()
    }
    // Not while the font list is open, which Esc closes.
    Shortcut {
        sequence: "Escape"
        enabled: !fontList.visible
        onActivated: win.close()
    }

    // Styled like the find bar's tooltips.
    component Tip: ToolTip {
        id: tooltip

        delay: 600
        padding: 0
        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 100
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                to: 0
                duration: 100
            }
        }

        contentItem: Text {
            leftPadding: 8 * win.zoom
            rightPadding: 8 * win.zoom
            topPadding: 4 * win.zoom
            bottomPadding: 4 * win.zoom
            text: tooltip.text
            font.pixelSize: Math.round(12 * win.zoom)
            color: win.editor.color
            textFormat: Text.PlainText
        }
        background: Rectangle {
            radius: 4 * win.zoom
            color: Qt.tint(win.editor.palette.base, win.dark ? "#12ffffff" : "#08000000")
            border.color: Qt.tint(win.editor.palette.base, win.dark ? "#40ffffff" : "#30000000")
            layer.enabled: tooltip.visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.6
                shadowVerticalOffset: 2
                shadowColor: win.dark ? "#a0000000" : "#40000000"
            }
        }
    }

    // An SVG path in a 16×16 box, drawn with lines.
    component Icon: Item {
        id: icon

        property string path

        implicitWidth: 16 * win.zoom
        implicitHeight: 16 * win.zoom

        Shape {
            anchors.centerIn: parent
            width: 16
            height: 16
            scale: win.zoom // a vector shape, so it stays sharp
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: win.textColor
                strokeWidth: 1.3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: icon.path
                }
            }
        }
    }

    // A small button with an icon.
    component IconButton: AbstractButton {
        id: button

        property string iconPath
        property string tip

        implicitWidth: 22 * win.zoom
        implicitHeight: 22 * win.zoom
        padding: 0
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        opacity: enabled ? 1 : 0.4
        Accessible.name: tip

        Tip {
            visible: button.hovered && button.tip !== ""
            text: button.tip
            x: Math.round((button.width - width) / 2)
            y: button.height + 6 * win.zoom
        }

        background: Rectangle {
            radius: 3 * win.zoom
            color: button.hovered || button.pressed ? win.hoverColor : "transparent"
            border.color: button.visualFocus ? win.accent : "transparent"
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                path: button.iconPath
            }
        }
    }

    // Resets one setting; hidden while it has its default value.
    component ResetButton: IconButton {
        iconPath: "M6 3 L3 6 L6 9 M3 6 H10 A3 3 0 0 1 10 12 H7"
        tip: qsTr("Reset to Default")
        opacity: enabled ? 1 : 0
    }

    // One of a few options, as a row of buttons.
    component Segmented: Rectangle {
        id: segmented

        property var options: [] // { label }
        property int current: -1

        signal picked(int index)

        implicitWidth: row.implicitWidth + 4 * win.zoom
        implicitHeight: 26 * win.zoom
        radius: 4 * win.zoom
        color: win.fieldColor
        border.color: win.borderColor

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 2 * win.zoom

            Repeater {
                model: segmented.options

                AbstractButton {
                    id: option

                    required property var modelData
                    required property int index
                    readonly property bool selected: index === segmented.current

                    implicitWidth: optionText.implicitWidth + 20 * win.zoom
                    implicitHeight: segmented.height - 4 * win.zoom
                    focusPolicy: Qt.TabFocus
                    hoverEnabled: true
                    Accessible.name: modelData.label
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    onClicked: segmented.picked(index)

                    background: Rectangle {
                        radius: 3 * win.zoom
                        color: option.selected ? win.accent : option.hovered ? win.hoverColor : "transparent"
                        border.color: option.visualFocus ? win.accent : "transparent"
                    }
                    contentItem: Text {
                        id: optionText

                        text: option.modelData.label
                        font.pixelSize: Math.round(13 * win.zoom)
                        color: option.selected ? win.editor.palette.highlightedText : win.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    component SettingLabel: Label {
        font.pixelSize: Math.round(13 * win.zoom)
        color: win.textColor
    }

    ColumnLayout {
        id: content

        x: 20 * win.zoom
        y: 16 * win.zoom
        spacing: 16 * win.zoom

        GridLayout {
            columns: 3
            columnSpacing: 12 * win.zoom
            rowSpacing: 10 * win.zoom

            SettingLabel {
                text: qsTr("Font")
            }
            // The installed monospaced fonts, each shown in itself. Typing in
            // the field searches them (for every word, in any case); Up/Down
            // and Return pick one, and Esc goes back to the font in use.
            Rectangle {
                id: fontPicker

                // The fonts in the list, and the one Return picks.
                property var matches: []
                property int highlighted: -1
                // Whether the field holds a search rather than the font in use.
                property bool searching: false

                function showList() {
                    win.app.loadFontFamilies();
                    matches = win.app.fontFamilies;
                    highlighted = matches.indexOf(win.app.fontFamily);
                    fontList.open();
                    fontListView.positionViewAtIndex(Math.max(0, highlighted), ListView.Center);
                }
                function search(query) {
                    win.app.loadFontFamilies();
                    const words = query.toLowerCase().split(/\s+/).filter(w => w);
                    matches = win.app.fontFamilies.filter(f => words.every(w => f.toLowerCase().includes(w)));
                    highlighted = matches.length ? 0 : -1;
                    searching = true;
                    fontList.open();
                    fontListView.positionViewAtBeginning();
                }
                function move(step) {
                    if (!fontList.visible) {
                        showList();
                    } else if (matches.length) {
                        highlighted = Math.max(0, Math.min(matches.length - 1, highlighted + step));
                        fontListView.positionViewAtIndex(highlighted, ListView.Contain);
                    }
                }
                // Return: picks the highlighted font, or shows the list.
                function accept() {
                    if (fontList.visible)
                        finish(matches[highlighted]);
                    else
                        showList();
                }
                // Closes the list, after picking `family` if given.
                function finish(family) {
                    if (family)
                        win.app.changeSetting("fontFamily", family);
                    fontList.close();
                }

                Layout.fillWidth: true
                implicitWidth: 180 * win.zoom
                implicitHeight: 26 * win.zoom
                radius: 4 * win.zoom
                color: win.fieldColor
                border.color: fontSearch.activeFocus ? win.accent : win.borderColor

                TextInput {
                    id: fontSearch

                    x: 8 * win.zoom
                    width: parent.width - x - fontButton.width - 2 * win.zoom
                    height: parent.height
                    clip: true
                    text: win.app.fontFamily
                    font.family: fontPicker.searching ? Application.font.family : win.app.fontFamily
                    font.pixelSize: Math.round(13 * win.zoom)
                    color: win.textColor
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    selectionColor: win.editor.palette.highlight
                    selectedTextColor: win.editor.palette.highlightedText
                    Accessible.name: qsTr("Font")
                    onTextEdited: fontPicker.search(text)
                    onActiveFocusChanged: {
                        if (activeFocus)
                            selectAll();
                        else
                            fontPicker.finish();
                    }
                    Keys.onUpPressed: fontPicker.move(-1)
                    Keys.onDownPressed: fontPicker.move(1)
                    Keys.onReturnPressed: fontPicker.accept()
                    Keys.onEnterPressed: fontPicker.accept()
                    // Without the list, Esc closes the window.

                    // A click (not one in a search) shows the list and selects
                    // the name, so typing replaces it.
                    TapHandler {
                        onTapped: {
                            if (!fontList.visible) {
                                fontPicker.showList();
                                fontSearch.selectAll();
                            }
                        }
                    }

                    Text {
                        anchors.fill: parent
                        visible: fontPicker.searching && !fontSearch.text
                        text: qsTr("Search fonts")
                        font: fontSearch.font
                        color: win.textColor
                        opacity: 0.5
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                IconButton {
                    id: fontButton

                    anchors.right: parent.right
                    anchors.rightMargin: 2 * win.zoom
                    anchors.verticalCenter: parent.verticalCenter
                    iconPath: "M5 6.5 L8 9.5 L11 6.5"
                    tip: qsTr("Show Fonts")
                    onClicked: {
                        if (fontList.visible) {
                            fontPicker.finish();
                        } else {
                            fontSearch.forceActiveFocus();
                            fontPicker.showList();
                        }
                    }
                }

                // Its own window, so the list isn't cut off by this one. The
                // field keeps the keys, except Esc, which the popup takes.
                T.Popup {
                    id: fontList

                    y: fontPicker.height + 2 * win.zoom
                    width: fontPicker.width
                    height: Math.min(implicitContentHeight + topPadding + bottomPadding, 320 * win.zoom)
                    padding: 4 * win.zoom
                    popupType: Popup.Window
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    onClosed: {
                        fontPicker.searching = false;
                        fontSearch.text = Qt.binding(() => win.app.fontFamily);
                    }

                    contentItem: ListView {
                        id: fontListView

                        clip: true
                        implicitHeight: Math.max(contentHeight, 24 * win.zoom)
                        model: fontPicker.matches
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollIndicator.vertical: ScrollIndicator {}

                        delegate: AbstractButton {
                            id: fontOption

                            required property string modelData
                            required property int index
                            readonly property bool highlighted: fontPicker.highlighted === index

                            width: ListView.view.width
                            implicitHeight: 24 * win.zoom
                            focusPolicy: Qt.NoFocus
                            hoverEnabled: true
                            Accessible.name: modelData
                            onHoveredChanged: if (hovered) fontPicker.highlighted = index
                            onClicked: fontPicker.finish(modelData)

                            background: Rectangle {
                                radius: 3 * win.zoom
                                color: fontOption.highlighted ? win.accent : "transparent"
                            }
                            contentItem: Text {
                                leftPadding: 4 * win.zoom
                                rightPadding: 4 * win.zoom
                                text: fontOption.modelData
                                font.family: fontOption.modelData
                                font.pixelSize: Math.round(13 * win.zoom)
                                color: fontOption.highlighted ? win.editor.palette.highlightedText : win.textColor
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !fontPicker.matches.length
                            text: qsTr("No matching fonts")
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.textColor
                            opacity: 0.6
                        }
                    }
                    background: Rectangle {
                        radius: 4 * win.zoom
                        color: win.fieldColor
                        border.color: win.borderColor
                    }
                }
            }
            ResetButton {
                enabled: win.customFontFamily
                onClicked: win.app.changeSetting("fontFamily", win.app.defaultFontFamily)
            }

            SettingLabel {
                text: qsTr("Font size")
            }
            // − size +, where the size can also be typed.
            Rectangle {
                implicitWidth: sizeRow.implicitWidth + 4 * win.zoom
                implicitHeight: 26 * win.zoom
                radius: 4 * win.zoom
                color: win.fieldColor
                border.color: sizeInput.activeFocus ? win.accent : win.borderColor

                Row {
                    id: sizeRow

                    anchors.centerIn: parent

                    IconButton {
                        iconPath: "M4 8 H12"
                        tip: qsTr("Smaller")
                        enabled: win.app.fontSize > win.app.minFontSize
                        onClicked: win.setFontSize(win.app.fontSize - 1)
                    }
                    TextInput {
                        id: sizeInput

                        width: 36 * win.zoom
                        height: 22 * win.zoom
                        text: win.app.fontSize
                        font.pixelSize: Math.round(13 * win.zoom)
                        color: win.textColor
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        selectionColor: win.editor.palette.highlight
                        selectedTextColor: win.editor.palette.highlightedText
                        validator: IntValidator {
                            bottom: 1
                            top: 999
                        }
                        Accessible.name: qsTr("Font size")
                        onActiveFocusChanged: if (activeFocus) selectAll()
                        onEditingFinished: {
                            const size = parseInt(text);
                            if (!isNaN(size))
                                win.setFontSize(size);
                            text = Qt.binding(() => win.app.fontSize);
                        }
                    }
                    IconButton {
                        iconPath: "M4 8 H12 M8 4 V12"
                        tip: qsTr("Larger")
                        enabled: win.app.fontSize < win.app.maxFontSize
                        onClicked: win.setFontSize(win.app.fontSize + 1)
                    }
                }
            }
            ResetButton {
                enabled: win.customFontSize
                onClicked: win.setFontSize(win.app.defaultFontSize)
            }

            SettingLabel {
                text: qsTr("Line numbers")
            }
            Segmented {
                options: win.lineNumberModes
                current: win.lineNumberMode
                onPicked: index => win.setLineNumberMode(index)
            }
            ResetButton {
                enabled: win.customLineNumbers
                onClicked: win.setLineNumberMode(0)
            }

            SettingLabel {
                text: qsTr("Theme")
            }
            Segmented {
                options: win.themes
                current: win.themes.findIndex(t => t.value === win.app.theme)
                onPicked: index => win.app.changeSetting("theme", win.themes[index].value)
            }
            ResetButton {
                enabled: win.customTheme
                onClicked: win.app.changeSetting("theme", "system")
            }

            // Whether Cmd+ / Cmd- and :set nu / rnu change the settings, or
            // only last until VimEdit quits.
            SettingLabel {
                text: qsTr("Zoom and :set")
            }
            Segmented {
                options: [{ label: qsTr("This Session Only") }, { label: qsTr("Change Settings") }]
                current: win.settings.keepChanges ? 1 : 0
                onPicked: index => win.settings.keepChanges = index === 1
            }
            ResetButton {
                enabled: win.customKeepChanges
                onClicked: win.settings.keepChanges = false
            }
        }

        AbstractButton {
            id: restore

            Layout.alignment: Qt.AlignRight
            implicitWidth: restoreText.implicitWidth + 24 * win.zoom
            implicitHeight: 26 * win.zoom
            enabled: win.customFontFamily || win.customFontSize || win.customLineNumbers || win.customTheme || win.customKeepChanges
            opacity: enabled ? 1 : 0.4
            focusPolicy: Qt.TabFocus
            hoverEnabled: true
            Accessible.name: restoreText.text
            onClicked: win.restoreDefaults()

            background: Rectangle {
                radius: 4 * win.zoom
                color: restore.hovered || restore.pressed ? Qt.tint(win.fieldColor, win.hoverColor) : win.fieldColor
                border.color: restore.visualFocus ? win.accent : win.borderColor
            }
            contentItem: Text {
                id: restoreText

                text: qsTr("Restore Defaults")
                font.pixelSize: Math.round(13 * win.zoom)
                color: win.textColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
