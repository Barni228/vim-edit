import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes

// A find and replace bar like VS Code's: at the top right of the editor,
// with Match Case, Match Whole Word and regular expressions. Moving to a
// match moves vim's cursor to its start; the view draws `matches` (see
// highlightSpans).
FocusScope {
    id: bar

    required property Item editor
    required property var vim

    // Follows the editor's zoom (Cmd+ and Cmd-), like every text in the app.
    property real zoom: 1
    property bool active: false
    property bool replaceShown: false
    property alias query: findField.text
    property alias replacement: replaceField.text
    property bool matchCase: false
    property bool wholeWord: false
    property bool useRegex: false

    // Every match, as { start, end }, and the index of the one at the
    // cursor (-1 if the cursor isn't at the start of one).
    property var matches: []
    property int current: -1
    readonly property int maxMatches: 19999
    // Why the pattern isn't a valid regular expression, or "".
    property string error: ""
    // Where the current match starts: where the bar moved the cursor to,
    // or where it moved some other way (an undo, a motion), which is only a
    // match if one starts there. And where typing a query looks for the
    // first match from.
    property int currentStart: -1
    property int searchStart: 0
    property bool moving: false

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property bool dark: editor.palette.base.hslLightness < 0.5
    readonly property color textColor: editor.color
    readonly property color accent: editor.palette.accent
    readonly property color errorColor: dark ? "#f48771" : "#c42b1c"
    readonly property color hoverColor: dark ? "#26ffffff" : "#1a000000"
    readonly property color checkedColor: Qt.rgba(accent.r, accent.g, accent.b, 0.25)
    // Room left beside the chevron, the count and three buttons.
    readonly property real fieldWidth: width - (25 + 4 + 72 + 3 * 22 + 4 * 2) * zoom

    // Opens the bar (with the replace field for Replace) and puts the
    // selected text, or else the word under the cursor, in the find field.
    function open(withReplace) {
        if (!active)
            replaceShown = false;
        if (withReplace)
            replaceShown = true;
        const t = editor.text;
        let seed = null;
        if (vim.mode === "visual" || vim.mode === "visualLine") {
            const s = editor.selectionStart, e = editor.selectionEnd;
            if (e > s && t.slice(s, e).indexOf("\n") < 0)
                seed = { start: s, text: t.slice(s, e) };
        } else if (vim.mode !== "visualBlock" && vim.charClass(t[vim.cursor], false) === 2) {
            seed = vim.wordAt(t, vim.cursor);
        }
        active = true;
        searchStart = seed ? seed.start : vim.cursor;
        const field = withReplace ? replaceField : findField;
        field.input.forceActiveFocus();
        field.selectAll();
        const seeded = seed ? (useRegex ? escaped(seed.text) : seed.text) : query;
        if (seeded !== query)
            query = seeded; // which searches, see onQueryChanged
        else
            search();
        if (!withReplace)
            findField.selectAll();
    }

    function close() {
        active = false;
        editor.forceActiveFocus();
    }

    // Find Next / Find Previous: from the menu, which also opens the bar.
    function findNext(step) {
        if (query === "") {
            open(false);
            return;
        }
        active = true;
        step > 0 ? next() : previous();
    }

    function escaped(s) {
        return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    // The query as a regular expression, or null (with `error` set if the
    // query is an invalid regular expression).
    function regExp() {
        error = "";
        if (query === "")
            return null;
        const source = useRegex ? query : escaped(query);
        const flags = "gm" + (matchCase ? "" : "i");
        try {
            return new RegExp(source, flags + "u");
        } catch (e) {
            // e.g. "\-", which is fine without the u flag
        }
        try {
            return new RegExp(source, flags);
        } catch (e) {
            error = e.message;
            return null;
        }
    }

    // Separators end a word, as in VS Code; everything else is part of one.
    function isSeparator(ch) {
        return ch === undefined || /[\s`~!@#$%^&*()\-=+[{\]}\\|;:'",.<>/?]/.test(ch);
    }

    function isWholeWord(t, s, e) {
        return (s === 0 || isSeparator(t[s - 1]) || e > s && isSeparator(t[s]))
            && (e === t.length || isSeparator(t[e]) || e > s && isSeparator(t[e - 1]));
    }

    // The matches in t, as the regular expression's results.
    function scan(t) {
        const re = regExp();
        const found = [];
        if (!re)
            return found;
        let m;
        while (found.length < maxMatches && (m = re.exec(t)) !== null) {
            const e = m.index + m[0].length;
            if (m[0] === "") // step over a whole code point
                re.lastIndex = m.index + (vim.isLowSurrogate(t, m.index + 1) ? 2 : 1);
            if (!wholeWord || isWholeWord(t, m.index, e))
                found.push(m);
        }
        return found;
    }

    // Finds the matches again, e.g. after an edit.
    function refresh() {
        if (!active)
            return;
        matches = scan(editor.text).map(m => ({ start: m.index, end: m.index + m[0].length }));
        current = currentStart < 0 ? -1 : matches.findIndex(m => m.start === currentStart);
    }

    // After the query or an option changed: moves to the first match from
    // where the search started.
    function search() {
        refresh();
        if (!matches.length)
            return;
        const i = matches.findIndex(m => m.start >= searchStart);
        moveTo(i < 0 ? 0 : i);
    }

    function moveTo(i) {
        const start = matches[i].start;
        moving = true;
        vim.jumpTo(start);
        moving = false;
        currentStart = start;
        current = i;
    }

    function next() {
        refresh();
        const n = matches.length;
        if (!n)
            return;
        let i = current >= 0 ? (current + 1) % n : matches.findIndex(m => m.start >= vim.cursor);
        moveTo(i < 0 ? 0 : i);
        searchStart = matches[current].start;
    }

    function previous() {
        refresh();
        const n = matches.length;
        if (!n)
            return;
        let i = current;
        if (i < 0) {
            i = matches.length;
            while (i > 0 && matches[i - 1].start >= vim.cursor)
                i--;
        }
        moveTo((i - 1 + n) % n);
        searchStart = matches[current].start;
    }

    // The replacement for match m: with a regular expression, $1 or $<name>
    // for a group, $& or $0 for the match, $$ for $, \n and \t, and \u, \l,
    // \U and \L to change the case of the group that follows.
    function replacementFor(m) {
        const r = replacement;
        if (!useRegex)
            return r;
        let out = "", one = "", all = "";
        const group = v => {
            v = v === undefined ? "" : v;
            if (all)
                v = all === "U" ? v.toUpperCase() : v.toLowerCase();
            if (one && v)
                v = (one === "u" ? v[0].toUpperCase() : v[0].toLowerCase()) + v.slice(1);
            one = all = "";
            return v;
        };
        for (let i = 0; i < r.length; i++) {
            const c = r[i], d = r[i + 1];
            if (c === "\\" && d !== undefined) {
                const plain = { "n": "\n", "t": "\t", "\\": "\\" }[d];
                if (plain !== undefined) {
                    out += plain;
                    i++;
                    continue;
                }
                if ("uUlL".includes(d)) {
                    if (d === "u" || d === "l")
                        one = d;
                    else
                        all = d;
                    i++;
                    continue;
                }
            } else if (c === "$" && d !== undefined) {
                if (d === "$") {
                    out += "$";
                    i++;
                    continue;
                }
                if (d === "&") {
                    out += group(m[0]);
                    i++;
                    continue;
                }
                if (d >= "0" && d <= "9") {
                    let k = d, j = i + 2;
                    const d2 = r[j];
                    if (d2 >= "0" && d2 <= "9" && parseInt(d + d2, 10) < m.length) {
                        k += d2;
                        j++;
                    }
                    if (parseInt(k, 10) < m.length) {
                        out += group(m[parseInt(k, 10)]);
                        i = j - 1;
                        continue;
                    }
                }
                if (d === "<" && m.groups) {
                    const e = r.indexOf(">", i);
                    const name = e > 0 ? r.slice(i + 2, e) : "";
                    if (e > 0 && name in m.groups) {
                        out += group(m.groups[name]);
                        i = e;
                        continue;
                    }
                }
            }
            out += c;
        }
        return out;
    }

    // Replaces the match at the cursor and moves to the next one. When the
    // cursor isn't at a match, only moves to the next one, as in VS Code.
    function replaceOne() {
        refresh();
        if (current < 0) {
            next();
            return;
        }
        const t = editor.text, start = matches[current].start;
        const m = scan(t).find(m => m.index === start);
        if (!m) {
            next();
            return;
        }
        const text = replacementFor(m), end = start + m[0].length;
        moving = true;
        vim.jumpTo(start);
        vim.externalEdit(() => vim.replaceRange(start, end, text));
        moving = false;
        currentStart = -1;
        refresh();
        // The next match after the replacement (after an empty match that
        // stayed empty, after where it was).
        const after = start + text.length + (text === "" && end === start ? 1 : 0);
        if (matches.length) {
            const i = matches.findIndex(m => m.start >= after);
            moveTo(i < 0 ? 0 : i);
        } else {
            vim.jumpTo(start);
        }
        searchStart = vim.cursor;
    }

    // Replaces every match, as one edit and one undo step. Hidden text
    // between the matches stays hidden.
    function replaceAll() {
        const t = editor.text, found = scan(t);
        if (!found.length)
            return;
        const first = found[0].index;
        let text = "", entries = [], i = first;
        for (const m of found) {
            const hidden = vim.hiddenIn(vim.hidden, i, m.index).filter(h => h.at + vim.poop.length <= m.index - i);
            entries = entries.concat(vim.shifted(hidden, text.length));
            text += t.slice(i, m.index) + replacementFor(m);
            i = m.index + m[0].length;
        }
        const cursor = Math.min(vim.cursor, first);
        moving = true;
        vim.jumpTo(cursor);
        vim.externalEdit(() => vim.replaceRange(first, i, text, entries));
        vim.jumpTo(cursor);
        moving = false;
        currentStart = -1;
        searchStart = vim.cursor;
        refresh();
        vim.showMessage(found.length === 1 ? "Replaced 1 occurrence" : "Replaced " + found.length + " occurrences");
    }

    // The matches in the visible lines, for the view to highlight.
    function highlightSpans() {
        if (!active || !matches.length)
            return [];
        const t = editor.text, v = vim.visibleRange(t);
        let lo = 0, hi = matches.length;
        while (lo < hi) { // the first match that ends in view
            const mid = (lo + hi) >> 1;
            if (matches[mid].end < v.from)
                lo = mid + 1;
            else
                hi = mid;
        }
        const spans = [];
        for (let i = lo; i < matches.length && matches[i].start <= v.to && spans.length < 5000; i++)
            vim.addHighlight(t, spans, matches[i].start, matches[i].end, i === current);
        return spans;
    }

    onQueryChanged: search()
    onMatchCaseChanged: search()
    onWholeWordChanged: search()
    onUseRegexChanged: search()
    onActiveChanged: {
        if (active) {
            refresh();
        } else {
            matches = [];
            current = -1;
            error = "";
        }
    }

    width: Math.max(300 * zoom, Math.min(440 * zoom, parent ? parent.width - 40 : 440 * zoom))
    height: frame.height
    y: active ? 0 : -height - 12
    visible: y > -height - 12
    Behavior on y {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: bar.editor

        function onRevisionChanged() {
            Qt.callLater(bar.refresh);
        }
    }
    Connections {
        target: bar.vim

        // The cursor moved some other way (e.g. an undo put it back on a
        // replaced match): the match there, if any, is now the current one,
        // and typing a query looks for matches from there. After an edit,
        // refresh finds the match again in the new text.
        function onCursorChanged() {
            if (bar.moving)
                return;
            const p = bar.vim.cursor;
            bar.currentStart = p;
            bar.current = bar.matches.findIndex(m => m.start === p);
            bar.searchStart = p;
        }
        function onHighlightsCleared() {
            if (bar.active)
                bar.close();
        }
    }

    Shortcut {
        id: caseShortcut

        enabled: bar.active
        sequence: bar.isMac ? "Ctrl+Alt+C" : "Alt+C"
        onActivated: bar.matchCase = !bar.matchCase
    }
    Shortcut {
        id: wordShortcut

        enabled: bar.active
        sequence: bar.isMac ? "Ctrl+Alt+W" : "Alt+W"
        onActivated: bar.wholeWord = !bar.wholeWord
    }
    Shortcut {
        id: regexShortcut

        enabled: bar.active
        sequence: bar.isMac ? "Ctrl+Alt+R" : "Alt+R"
        onActivated: bar.useRegex = !bar.useRegex
    }

    // Enter in a field: Shift+Enter finds the previous match, Cmd+Enter
    // (in the replace field) or Cmd+Alt+Enter replaces all, as in VS Code.
    function enterPressed(inReplace, modifiers) {
        const ctrl = modifiers & Qt.ControlModifier, alt = modifiers & Qt.AltModifier;
        if (replaceShown && ctrl && (alt || inReplace && isMac))
            replaceAll();
        else if (inReplace)
            replaceOne();
        else if (modifiers & Qt.ShiftModifier)
            previous();
        else
            next();
    }

    component IconButton: AbstractButton {
        id: button

        property string iconPath // an SVG path in a 16×16 box
        property string label // text, instead of an icon
        property bool underline
        property real iconRotation
        property string tip

        implicitWidth: 22 * bar.zoom
        implicitHeight: 22 * bar.zoom
        padding: 0
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        opacity: enabled ? 1 : 0.4
        Accessible.name: tip || label

        // Styled like the hidden-text hover box, and below the button, since
        // the bar sits at the top of the window.
        ToolTip {
            id: tooltip

            visible: button.hovered && button.tip !== ""
            delay: 600
            text: button.tip
            x: Math.round((button.width - width) / 2)
            y: button.height + 6 * bar.zoom
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
                leftPadding: 8 * bar.zoom
                rightPadding: 8 * bar.zoom
                topPadding: 4 * bar.zoom
                bottomPadding: 4 * bar.zoom
                text: tooltip.text
                font.pixelSize: Math.round(12 * bar.zoom)
                color: bar.textColor
                textFormat: Text.PlainText
            }
            background: Rectangle {
                radius: 4 * bar.zoom
                color: Qt.tint(bar.editor.palette.base, bar.dark ? "#12ffffff" : "#08000000")
                border.color: Qt.tint(bar.editor.palette.base, bar.dark ? "#40ffffff" : "#30000000")
                layer.enabled: tooltip.visible
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowBlur: 0.6
                    shadowVerticalOffset: 2
                    shadowColor: bar.dark ? "#a0000000" : "#40000000"
                }
            }
        }

        background: Rectangle {
            radius: 3 * bar.zoom
            color: button.checked ? bar.checkedColor : button.hovered || button.pressed ? bar.hoverColor : "transparent"
            border.color: button.checked ? bar.accent : "transparent"
        }
        contentItem: Item {
            Shape {
                anchors.centerIn: parent
                width: 16
                height: 16
                visible: button.iconPath !== ""
                rotation: button.iconRotation
                scale: bar.zoom // a vector shape, so it stays sharp
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: bar.textColor
                    strokeWidth: 1.3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg {
                        path: button.iconPath
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: button.label !== ""
                text: button.label
                font.pixelSize: Math.round(12 * bar.zoom)
                font.underline: button.underline
                color: bar.textColor
            }
        }
    }

    component Field: Rectangle {
        id: field

        property alias input: textInput
        property alias text: textInput.text
        property string placeholder
        property bool invalid
        default property alias tools: toolRow.data

        signal enterPressed(int modifiers)
        signal tabPressed(bool backward)

        function selectAll() {
            textInput.selectAll();
        }

        implicitHeight: 26 * bar.zoom
        radius: 2 * bar.zoom
        color: bar.dark ? Qt.tint(bar.editor.palette.base, "#1effffff") : bar.editor.palette.base
        border.color: invalid ? bar.errorColor : textInput.activeFocus ? bar.accent
            : bar.dark ? "transparent" : "#cecece"

        TextInput {
            id: textInput

            anchors.left: parent.left
            anchors.right: toolRow.left
            anchors.leftMargin: 6 * bar.zoom
            anchors.rightMargin: 4 * bar.zoom
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: bar.textColor
            font.pixelSize: Math.round(13 * bar.zoom)
            selectByMouse: true
            selectionColor: bar.editor.palette.highlight
            selectedTextColor: bar.editor.palette.highlightedText
            Keys.onPressed: event => {
                // Undo and redo the document (a replace, say), not the field.
                if (event.matches(StandardKey.Undo) || event.matches(StandardKey.Redo))
                    bar.vim.nativeUndo(event.matches(StandardKey.Redo));
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    field.enterPressed(event.modifiers);
                else if (event.key === Qt.Key_Escape)
                    bar.close();
                else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                    field.tabPressed(event.key === Qt.Key_Backtab);
                else
                    return;
                event.accepted = true;
            }

            Text {
                anchors.fill: parent
                visible: textInput.text === ""
                text: field.placeholder
                font: textInput.font
                color: bar.editor.palette.placeholderText
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
        Row {
            id: toolRow

            anchors.right: parent.right
            anchors.rightMargin: 2 * bar.zoom
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * bar.zoom
        }
    }

    Rectangle {
        id: frame

        width: bar.width
        height: rows.height + 10 * bar.zoom
        bottomLeftRadius: 4 * bar.zoom
        bottomRightRadius: 4 * bar.zoom
        color: bar.dark ? Qt.tint(bar.editor.palette.base, "#12ffffff") : Qt.tint(bar.editor.palette.base, "#0b000000")
        border.color: bar.dark ? Qt.tint(bar.editor.palette.base, "#30ffffff") : Qt.tint(bar.editor.palette.base, "#26000000")
        layer.enabled: bar.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.6
            shadowVerticalOffset: 2
            shadowColor: bar.dark ? "#a0000000" : "#40000000"
        }

        // Clicks on the frame don't reach the editor under it.
        MouseArea {
            anchors.fill: parent
        }

        IconButton {
            id: chevron

            x: 3 * bar.zoom
            y: 5 * bar.zoom
            width: 18 * bar.zoom
            height: rows.height
            iconPath: "M6 4 L10 8 L6 12"
            iconRotation: bar.replaceShown ? 90 : 0
            tip: qsTr("Toggle Replace")
            onClicked: {
                bar.replaceShown = !bar.replaceShown;
                (bar.replaceShown ? replaceField : findField).input.forceActiveFocus();
            }
        }

        ColumnLayout {
            id: rows

            x: chevron.x + chevron.width + 4 * bar.zoom
            y: 5 * bar.zoom
            width: bar.width - x - 4 * bar.zoom
            spacing: 4 * bar.zoom

            RowLayout {
                spacing: 2 * bar.zoom

                Field {
                    id: findField

                    Layout.preferredWidth: bar.fieldWidth
                    placeholder: qsTr("Find")
                    invalid: bar.error !== ""
                    onEnterPressed: modifiers => bar.enterPressed(false, modifiers)
                    onTabPressed: backward => {
                        if (bar.replaceShown && !backward)
                            replaceField.input.forceActiveFocus();
                    }

                    IconButton {
                        label: "Aa"
                        checkable: true
                        checked: bar.matchCase
                        tip: qsTr("Match Case") + " (" + caseShortcut.nativeText + ")"
                        onToggled: bar.matchCase = checked
                    }
                    IconButton {
                        label: "ab"
                        underline: true
                        checkable: true
                        checked: bar.wholeWord
                        tip: qsTr("Match Whole Word") + " (" + wordShortcut.nativeText + ")"
                        onToggled: bar.wholeWord = checked
                    }
                    IconButton {
                        label: ".*"
                        checkable: true
                        checked: bar.useRegex
                        tip: qsTr("Use Regular Expression") + " (" + regexShortcut.nativeText + ")"
                        onToggled: bar.useRegex = checked
                    }
                }
                Label {
                    id: countLabel

                    Layout.preferredWidth: 72 * bar.zoom
                    leftPadding: 4 * bar.zoom
                    font.pixelSize: Math.round(12 * bar.zoom)
                    elide: Text.ElideRight
                    color: bar.query !== "" && !bar.matches.length ? bar.errorColor : bar.textColor
                    text: {
                        const n = bar.matches.length;
                        if (!n)
                            return qsTr("No results");
                        const total = n >= bar.maxMatches ? n + "+" : n;
                        return qsTr("%1 of %2").arg(bar.current >= 0 ? bar.current + 1 : "?").arg(total);
                    }
                }
                IconButton {
                    iconPath: "M8 13 V3 M4 7 L8 3 L12 7"
                    enabled: bar.matches.length > 0
                    tip: qsTr("Previous Match") + (bar.isMac ? " (⇧Enter)" : " (Shift+Enter)")
                    onClicked: bar.previous()
                }
                IconButton {
                    iconPath: "M8 3 V13 M4 9 L8 13 L12 9"
                    enabled: bar.matches.length > 0
                    tip: qsTr("Next Match") + " (Enter)"
                    onClicked: bar.next()
                }
                IconButton {
                    iconPath: "M4.5 4.5 L11.5 11.5 M11.5 4.5 L4.5 11.5"
                    tip: qsTr("Close") + " (Escape)"
                    onClicked: bar.close()
                }
            }

            RowLayout {
                visible: bar.replaceShown
                spacing: 2 * bar.zoom

                Field {
                    id: replaceField

                    Layout.preferredWidth: bar.fieldWidth
                    placeholder: qsTr("Replace")
                    onEnterPressed: modifiers => bar.enterPressed(true, modifiers)
                    onTabPressed: backward => {
                        if (backward)
                            findField.input.forceActiveFocus();
                    }
                }
                IconButton {
                    iconPath: "M2.5 4.5 H9 Q12 4.5 12 7.5 V12.5 M9.5 10 L12 12.5 L14.5 10"
                    enabled: bar.matches.length > 0
                    tip: qsTr("Replace") + " (Enter)"
                    onClicked: bar.replaceOne()
                }
                IconButton {
                    iconPath: "M2.5 4.5 H9 Q12 4.5 12 7.5 V12.5 M9.5 10 L12 12.5 L14.5 10 M2.5 8.5 H8 M2.5 12.5 H8"
                    enabled: bar.matches.length > 0
                    tip: qsTr("Replace All") + (bar.isMac ? " (⌘Enter)" : " (Ctrl+Alt+Enter)")
                    onClicked: bar.replaceAll()
                }
            }
        }
    }

    // Why the query isn't a valid regular expression, under the find field.
    Rectangle {
        x: rows.x
        y: frame.height - 3 * bar.zoom
        width: Math.min(errorText.implicitWidth + 12 * bar.zoom, bar.width - x - 4 * bar.zoom)
        height: errorText.implicitHeight + 8 * bar.zoom
        visible: bar.error !== ""
        color: frame.color
        border.color: bar.errorColor

        Text {
            id: errorText

            x: 6 * bar.zoom
            y: 4 * bar.zoom
            width: parent.width - 12 * bar.zoom
            text: bar.error
            font.pixelSize: Math.round(12 * bar.zoom)
            color: bar.textColor
            wrapMode: Text.Wrap
        }
    }
}
