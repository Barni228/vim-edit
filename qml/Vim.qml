import QtQuick

// Vim emulation for a TextEdit. The editor keeps the text; this object keeps
// the mode, the cursor (a character index: in normal and visual mode the
// cursor sits *on* the character at `cursor`), registers and undo history.
// Every normal-mode edit goes through editor.insert/remove so the view keeps
// its scroll position.
QtObject {
    id: vim

    required property Item editor
    property Flickable flickable: null
    // Object with clipboardText(), clipboardData() and setClipboardText(text,
    // data): backs the "+ and "* registers. No other register touches the
    // system clipboard. data is for VimEdit only (the hidden texts).
    property var clipboard: null
    property real lineHeight: 16
    readonly property int pageLines: flickable ? Math.max(2, Math.floor(flickable.height / lineHeight)) : 20

    // "normal", "insert", "replace", "visual", "visualLine" or "visualBlock"
    property string mode: "normal"
    property int cursor: 0
    property int anchor: 0
    property string pendingKeys: ""
    property bool awaitingReplaceChar: false
    property string commandLine: ""
    // Index in commandLine that the command-line cursor sits on (1 or more;
    // index 0 holds the ":", "/" or "?").
    property int commandCursor: 1
    property string message: ""
    property bool messageIsError: false
    // :set number and :set relativenumber (the view draws the line numbers).
    property bool number: false
    property bool relativeNumber: false

    readonly property bool isVisual: mode === "visual" || mode === "visualLine" || mode === "visualBlock"
    readonly property string cursorShape: mode === "insert" ? "bar"
        : mode === "replace" || awaitingReplaceChar ? "underline" : "block"
    readonly property string modeLabel: [({
            insert: "-- INSERT --",
            replace: "-- REPLACE --",
            visual: "-- VISUAL --",
            visualLine: "-- VISUAL LINE --",
            visualBlock: "-- VISUAL BLOCK --"
        })[mode] || "", cursors.length ? "MULTI CURSOR" : "", recording ? "recording @" + recording : ""]
        .filter(s => s).join(" ")

    signal writeRequested(bool quit)
    signal quitRequested(bool force)
    // gh on a hidden-text 💩: show its text at the 💩 at `at`.
    signal hoverRequested(int at)
    // Esc in normal mode, or :noh: search highlights should go.
    signal highlightsCleared()

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property var operators: ["d", "c", "y", ">", "<", "g~", "gu", "gU", "g?"]
    readonly property var motions: ["h", "j", "k", "l", "<Left>", "<Right>", "<Up>", "<Down>", "<BS>", " ",
        "w", "W", "b", "B", "e", "E", "ge", "gE", "0", "^", "$", "<Home>", "<End>", "gg", "G",
        ";", ",", "%", "{", "}", "+", "-", "_", "<CR>", "|", "n", "N", "*", "#", "H", "M", "L",
        "<C-d>", "<C-u>", "<C-f>", "<C-b>", "<PageDown>", "<PageUp>"]
    readonly property var normalActions: ["i", "a", "I", "A", "gI", "o", "O", "v", "V", "x", "<Del>", "X",
        "s", "S", "C", "D", "Y", "p", "P", "J", "gJ", "u", "<C-r>", ".", "~", "r", "R", ":", "/", "?",
        "ZZ", "ZQ", "zz", "zt", "zb", "<C-e>", "<C-y>", "gv", "gh", "<C-a>", "<C-x>", "q", "@", "<C-v>", "<Esc>"]
    readonly property var visualActions: ["<Esc>", "v", "V", "<C-v>", "o", "O", "x", "<Del>", "X", "D", "s",
        "C", "S", "R", "Y", "~", "u", "U", "r", "J", "gJ", "p", "P", ":", "/", "?", "q", "I", "A", "<C-e>", "<C-y>"]
    // Normal-mode commands that run at every cursor (as do operators and
    // motions). "." does too, through the command it repeats.
    readonly property var everyCursorActions: ["i", "a", "I", "A", "gI", "o", "O", "x", "<Del>", "X", "s",
        "S", "C", "D", "Y", "p", "P", "J", "gJ", "~", "r", "R", "<C-a>", "<C-x>"]
    readonly property var visualModes: ({ "v": "visual", "V": "visualLine", "<C-v>": "visualBlock" })
    // Normal-mode commands that modify the text (and so can be repeated with ".").
    readonly property var changeActions: ["i", "a", "I", "A", "gI", "o", "O", "x", "<Del>", "X", "s", "S",
        "C", "D", "p", "P", "J", "gJ", "~", "r", "R", "<C-a>", "<C-x>"]
    readonly property var textObjects: ["w", "W", "p", "\"", "'", "`", "(", ")", "b", "[", "]", "{", "}",
        "B", "<", ">"]

    property var keys: []
    property var registers: ({})
    property var undoStack: []
    property var redoStack: []
    property var change: null
    property var wantCol: 0
    property var lastFind: null
    property var lastSearch: null
    property var lastVisual: null
    property var dot: null
    property var insertSession: null
    // Extra cursors (Alt+click, or one per line of a block insert), sorted:
    // { pos, col, registers, replaceStack }, where col is its wantCol,
    // registers its own (see atEveryCursor) and replaceStack what it
    // replaced in replace mode. Commands work at all of them, and leaving
    // insert or replace mode removes them. Edits move them (see
    // replaceRange). Replaced, never changed in place, so the view sees
    // every change.
    property var cursors: []
    // While editAll runs: every cursor, the main one too, for edits to move.
    property var shifting: null
    // During a block insert: where it started ({ line, offset, moved }), to go
    // back to after it unless the cursors moved.
    property var blockHome: null
    property var replaceStack: []
    property bool syncing: false
    property bool replaying: false
    // Macros: the register being recorded into ("" when not recording) and
    // the keys typed so far. Running a macro puts its keys in `typeahead`,
    // which runs them one by one; a failing command empties it, as in vim.
    property string recording: ""
    property var recordKeys: []
    property var typeahead: []
    property bool draining: false
    property string lastMacro: ""
    readonly property int maxMacroKeys: 100000
    // Command-line history: ":" commands, and "/" and "?" searches together.
    property var history: ({ ":": [], "/": [] })
    property int historyIndex: -1 // -1 while not browsing
    property string historyTyped: ""
    // While a search is typed: where Enter would jump (-1 if nowhere), and
    // the view to go back to if the search is cancelled.
    property int searchTarget: -1
    property var searchView: null
    // The last search stays highlighted until Esc in normal mode (or :noh).
    property string highlightPattern: ""
    // Start of the match to show as current: the one a typed search would
    // jump to, otherwise the one under the cursor.
    readonly property int highlightTarget: commandLine[0] === "/" || commandLine[0] === "?" ? searchTarget : cursor

    onCommandLineChanged: previewSearch()

    // ---- Entry points ------------------------------------------------------

    function reset() {
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        commandLine = "";
        message = "";
        undoStack = [];
        redoStack = [];
        change = null;
        hidden = [];
        insertSession = null;
        cursors = [];
        blockHome = null;
        setMode("normal");
        setCursor(0);
    }

    // Returns whether the key was consumed; unconsumed keys go to the editor.
    function handleKey(event) {
        if (commandLine !== "")
            return typedKey(tokenFor(event), event);
        if (!isVisual && mode !== "insert")
            message = "";
        // Ctrl+Y is also Redo on Windows and Linux, and Paste (yank) on
        // macOS, except outside insert mode, where it scrolls as in vim.
        const scrollKey = mode !== "insert" && tokenFor(event) === "<C-y>";
        if ((event.matches(StandardKey.Undo) || event.matches(StandardKey.Redo)) && !scrollKey) {
            nativeUndo(event.matches(StandardKey.Redo));
            return true;
        }
        if (mode === "insert") {
            // Also through the "+ register, so hidden text is revealed for
            // other apps and stays hidden when pasted here.
            const s = editor.selectionStart, e = editor.selectionEnd;
            if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)) {
                if (e > s) {
                    setRegister("+", editor.text.slice(s, e), false, true, hiddenIn(hidden, s, e));
                    if (event.matches(StandardKey.Cut)) {
                        replaceRange(s, e, "");
                        setCursor(s);
                    }
                }
                return true;
            }
            // Ctrl+V pastes too, also on macOS (where Paste is Cmd+V).
            if (event.matches(StandardKey.Paste) || tokenFor(event) === "<C-v>") {
                const r = getRegister("+");
                if (r && cursors.length) {
                    setCursor(editAll(p => {
                        replaceRange(p, p, r.text, r.hidden);
                        return p + r.text.length;
                    }));
                } else if (r) {
                    replaceRange(s, e, r.text, r.hidden);
                    setCursor(s + r.text.length);
                }
                return true;
            }
        } else {
            // On Windows and Linux, Ctrl+A and Ctrl+X are Select All and Cut,
            // except in normal mode, where they add to a number as in vim.
            // Ctrl+V (Paste there) starts visual block mode.
            const addKey = mode === "normal" && ["<C-a>", "<C-x>"].includes(tokenFor(event));
            const blockKey = tokenFor(event) === "<C-v>";
            if (event.matches(StandardKey.Copy)) {
                if (isVisual)
                    execute({ reg: "+", count: 0, action: "y" });
                return true;
            }
            if (event.matches(StandardKey.Cut) && !addKey) {
                if (isVisual)
                    execute({ reg: "+", count: 0, action: "d" });
                return true;
            }
            if (event.matches(StandardKey.Paste) && !blockKey && !scrollKey) {
                if (mode !== "replace")
                    execute({ reg: "+", count: 0, action: "P" });
                return true;
            }
            if (event.matches(StandardKey.SelectAll) && !addKey) {
                if (mode !== "replace") {
                    setMode("visualLine");
                    anchor = 0;
                    setCursor(editor.length);
                }
                return true;
            }
        }
        return typedKey(tokenFor(event), event);
    }

    // A key the user typed, which a macro being recorded keeps.
    function typedKey(tok, event) {
        if (recording && tok !== null)
            recordKeys.push(tok);
        return runKey(tok, event);
    }

    // Runs a typed key, or one from a macro (with no event).
    function runKey(tok, event) {
        if (commandLine !== "")
            return commandLineKey(tok);
        if (mode === "insert")
            return insertKey(tok, event);
        if (tok === null)
            return true;
        if (mode === "replace") {
            if (tok === "<Esc>") {
                leaveInsert();
            } else if (!isSpecial(tok) || ["<CR>", "<Tab>", "<BS>"].includes(tok)) {
                if (insertSession && !insertSession.broken)
                    insertSession.keys.push(tok);
                replaceKey(tok);
            }
            return true;
        }
        feed(tok);
        return true;
    }

    // Called when the editor's cursor or selection changes, e.g. by the mouse.
    function syncFromEditor() {
        if (syncing)
            return;
        const p = editor.cursorPosition;
        if (mode === "insert" || mode === "replace") {
            cursor = p;
            return;
        }
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        const t = editor.text;
        const s = editor.selectionStart, e = editor.selectionEnd;
        if (s !== e) {
            mode = "visual";
            if (p === e) {
                anchor = s;
                cursor = charStart(t, e - 1);
            } else {
                anchor = charStart(t, e - 1);
                cursor = s;
            }
            return;
        }
        if (isVisual)
            mode = "normal";
        const c = clampNormal(t, p);
        wantCol = column(t, c);
        if (c !== p)
            setCursor(c);
        else
            cursor = c;
    }

    // Runs an edit made outside vim (e.g. from a menu) as its own undo step.
    function externalEdit(fn) {
        commitChange();
        beginChange();
        fn();
        commitChange();
        if (mode === "insert" || mode === "replace")
            beginChange();
    }

    // Cmd+Z / Cmd+Shift+Z, in any mode (also from the find bar).
    function nativeUndo(isRedo) {
        if (commandLine !== "")
            commandLineKey("<Esc>");
        const insertish = mode === "insert" || mode === "replace";
        if (insertish)
            breakInsert();
        if (isVisual) {
            setMode("normal");
            setCursor(clampNormal(editor.text, cursor));
        }
        if (isRedo)
            redo(1);
        else
            undo(1);
        if (insertish)
            beginChange();
    }

    // Moves the cursor to p from outside vim (the find bar): back to one
    // cursor, out of visual mode, and a new undo step in insert mode.
    function jumpTo(p) {
        if (commandLine !== "")
            commandLineKey("<Esc>");
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        clearCursors();
        if (isVisual)
            setMode("normal");
        if (mode === "insert" || mode === "replace") {
            breakInsert();
            replaceStack = [];
        }
        const t = editor.text;
        p = mode === "normal" ? clampNormal(t, p) : Math.max(0, Math.min(p, t.length));
        setCursor(p);
        wantCol = column(t, p);
    }

    function positionLabel() {
        const t = editor.text;
        return lineOf(t, cursor) + ":" + (column(t, cursor) + 1);
    }

    function showError(text) {
        message = text;
        messageIsError = true;
        typeahead = [];
    }

    function showMessage(text) {
        message = text;
        messageIsError = false;
    }

    // ---- Keys --------------------------------------------------------------

    // Turns a key event into a vim key: a character, or a name like "<Esc>",
    // "<CR>" or "<C-r>". Returns null for keys vim doesn't handle.
    function tokenFor(event) {
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        if ((event.modifiers & ctrl) && !(event.modifiers & Qt.AltModifier)) {
            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
                return "<C-" + String.fromCharCode(event.key - Qt.Key_A + 97) + ">";
            if (event.key === Qt.Key_BracketLeft)
                return "<Esc>";
            return null;
        }
        if (isMac && (event.modifiers & Qt.ControlModifier)) // Cmd
            return null;
        const named = {
            [Qt.Key_Escape]: "<Esc>",
            [Qt.Key_Return]: "<CR>",
            [Qt.Key_Enter]: "<CR>",
            [Qt.Key_Backspace]: "<BS>",
            [Qt.Key_Delete]: "<Del>",
            [Qt.Key_Tab]: "<Tab>",
            [Qt.Key_Left]: "<Left>",
            [Qt.Key_Right]: "<Right>",
            [Qt.Key_Up]: "<Up>",
            [Qt.Key_Down]: "<Down>",
            [Qt.Key_Home]: "<Home>",
            [Qt.Key_End]: "<End>",
            [Qt.Key_PageUp]: "<PageUp>",
            [Qt.Key_PageDown]: "<PageDown>"
        }[event.key];
        if (named)
            return named;
        const text = event.text;
        if (text.length > 0 && text.charCodeAt(0) >= 32 && text !== "\x7f")
            return text;
        return null;
    }

    function isSpecial(tok) {
        return tok.length > 2 && tok[0] === "<" && tok[tok.length - 1] === ">";
    }

    function insertKey(tok, event) {
        if (tok === "<Esc>") {
            leaveInsert();
            return true;
        }
        if (tok === null)
            return false;
        const s = insertSession;
        const move = ["<Left>", "<Right>", "<Up>", "<Down>", "<Home>", "<End>", "<PageUp>", "<PageDown>"].includes(tok);
        const typed = !isSpecial(tok) || ["<CR>", "<Tab>", "<BS>", "<Del>"].includes(tok);
        if (move)
            breakInsert();
        else if (s && !s.broken && typed)
            s.keys.push(tok);
        // A macro has no event for the editor to handle, and the editor
        // knows only one cursor, so vim does it.
        if (!event || cursors.length && (move || typed)) {
            if (move)
                insertMove(tok);
            else if (typed)
                typeKey(tok);
            return true;
        }
        // The editor's backspace deletes one code point, which would leave
        // most of an emoji (or of a hidden-text 💩) behind.
        if (tok === "<BS>" && event.modifiers === Qt.NoModifier && editor.selectionStart === editor.selectionEnd) {
            typeKey(tok);
            return true;
        }
        return false;
    }

    // Moves the insert-mode cursors like the editor does for these keys.
    function insertMove(tok) {
        setCursor(editAll(p => insertMoved(editor.text, p, tok)));
    }

    function insertMoved(t, p, tok) {
        let q = p;
        if (tok === "<Left>") {
            q = p > 0 ? charStart(t, p - 1) : p;
        } else if (tok === "<Right>") {
            q = p < t.length ? charEnd(t, p) : p;
        } else if (tok === "<Home>") {
            q = lineStart(t, p);
        } else if (tok === "<End>") {
            q = lineEnd(t, p);
        } else {
            const lines = tok === "<Up>" ? -1 : tok === "<Down>" ? 1 : tok === "<PageUp>" ? -pageLines : pageLines;
            const col = column(t, p);
            const r = lineMotion(t, p, lines);
            if (r) {
                const ls = lineStart(t, r.pos);
                q = advance(t, ls, col, lineEnd(t, ls));
            }
        }
        return q;
    }

    function openCommandLine(kind) {
        commandCursor = 1;
        commandLine = kind;
    }

    // Replaces commandLine[from, to) with text and puts the cursor after it.
    function editCommandLine(from, to, text) {
        commandCursor = from + text.length;
        commandLine = commandLine.slice(0, from) + text + commandLine.slice(to);
    }

    function commandLineKey(tok) {
        if (tok === "<Up>" || tok === "<Down>") {
            browseHistory(tok === "<Up>" ? -1 : 1);
            return true;
        }
        const c = commandCursor, n = commandLine.length;
        if (["<Left>", "<Right>", "<Home>", "<End>", "<C-b>", "<C-e>"].includes(tok)) {
            commandCursor = tok === "<Left>" ? Math.max(1, c - 1)
                : tok === "<Right>" ? Math.min(n, c + 1)
                : tok === "<Home>" || tok === "<C-b>" ? 1 : n;
            return true;
        }
        historyIndex = -1;
        if (tok === "<Esc>" || tok === "<C-c>") {
            commandLine = "";
        } else if (tok === "<CR>") {
            const line = commandLine;
            if (searchTarget >= 0)
                searchView = null; // keep the view on the match
            commandLine = "";
            addToHistory(line);
            runCommandLine(line);
        } else if (tok === "<BS>") {
            if (n === 1)
                commandLine = ""; // backspace on an empty line leaves it
            else if (c > 1)
                editCommandLine(c - 1, c, "");
        } else if (tok === "<Del>") {
            if (c < n)
                editCommandLine(c, c + 1, "");
        } else if (tok === "<C-u>") {
            editCommandLine(1, c, "");
        } else if (tok === "<C-w>") {
            let s = c;
            while (s > 1 && isBlank(commandLine[s - 1]))
                s--;
            const cls = charClass(commandLine[s - 1], false);
            while (s > 1 && !isBlank(commandLine[s - 1]) && charClass(commandLine[s - 1], false) === cls)
                s--;
            editCommandLine(s, c, "");
        } else if (tok === "<Tab>") {
            editCommandLine(c, c, "\t");
        } else if (tok !== null && !isSpecial(tok)) {
            editCommandLine(c, c, tok);
        }
        return true;
    }

    function historyList(kind) {
        return history[kind === ":" ? ":" : "/"];
    }

    function addToHistory(line) {
        const body = line.slice(1);
        if (!body)
            return;
        const list = historyList(line[0]);
        const i = list.indexOf(body);
        if (i >= 0)
            list.splice(i, 1);
        list.push(body);
        if (list.length > 200)
            list.shift();
    }

    // Steps to the previous (-1) or next (1) entry that starts with what was
    // typed before browsing; stepping past the newest restores the typed text.
    function browseHistory(step) {
        const kind = commandLine[0];
        const list = historyList(kind);
        if (historyIndex < 0) {
            historyTyped = commandLine.slice(1);
            historyIndex = list.length;
        }
        let i = historyIndex + step;
        while (i >= 0 && i < list.length && !list[i].startsWith(historyTyped))
            i += step;
        if (i < 0)
            return;
        historyIndex = Math.min(i, list.length);
        const text = kind + (i >= list.length ? historyTyped : list[i]);
        commandCursor = text.length;
        commandLine = text;
    }

    function feed(tok) {
        if (recording && tok === "q" && keys.length === 0) {
            stopRecording();
            return;
        }
        keys.push(tok);
        const r = parse(keys, isVisual);
        if (r.status === "more") {
            pendingKeys = keys.join("");
            awaitingReplaceChar = tok === "r" && keys[keys.length - 2] !== "\"";
            return;
        }
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        if (r.status === "ok")
            execute(r.cmd);
        else
            typeahead = [];
    }

    // ---- Parsing -----------------------------------------------------------

    // Parses a key sequence into a command:
    //   ["x] [count] operator [count] (motion | text object | operator again)
    //   ["x] [count] (motion | action)
    // Returns { status: "more" | "bad" | "ok", cmd }.
    function parse(keys, visual) {
        const more = { status: "more" }, bad = { status: "bad" };
        const cmd = { reg: null, count: 0 };
        let i = 0;
        if (keys[0] === "\"") {
            if (keys.length < 2)
                return more;
            if (!/^[a-zA-Z0-9"+*_-]$/.test(keys[1]))
                return bad;
            cmd.reg = keys[1];
            i = 2;
        }
        const c1 = readCount(keys, i);
        cmd.count = c1.count;
        i = c1.next;
        const w = readName(keys, i);
        if (!w)
            return more;

        if (operators.includes(w.name)) {
            if (visual) {
                cmd.action = w.name;
                return { status: "ok", cmd };
            }
            cmd.op = w.name;
            const c2 = readCount(keys, w.next);
            if (c2.count)
                cmd.count = Math.max(cmd.count, 1) * c2.count;
            const j = c2.next;
            if (j >= keys.length)
                return more;
            const k = keys[j];
            const last = cmd.op[cmd.op.length - 1];
            if (k === last) {
                cmd.linewise = true;
                return { status: "ok", cmd };
            }
            if (cmd.op.length === 2 && k === "g") {
                if (j + 1 >= keys.length)
                    return more;
                if (keys[j + 1] === last) {
                    cmd.linewise = true;
                    return { status: "ok", cmd };
                }
            }
            if (k === "i" || k === "a") {
                if (j + 1 >= keys.length)
                    return more;
                if (!textObjects.includes(keys[j + 1]))
                    return bad;
                cmd.textObj = { around: k === "a", ch: keys[j + 1] };
                return { status: "ok", cmd };
            }
            const m = parseMotion(keys, j);
            if (m.status !== "ok")
                return m;
            cmd.motion = m.motion;
            return { status: "ok", cmd };
        }

        if (visual && (w.name === "i" || w.name === "a")) {
            if (w.next >= keys.length)
                return more;
            if (!textObjects.includes(keys[w.next]))
                return bad;
            cmd.textObj = { around: w.name === "a", ch: keys[w.next] };
            return { status: "ok", cmd };
        }

        const m = parseMotion(keys, i);
        if (m.status === "more")
            return more;
        if (m.status === "ok") {
            cmd.motion = m.motion;
            return { status: "ok", cmd };
        }
        if (!(visual ? visualActions : normalActions).includes(w.name))
            return bad;
        cmd.action = w.name;
        if (w.name === "r") {
            if (w.next >= keys.length)
                return more;
            const ch = charArg(keys[w.next], true);
            if (ch === null)
                return bad;
            cmd.ch = ch;
        } else if (w.name === "q" || w.name === "@") {
            // The register to record into, or to run. A plain "q" stops a
            // recording (see feed).
            if (w.name === "q" && recording)
                return bad;
            if (w.next >= keys.length)
                return more;
            if (!(w.name === "q" ? /^[0-9a-zA-Z"]$/ : /^[0-9a-zA-Z"+*:@-]$/).test(keys[w.next]))
                return bad;
            cmd.ch = keys[w.next];
        }
        return { status: "ok", cmd };
    }

    function parseMotion(keys, i) {
        const w = readName(keys, i);
        if (!w)
            return { status: "more" };
        if (["f", "F", "t", "T"].includes(w.name)) {
            if (w.next >= keys.length)
                return { status: "more" };
            const ch = charArg(keys[w.next], false);
            if (ch === null)
                return { status: "bad" };
            return { status: "ok", motion: { name: w.name, ch } };
        }
        if (motions.includes(w.name))
            return { status: "ok", motion: { name: w.name } };
        return { status: "bad" };
    }

    // A command name: one key, or two for the g, z and Z prefixes.
    function readName(keys, i) {
        if (i >= keys.length)
            return null;
        const k = keys[i];
        if (k === "g" || k === "z" || k === "Z") {
            if (i + 1 >= keys.length)
                return null;
            return { name: k + keys[i + 1], next: i + 2 };
        }
        return { name: k, next: i + 1 };
    }

    function readCount(keys, i) {
        let s = "";
        while (i < keys.length && /^[0-9]$/.test(keys[i]) && !(s === "" && keys[i] === "0"))
            s += keys[i++];
        return { count: s ? parseInt(s, 10) : 0, next: i };
    }

    function charArg(tok, allowNewline) {
        if (tok === "<Tab>")
            return "\t";
        if (tok === "<CR>")
            return allowNewline ? "\n" : null;
        return isSpecial(tok) ? null : tok;
    }

    // ---- Execution ---------------------------------------------------------

    function isChange(cmd) {
        if (isVisual)
            return !cmd.motion && !cmd.textObj
                && !["<Esc>", "v", "V", "<C-v>", "o", "O", ":", "/", "?", "y", "Y", "q"].includes(cmd.action);
        return cmd.op ? cmd.op !== "y" : changeActions.includes(cmd.action);
    }

    function execute(cmd) {
        const changing = isChange(cmd);
        if (changing) {
            beginChange();
            if (!isVisual && !replaying)
                dot = { cmd: Object.assign({}, cmd), insertKeys: [] };
        }
        if (isVisual)
            executeVisual(cmd);
        else if (cmd.op && cursors.length)
            atEveryCursor(() => executeOperator(cmd));
        else if (cmd.op)
            executeOperator(cmd);
        else if (cmd.motion)
            moveBy(cmd); // moves the extra cursors itself
        else if (cursors.length && everyCursorActions.includes(cmd.action))
            atEveryCursor(() => executeAction(cmd));
        else
            executeAction(cmd);
        if (changing && mode !== "insert" && mode !== "replace")
            commitChange();
    }

    function moveBy(cmd) {
        const t = editor.text;
        const count = Math.max(cmd.count, 1);
        const r = motion(t, cursor, cmd.motion, count, cmd.count > 0, false);
        if (r) {
            let p = r.pos;
            if (isVisual)
                p = r.eol ? Math.min(p, t.length) : clampNormal(t, p);
            else
                p = clampNormal(t, p);
            if (!r.keepCol)
                wantCol = r.eol ? Infinity : column(t, p);
            setCursor(p);
        } else {
            typeahead = [];
        }
        if (cursors.length && mode === "normal")
            moveCursors(t, cmd.motion, count, cmd.count > 0);
    }

    // Moves the extra cursors as the main one moved. Each keeps its own
    // column for j and k (`col`, like wantCol).
    function moveCursors(t, m, count, explicit) {
        // "*" and "#" search for the main cursor's word, which is now the
        // last search, from every cursor.
        if (m.name === "*" || m.name === "#")
            m = { name: "n" };
        const mainCol = wantCol;
        setCursors(cursors.map(c => {
            wantCol = c.col === undefined ? column(t, c.pos) : c.col;
            const r = motion(t, c.pos, m, count, explicit, false, true);
            if (!r)
                return Object.assign({}, c, { col: wantCol });
            const p = clampNormal(t, r.pos);
            return Object.assign({}, c, { pos: p, col: r.keepCol ? wantCol : r.eol ? Infinity : column(t, p) });
        }));
        wantCol = mainCol;
    }

    function executeOperator(cmd) {
        const t = editor.text;
        const n = t.length;
        const count = Math.max(cmd.count, 1);
        let range, target = cursor;
        if (cmd.linewise) {
            let le = lineEnd(t, cursor);
            for (let i = 1; i < count && le < n; i++)
                le = lineEnd(t, le + 1);
            range = { start: lineStart(t, cursor), end: Math.min(le + 1, n), linewise: true };
        } else if (cmd.textObj) {
            range = textObject(t, cursor, cmd.textObj, count);
            if (!range) {
                typeahead = [];
                return;
            }
            target = range.start;
        } else {
            let r;
            // "cw" on a word changes to the end of the word, like "ce", but
            // stays on the current word when the cursor is at its last letter.
            if (cmd.op === "c" && (cmd.motion.name === "w" || cmd.motion.name === "W")
                    && charClass(t[cursor], false) !== 0) {
                const big = cmd.motion.name === "W";
                let q = cursor;
                for (let i = 0; i < count; i++)
                    if (i > 0 || charClass(t[charEnd(t, q)], big) === charClass(t[q], big))
                        q = wordEnd(t, q, big);
                r = { pos: q, type: "inclusive" };
            } else {
                r = motion(t, cursor, cmd.motion, count, cmd.count > 0, true);
            }
            if (!r) {
                typeahead = [];
                return;
            }
            target = r.pos;
            const a = Math.min(cursor, r.pos), b = Math.max(cursor, r.pos);
            if (r.type === "linewise")
                range = { start: lineStart(t, a), end: Math.min(lineEnd(t, b) + 1, n), linewise: true };
            else
                range = { start: a, end: r.type === "inclusive" ? charEnd(t, b) : Math.min(b, n), linewise: false };
        }
        applyOperator(cmd.op, range, cmd.reg, count,
            range.linewise ? Math.min(cursor, target) : range.start);
    }

    function applyOperator(op, range, reg, count, yankCursor) {
        const t = editor.text;
        if (!range.linewise && range.end <= range.start && op !== "c")
            return;
        const lines = range.linewise ? spannedLines(t.slice(range.start, range.end)) : 0;
        switch (op) {
        case "y":
            yank(t, range, reg);
            if (lines > 2)
                showMessage(lines + " lines yanked");
            setCursor(clampNormal(t, yankCursor));
            break;
        case "d":
            deleteRange(t, range, reg);
            if (lines > 2)
                showMessage(lines + " fewer lines");
            break;
        case "c": {
            yank(t, range, reg);
            let e = range.end;
            if (range.linewise && e > range.start && t[e - 1] === "\n")
                e--; // keep an empty line to type on
            replaceRange(range.start, e, "");
            startInsert(1, range.start, null);
            break;
        }
        case ">":
        case "<":
            shiftLines(range, op === ">" ? 1 : -1, 1);
            break;
        default: // g~, gu, gU
            changeCase(range, op[1]);
            break;
        }
    }

    function executeAction(cmd) {
        const t = editor.text;
        const count = Math.max(cmd.count, 1);
        const p = cursor;
        switch (cmd.action) {
        case "i":
            startInsert(count, p, null);
            break;
        case "a":
            startInsert(count, p < lineEnd(t, p) ? charEnd(t, p) : p, null);
            break;
        case "I":
            startInsert(count, firstNonBlank(t, p), null);
            break;
        case "gI":
            startInsert(count, lineStart(t, p), null);
            break;
        case "A":
            startInsert(count, lineEnd(t, p), null);
            break;
        case "o": {
            const le = lineEnd(t, p);
            replaceRange(le, le, "\n");
            startInsert(count, le + 1, "o");
            break;
        }
        case "O": {
            const ls = lineStart(t, p);
            replaceRange(ls, ls, "\n");
            startInsert(count, ls, "O");
            break;
        }
        case "v":
        case "V":
        case "<C-v>":
            anchor = p;
            setMode(visualModes[cmd.action]);
            setCursor(p);
            break;
        case "x":
        case "<Del>":
            executeOperator({ op: "d", reg: cmd.reg, count: cmd.count, motion: { name: "l" } });
            break;
        case "X":
            executeOperator({ op: "d", reg: cmd.reg, count: cmd.count, motion: { name: "h" } });
            break;
        case "s":
            applyOperator("c", { start: p, end: advance(t, p, count, lineEnd(t, p)), linewise: false }, cmd.reg);
            break;
        case "S":
            executeOperator({ op: "c", reg: cmd.reg, count: cmd.count, linewise: true });
            break;
        case "C":
            executeOperator({ op: "c", reg: cmd.reg, count: cmd.count, motion: { name: "$" } });
            break;
        case "D":
            executeOperator({ op: "d", reg: cmd.reg, count: cmd.count, motion: { name: "$" } });
            break;
        case "Y":
            executeOperator({ op: "y", reg: cmd.reg, count: cmd.count, linewise: true });
            break;
        case "p":
        case "P":
            paste(cmd.reg, cmd.action === "p", count);
            break;
        case "J":
        case "gJ":
            joinLines(count, cmd.action === "J");
            break;
        case "u":
            undo(count);
            break;
        case "<C-r>":
            redo(count);
            break;
        case ".":
            repeatDot(cmd.count);
            break;
        case "~": {
            const e = advance(t, p, count, lineEnd(t, p));
            if (e > p) {
                const text = toggleCase(t.slice(p, e));
                replaceRange(p, e, text, carriedHidden(p, e, text));
                setCursor(clampNormal(editor.text, e));
            }
            break;
        }
        case "r": {
            const le = lineEnd(t, p);
            let e = p, k = 0;
            for (; k < count && e < le; k++)
                e = charEnd(t, e);
            if (k < count)
                break;
            if (cmd.ch === "\n") {
                replaceRange(p, e, "\n");
                setCursor(p + 1);
            } else {
                replaceRange(p, e, cmd.ch.repeat(count));
                setCursor(p + cmd.ch.length * (count - 1));
            }
            break;
        }
        case "R":
            setMode("replace");
            setCursor(p);
            replaceStack = [];
            insertSession = { count: count, keys: [], openLine: null, dot: replaying ? null : dot, broken: false };
            break;
        case ":":
        case "/":
        case "?":
            openCommandLine(cmd.action);
            break;
        case "ZZ":
            writeRequested(true);
            break;
        case "ZQ":
            quitRequested(true);
            break;
        case "zz":
        case "zt":
        case "zb":
            scrollToCursor(cmd.action[1]);
            break;
        case "<C-e>":
        case "<C-y>":
            scrollText(cmd.action === "<C-e>" ? count : -count);
            break;
        case "<Esc>":
            highlightPattern = "";
            cursors = [];
            highlightsCleared();
            break;
        case "gv":
            if (lastVisual) {
                anchor = Math.min(lastVisual.anchor, t.length);
                setMode(lastVisual.mode);
                setCursor(Math.min(lastVisual.cursor, t.length));
            }
            break;
        case "gh":
            if (hiddenAt(p))
                hoverRequested(p);
            break;
        case "<C-a>":
        case "<C-x>":
            addToNumber(cmd.action === "<C-a>" ? count : -count);
            break;
        case "q":
            startRecording(cmd.ch);
            break;
        case "@":
            runMacro(cmd.ch, count);
            break;
        }
    }

    function executeVisual(cmd) {
        const t = editor.text;
        const n = t.length;
        const count = Math.max(cmd.count, 1);
        if (cmd.motion) {
            moveBy(cmd);
            return;
        }
        if (cmd.textObj) {
            const r = textObject(t, cursor, cmd.textObj, count);
            if (r && r.end > r.start) {
                anchor = r.start;
                setCursor(charStart(t, r.end - 1));
            }
            return;
        }
        const a = cmd.action;
        lastVisual = { mode: mode, anchor: anchor, cursor: cursor };
        if (a === "<Esc>" || visualModes[a] === mode) {
            setMode("normal");
            setCursor(clampNormal(t, cursor));
            return;
        }
        if (visualModes[a]) {
            setMode(visualModes[a]);
            setCursor(cursor);
            return;
        }
        if (a === "O" && mode === "visualBlock") {
            // To the other corner on the same line.
            const ca = column(t, anchor), cc = column(t, cursor);
            const la = lineStart(t, anchor), lc = lineStart(t, cursor);
            anchor = advance(t, la, cc, lineEnd(t, la));
            setCursor(advance(t, lc, ca, lineEnd(t, lc)));
            return;
        }
        if (a === "o" || a === "O") {
            const c = cursor;
            cursor = anchor;
            anchor = c;
            setCursor(cursor);
            return;
        }
        if (a === ":" || a === "/" || a === "?") {
            openCommandLine(a);
            return;
        }
        if (a === "q") {
            startRecording(cmd.ch);
            return;
        }
        if (a === "<C-e>" || a === "<C-y>") {
            scrollText(a === "<C-e>" ? count : -count);
            return;
        }
        if (mode === "visualBlock" && executeBlock(cmd))
            return;

        const lo = Math.min(anchor, cursor), hi = Math.max(anchor, cursor);
        const lineRange = { start: lineStart(t, lo), end: Math.min(lineEnd(t, hi) + 1, n), linewise: true };
        const range = mode === "visualLine" ? lineRange : { start: lo, end: charEnd(t, hi), linewise: false };
        setMode("normal");
        setCursor(clampNormal(t, lo));
        switch (a) {
        case "d":
        case "x":
        case "<Del>":
            applyOperator("d", range, cmd.reg);
            break;
        case "X":
        case "D":
            applyOperator("d", lineRange, cmd.reg);
            break;
        case "c":
        case "s":
            applyOperator("c", range, cmd.reg);
            break;
        case "C":
        case "S":
        case "R":
            applyOperator("c", lineRange, cmd.reg);
            break;
        case "y":
            applyOperator("y", range, cmd.reg, 0, lo);
            break;
        case "Y":
            applyOperator("y", lineRange, cmd.reg, 0, lo);
            break;
        case ">":
        case "<":
            shiftLines(range, a === ">" ? 1 : -1, count);
            break;
        case "~":
        case "g~":
            changeCase(range, "~");
            break;
        case "u":
        case "gu":
            changeCase(range, "u");
            break;
        case "U":
        case "gU":
            changeCase(range, "U");
            break;
        case "g?":
            changeCase(range, "?");
            break;
        case "r": {
            if (cmd.ch !== "\n") {
                let s = "";
                for (let q = range.start; q < range.end; q = charEnd(t, q))
                    s += t[q] === "\n" ? "\n" : cmd.ch;
                replaceRange(range.start, range.end, s);
            }
            setCursor(clampNormal(editor.text, range.start));
            break;
        }
        case "J":
        case "gJ":
            joinLines(spannedLines(t.slice(lineRange.start, lineRange.end)), a === "J");
            break;
        case "I":
            startInsert(1, range.start, null);
            insertSession.dot = null;
            break;
        case "A":
            startInsert(1, range.linewise ? lineEnd(t, hi) : range.end, null);
            insertSession.dot = null;
            break;
        case "p":
        case "P": {
            const r = getRegister(cmd.reg);
            if (!r)
                break;
            let text = r.text, entries = r.hidden;
            if (r.linewise && !range.linewise) {
                text = "\n" + text;
                entries = shifted(entries, 1);
            } else if (!r.linewise && range.linewise) {
                text = text + "\n";
            }
            const removed = t.slice(range.start, range.end);
            const removedHidden = hiddenIn(hidden, range.start, range.end);
            replaceRange(range.start, range.end, text, entries);
            if (a === "p")
                setRegister(null, removed, range.linewise, false, removedHidden);
            const nt = editor.text;
            setCursor(clampNormal(nt, r.linewise
                ? firstNonBlank(nt, range.start + (range.linewise ? 0 : 1))
                : charStart(nt, range.start + text.length - 1)));
            break;
        }
        }
    }

    // ---- Insert and replace mode ------------------------------------------

    function startInsert(count, pos, openLine) {
        beginChange();
        setMode("insert");
        setCursor(pos);
        insertSession = { count: count, keys: [], openLine: openLine, dot: replaying ? null : dot, broken: false };
    }

    // Moving around in insert mode ends the repeatable part of the insert and
    // starts a new undo step, like in vim.
    function breakInsert() {
        if (blockHome)
            blockHome.moved = true;
        const s = insertSession;
        if (s && !s.broken) {
            if (s.dot)
                s.dot.insertKeys = s.keys.slice();
            s.broken = true;
        }
        commitChange();
        beginChange();
    }

    function leaveInsert() {
        const s = insertSession;
        if (s && !s.broken) {
            for (let i = 1; i < s.count; i++) {
                if (s.openLine) {
                    setCursor(editAll(q => {
                        const le = lineEnd(editor.text, q);
                        replaceRange(le, le, "\n");
                        return le + 1;
                    }));
                }
                for (const k of s.keys)
                    typeKey(k);
            }
            if (s.dot)
                s.dot.insertKeys = s.keys.slice();
        }
        insertSession = null;
        replaceStack = [];
        // Back to one cursor. After a block insert it goes back to where the
        // insert started (unless the cursors moved), otherwise it steps back
        // onto what was typed, as in vim.
        const block = blockHome;
        clearCursors();
        const t = editor.text;
        const p = block && !block.moved ? lineToPos(t, block.line) + block.offset
            : cursor > lineStart(t, cursor) ? charStart(t, cursor - 1) : cursor;
        setMode("normal");
        commitChange();
        setCursor(clampNormal(t, p));
        wantCol = column(t, cursor);
    }

    // Types an insert-mode key at every cursor (for extra cursors, macros,
    // "." and counts; otherwise the editor does it).
    function typeKey(tok) {
        if (mode === "replace") {
            replaceKey(tok);
            return;
        }
        setCursor(editAll(p => {
            if (tok === "<BS>") {
                if (p === 0)
                    return p;
                const q = charStart(editor.text, p - 1);
                replaceRange(q, p, "");
                return q;
            }
            if (tok === "<Del>") {
                if (p < editor.length)
                    replaceRange(p, charEnd(editor.text, p), "");
                return p;
            }
            const s = tok === "<CR>" ? "\n" : tok === "<Tab>" ? "\t" : tok;
            replaceRange(p, p, s);
            return p + s.length;
        }));
    }

    // Types a replace-mode key at every cursor. Each cursor keeps what it
    // replaced (the main one in replaceStack), for Backspace to put back.
    function replaceKey(tok) {
        setCursor(editAll((p, c) => {
            if (!c.main && !c.replaceStack)
                c.replaceStack = [];
            return replaceAt(p, c.main ? replaceStack : c.replaceStack, tok);
        }));
    }

    function replaceAt(p, stack, tok) {
        if (tok === "<BS>") {
            const q = charStart(editor.text, p - 1);
            if (stack.length) {
                const orig = stack.pop();
                replaceRange(q, p, orig ? orig.text : "", orig ? orig.hidden : []);
                return q;
            }
            return p > lineStart(editor.text, p) ? q : p;
        }
        const s = tok === "<CR>" ? "\n" : tok === "<Tab>" ? "\t" : tok;
        for (const ch of s) {
            const t = editor.text;
            // A line break is inserted without replacing anything.
            if (ch !== "\n" && p < t.length && t[p] !== "\n") {
                const e = charEnd(t, p);
                stack.push({ text: t.slice(p, e), hidden: hiddenIn(hidden, p, e) });
                replaceRange(p, e, ch);
            } else {
                stack.push(null);
                replaceRange(p, p, ch);
            }
            p += ch.length;
        }
        return p;
    }

    function repeatDot(count) {
        if (!dot)
            return;
        const cmd = Object.assign({}, dot.cmd);
        if (count)
            cmd.count = count;
        replaying = true;
        execute(cmd);
        if ((mode === "insert" || mode === "replace") && insertSession) {
            for (const k of dot.insertKeys) {
                insertSession.keys.push(k);
                typeKey(k);
            }
            leaveInsert();
        }
        replaying = false;
    }

    // ---- Visual block ------------------------------------------------------
    // Columns count characters, as elsewhere. After "$" the block reaches the
    // end of every line.

    // The block's columns (right is Infinity after "$") and one entry per
    // line, top to bottom: { line, ls, le, start, end, cols }, where
    // [start, end) is the part in the block (empty if the line is too short)
    // and cols the line's length.
    function blockShape(t) {
        const ca = column(t, anchor), cc = column(t, cursor);
        const left = Math.min(ca, cc), right = wantCol === Infinity ? Infinity : Math.max(ca, cc);
        const last = lineStart(t, Math.max(anchor, cursor));
        const lines = [];
        let ls = lineStart(t, Math.min(anchor, cursor));
        for (let line = lineOf(t, ls); ; line++) {
            const le = lineEnd(t, ls);
            const start = advance(t, ls, left, le);
            lines.push({ line: line, ls: ls, le: le, start: start,
                end: right === Infinity ? le : advance(t, start, right - left + 1, le), cols: column(t, le) });
            if (ls >= last)
                break;
            ls = le + 1;
        }
        return { left: left, right: right, lines: lines };
    }

    // The block as { start, end } spans, for drawing it.
    function blockSpans() {
        return blockShape(editor.text).lines.filter(l => l.end > l.start).map(l => ({ start: l.start, end: l.end }));
    }

    // Runs a visual block command. Returns false for the ones that work on
    // whole lines, as in the other visual modes.
    function executeBlock(cmd) {
        const t = editor.text;
        const a = cmd.action;
        const b = blockShape(t);
        const lines = b.lines;
        if (["D", "C"].includes(a))
            for (const l of lines)
                l.end = l.le;
        // Lines that reach the block; the others are left alone.
        const reached = lines.filter(l => l.cols > b.left);
        const points = (reached.length ? reached : lines.slice(0, 1))
            .map(l => ({ line: l.line, offset: l.start - l.ls, pad: "" }));
        const home = () => {
            const nt = editor.text;
            const ls = lineToPos(nt, lines[0].line);
            setCursor(clampNormal(nt, advance(nt, ls, b.left, lineEnd(nt, ls))));
            wantCol = column(nt, cursor);
        };
        switch (a) {
        case "y":
        case "d":
        case "x":
        case "<Del>":
        case "D":
        case "c":
        case "s":
        case "C": {
            const r = blockText(t, lines);
            setRegister(cmd.reg, r.text, false, a === "y", r.entries, true);
            setMode("normal");
            if (a !== "y")
                deleteBlock(lines);
            if (["c", "s", "C"].includes(a))
                startBlockInsert(points);
            else
                home();
            return true;
        }
        case "I":
        case "A": {
            setMode("normal");
            if (a === "A") {
                const col = b.right + 1;
                points.length = 0;
                for (const l of lines) {
                    if (b.right === Infinity || l.cols < col)
                        points.push({ line: l.line, offset: l.le - l.ls,
                            pad: b.right === Infinity ? "" : " ".repeat(col - l.cols) });
                    else
                        points.push({ line: l.line, offset: advance(t, l.ls, col, l.le) - l.ls, pad: "" });
                }
            }
            startBlockInsert(points);
            return true;
        }
        case "~":
        case "u":
        case "U":
        case "g~":
        case "gu":
        case "gU":
        case "g?":
            setMode("normal");
            for (let i = lines.length - 1; i >= 0; i--)
                changeCase(lines[i], a[a.length - 1]);
            home();
            return true;
        case "r":
            setMode("normal");
            if (cmd.ch !== "\n") {
                for (let i = lines.length - 1; i >= 0; i--) {
                    const l = lines[i];
                    let s = "";
                    for (let q = l.start; q < l.end; q = charEnd(t, q))
                        s += cmd.ch;
                    replaceRange(l.start, l.end, s);
                }
            }
            home();
            return true;
        case "p":
        case "P": {
            const r = getRegister(cmd.reg);
            if (!r)
                return true;
            const removed = blockText(t, lines);
            setMode("normal");
            deleteBlock(lines);
            if (r.blockwise) {
                putBlock(r, lines[0].line, b.left, 1);
            } else if (!r.linewise && !r.text.includes("\n")) {
                // One line of text goes on every line of the block.
                for (let i = points.length - 1; i >= 0; i--) {
                    const p = lineToPos(editor.text, points[i].line) + points[i].offset;
                    replaceRange(p, p, r.text, r.hidden);
                }
            } else {
                const nt = editor.text;
                setCursor(r.linewise ? lineToPos(nt, lines[lines.length - 1].line)
                    : lineToPos(nt, points[0].line) + points[0].offset);
                paste(cmd.reg, r.linewise, 1);
            }
            if (a === "p")
                setRegister(null, removed.text, false, false, removed.entries, true);
            if (!r.linewise)
                home();
            return true;
        }
        }
        return false;
    }

    // The text of a block's lines, one per line, with its hidden entries.
    function blockText(t, lines) {
        let text = "", entries = [];
        lines.forEach((l, i) => {
            if (i > 0)
                text += "\n";
            entries = entries.concat(shifted(hiddenIn(hidden, l.start, l.end), text.length));
            text += t.slice(l.start, l.end);
        });
        return { text: text, entries: entries };
    }

    function deleteBlock(lines) {
        // Bottom up, so the positions above stay right.
        for (let i = lines.length - 1; i >= 0; i--)
            replaceRange(lines[i].start, lines[i].end, "");
    }

    // Puts a blockwise register's lines at column `col` of line `line` and
    // the lines below it, adding lines at the end and padding short lines
    // with spaces where needed.
    function putBlock(r, line, col, count) {
        const pieces = r.text.split("\n");
        const width = Math.max(...pieces.map(s => column(s, s.length)));
        let from = 0;
        pieces.forEach((piece, i) => {
            const entries = hiddenIn(r.hidden, from, from + piece.length);
            from += piece.length + 1;
            if (line + i > countLines(editor.text))
                replaceRange(editor.length, editor.length, "\n");
            const t = editor.text;
            const ls = lineToPos(t, line + i), le = lineEnd(t, ls);
            const cols = column(t, le);
            const at = advance(t, ls, col, le);
            const lead = " ".repeat(Math.max(0, col - cols));
            // Pad each copy to the block's width, unless nothing follows it.
            const padded = piece + " ".repeat(width - column(piece, piece.length));
            const body = lead + (at < le ? padded.repeat(count) : padded.repeat(count - 1) + piece);
            replaceRange(at, at, body, shifted(repeated(entries, padded.length, count), lead.length));
        });
    }

    // Starts insert mode with a cursor at each of `points` ({ line, offset,
    // pad }, top to bottom: offset is from the line's start, and the spaces
    // in pad are added there first, to line the cursors up), the first being
    // the main one.
    function startBlockInsert(points) {
        for (const q of points) {
            if (q.pad) {
                const at = lineToPos(editor.text, q.line) + q.offset;
                replaceRange(at, at, q.pad);
            }
        }
        const t = editor.text;
        const at = points.map(q => lineToPos(t, q.line) + q.offset + q.pad.length);
        startInsert(1, at[0], null);
        insertSession.dot = null;
        setCursors(at.slice(1).map(p => ({ pos: p })));
        blockHome = { line: points[0].line, offset: points[0].offset + points[0].pad.length };
    }

    // ---- Multiple cursors --------------------------------------------------

    // Sets the extra cursors, sorted and without doubles or one at `main`
    // (the main cursor, unless given).
    function setCursors(list, main) {
        if (main === undefined)
            main = cursor;
        const sorted = list.slice().sort((a, b) => a.pos - b.pos);
        cursors = sorted.filter((c, i) => c.pos !== main && (i === 0 || c.pos !== sorted[i - 1].pos));
        if (cursors.length)
            trackedText = editor.text;
    }

    // Alt+click: adds a cursor at pos, or removes the one there.
    function toggleCursor(pos) {
        if (isVisual) {
            setMode("normal");
            setCursor(clampNormal(editor.text, cursor));
        }
        if (mode !== "normal" && mode !== "insert")
            return;
        const t = editor.text;
        const p = mode === "normal" ? clampNormal(t, pos) : Math.min(pos, t.length);
        if (cursors.some(c => c.pos === p))
            setCursors(cursors.filter(c => c.pos !== p));
        else
            setCursors(cursors.concat([{ pos: p }]));
    }

    // Back to one cursor (a plain click, or leaving insert mode).
    function clearCursors() {
        cursors = [];
        blockHome = null;
    }

    // Runs fn(pos, c) at every cursor, the main one too, from the last to the
    // first, so that each edit moves only cursors that are done (see
    // shiftCursors). fn returns the cursor's new position. Updates the extra
    // cursors and returns the main one's position.
    function editAll(fn) {
        const main = { pos: cursor, main: true };
        const all = [main].concat(cursors.filter(c => c.pos !== cursor).map(c => Object.assign({}, c)));
        shifting = all;
        for (const c of all.slice().sort((a, b) => b.pos - a.pos))
            c.pos = fn(c.pos, c);
        shifting = null;
        setCursors(all.filter(c => c !== main), main.pos);
        return main.pos;
    }

    // Runs a normal-mode command (fn, which works at `cursor`) at every
    // cursor, like editAll. Each extra cursor has registers of its own (the
    // main ones at first), so "yyp" copies every cursor's own line.
    function atEveryCursor(fn) {
        const mainRegisters = registers, initial = Object.assign({}, registers);
        setCursor(editAll((p, c) => {
            if (!c.main)
                registers = c.registers || Object.assign({}, initial);
            setCursor(p);
            fn();
            if (!c.main) {
                c.registers = registers;
                registers = mainRegisters;
            }
            return cursor;
        }));
    }

    // Moves the extra cursors for an edit that replaced [start, end) with
    // `length` characters: the ones after it along, the ones in it to the
    // same offset in the new text if it's that long (so undo keeps them),
    // otherwise to its end.
    function shiftCursors(start, end, length) {
        const move = q => q >= end ? q + length - (end - start) : Math.min(q, start + length);
        if (shifting) {
            for (const c of shifting)
                c.pos = move(c.pos);
        } else if (cursors.length) {
            setCursors(cursors.map(c => Object.assign({}, c, { pos: move(c.pos) })), -1);
        }
    }

    // ---- Macros ------------------------------------------------------------
    // A register holds a macro as text, with keys like Esc written "<Esc>".
    // A recorded one also keeps its keys, so typed text like "<CR>" stays text.

    function startRecording(reg) {
        recording = reg;
        recordKeys = [];
    }

    function stopRecording() {
        const reg = recording.toLowerCase();
        let ks = recordKeys;
        if (!draining)
            ks = ks.slice(0, -1); // the "q" that stopped it
        // "qA" appends to register a.
        const old = recording !== reg ? registers[reg] : null;
        if (old)
            ks = (old.keys || macroKeys(old.text)).concat(ks);
        registers[reg] = { text: ks.join(""), linewise: false, hidden: [], keys: ks };
        recording = "";
        recordKeys = [];
    }

    // Splits register text into keys.
    function macroKeys(text) {
        const named = { "\n": "<CR>", "\r": "<CR>", "\t": "<Tab>", "\x1b": "<Esc>" };
        const re = /<(?:Esc|CR|BS|Del|Tab|Left|Right|Up|Down|Home|End|PageUp|PageDown|C-[a-z])>|[\s\S]/gu;
        return (text.match(re) || []).map(k => named[k] || k);
    }

    function runMacro(reg, count) {
        if (reg === "@") {
            if (!lastMacro) {
                showError("E748: No previously used register");
                return;
            }
            reg = lastMacro;
        }
        lastMacro = reg;
        if (reg === ":") {
            const list = history[":"];
            if (!list.length) {
                showError("E30: No previous command line");
                return;
            }
            for (let i = 0; i < count; i++)
                runEx(list[list.length - 1].trim());
            return;
        }
        const r = getRegister(reg);
        if (!r)
            return;
        const ks = r.keys || macroKeys(r.text);
        let all = [];
        for (let i = 0; i < count; i++)
            all = all.concat(ks);
        // A macro run from a macro goes before the rest of that one.
        typeahead = all.concat(typeahead);
        if (draining)
            return;
        draining = true;
        for (let n = 0; typeahead.length; n++) {
            if (n === maxMacroKeys) {
                showError("Macro stopped after " + n + " keys");
                break;
            }
            runKey(typeahead.shift(), null);
        }
        draining = false;
    }

    // ---- Editing primitives ----------------------------------------------

    // `entries` are the hidden-text entries for `text`, if it has any.
    function replaceRange(start, end, text, entries) {
        syncing = true;
        editing = true;
        if (end > start)
            editor.remove(start, end);
        if (text.length)
            editor.insert(start, text);
        editing = false;
        syncing = false;
        if (hidden.length || entries && entries.length)
            shiftHidden(start, end, text.length, entries || []);
        shiftCursors(start, end, text.length);
        if (hidden.length || cursors.length)
            trackedText = editor.text;
    }

    function setMode(m) {
        const wasVisual = isVisual;
        mode = m;
        syncing = true;
        // Changing readOnly makes the editor scroll to where the cursor used
        // to be, then setting the cursor puts its line at the top. Keep the
        // view instead, and only scroll if the cursor is out of it.
        const view = flickable && { x: flickable.contentX, y: flickable.contentY };
        // Read-only outside insert mode, so macOS doesn't turn held keys into
        // the accent picker and nothing but vim edits the text.
        editor.readOnly = m !== "insert";
        if (wasVisual && !isVisual)
            editor.deselect();
        if (!isVisual)
            editor.cursorPosition = Math.min(cursor, editor.length);
        if (view) {
            flickable.contentX = view.x;
            flickable.contentY = view.y;
            showCursor();
        }
        syncing = false;
    }

    function setCursor(p) {
        cursor = p;
        syncing = true;
        if (isVisual)
            updateSelection();
        else
            editor.cursorPosition = p;
        syncing = false;
    }

    function updateSelection() {
        const t = editor.text;
        const n = t.length;
        if (mode === "visualBlock") {
            // The editor's selection can't be a block: the view draws it.
            editor.deselect();
            editor.cursorPosition = Math.min(cursor, n);
        } else if (mode === "visualLine") {
            const s = lineStart(t, Math.min(anchor, cursor));
            const e = Math.min(lineEnd(t, Math.max(anchor, cursor)) + 1, n);
            if (cursor >= anchor)
                editor.select(s, e);
            else
                editor.select(e, s);
        } else if (cursor >= anchor) {
            editor.select(anchor, charEnd(t, cursor));
        } else {
            editor.select(charEnd(t, anchor), cursor);
        }
    }

    // ---- Undo ------------------------------------------------------------
    // Each change (a normal-mode command, or everything typed in one insert)
    // is stored as the span it replaced, found by diffing the text around it.

    function beginChange() {
        if (!change)
            change = { before: editor.text, hidden: hidden, cursor: cursor };
    }

    function commitChange() {
        if (!change)
            return;
        const before = change.before, after = editor.text;
        const c = change.cursor, bh = change.hidden;
        change = null;
        const d = diff(before, after, bh, hidden);
        if (!d)
            return;
        const s = d.start, e1 = d.end1, e2 = d.end2;
        undoStack.push({ start: s, removed: before.slice(s, e1), inserted: after.slice(s, e2),
            removedHidden: hiddenIn(bh, s, e1), insertedHidden: hiddenIn(hidden, s, e2), cursor: c });
        redoStack = [];
    }

    function undo(count) {
        commitChange();
        let last = null;
        for (let i = 0; i < count && undoStack.length; i++) {
            last = undoStack.pop();
            replaceRange(last.start, last.start + last.inserted.length, last.removed, last.removedHidden);
            redoStack.push(last);
        }
        if (!last) {
            showMessage("Already at oldest change");
            return;
        }
        const p = Math.min(last.cursor, editor.length);
        setCursor(mode === "normal" ? clampNormal(editor.text, p) : p);
    }

    function redo(count) {
        commitChange();
        let last = null;
        for (let i = 0; i < count && redoStack.length; i++) {
            last = redoStack.pop();
            replaceRange(last.start, last.start + last.removed.length, last.inserted, last.insertedHidden);
            undoStack.push(last);
        }
        if (!last) {
            showMessage("Already at newest change");
            return;
        }
        // Land on an inserted line rather than the end of the line above it.
        const p = last.start + (last.inserted[0] === "\n" ? 1 : 0);
        setCursor(mode === "normal" ? clampNormal(editor.text, p) : p);
    }

    // ---- Registers -------------------------------------------------------

    // `entries` are the hidden-text entries for `text`, if it has any. A
    // blockwise register holds a visual block, one line of it per line.
    function setRegister(name, text, linewise, isYank, entries, blockwise) {
        if (name === "_")
            return;
        entries = entries || [];
        blockwise = !!blockwise;
        // The clipboard registers are separate: writing them leaves the
        // unnamed register (what plain "p" pastes) alone. Other apps get the
        // hidden texts revealed; VimEdit gets the 💩s back.
        if (name === "+" || name === "*") {
            if (clipboard)
                clipboard.setClipboardText(revealAll(text, entries), entries.length || blockwise
                    ? JSON.stringify({ text: text, hidden: entries, block: blockwise }) : "");
            return;
        }
        const entry = { text: text, linewise: linewise, hidden: entries, blockwise: blockwise };
        if (name && /^[A-Z]$/.test(name)) {
            const key = name.toLowerCase();
            const old = registers[key];
            if (old) {
                const sep = linewise && !old.linewise ? "\n" : "";
                entry.text = old.text + sep + text;
                entry.hidden = old.hidden.concat(shifted(entries, old.text.length + sep.length));
            }
            entry.linewise = linewise || (old && old.linewise);
            registers[key] = entry;
        } else if (name && name !== "\"") {
            registers[name] = entry;
        } else if (isYank) {
            registers["0"] = entry;
        }
        registers["\""] = entry;
    }

    function getRegister(name) {
        if (name === "+" || name === "*") {
            if (!clipboard)
                return null;
            try {
                const d = JSON.parse(clipboard.clipboardData() || "null");
                if (d && typeof d.text === "string" && validHidden(d.text, d.hidden))
                    return { text: d.text, linewise: !d.block && d.text.endsWith("\n"), hidden: d.hidden,
                        blockwise: !!d.block };
            } catch (e) {
                // not ours after all: use the text
            }
            const s = clipboard.clipboardText();
            return s ? { text: s, linewise: s.endsWith("\n"), hidden: [] } : null;
        }
        return registers[(name || "\"").toLowerCase()] || null;
    }

    function yank(t, range, reg) {
        let text = t.slice(range.start, range.end);
        if (range.linewise && !text.endsWith("\n"))
            text += "\n";
        setRegister(reg, text, range.linewise, true, hiddenIn(hidden, range.start, range.end));
    }

    function deleteRange(t, range, reg) {
        let s = range.start;
        let text = t.slice(s, range.end);
        if (range.linewise && !text.endsWith("\n")) {
            // Last line without a trailing newline: take the one before it.
            text += "\n";
            if (s > 0)
                s--;
        }
        setRegister(reg, text, range.linewise, false, hiddenIn(hidden, range.start, range.end));
        replaceRange(s, range.end, "");
        const nt = editor.text;
        if (range.linewise)
            setCursor(clampNormal(nt, firstNonBlank(nt, Math.min(s, nt.length))));
        else
            setCursor(clampNormal(nt, s));
    }

    function paste(reg, after, count) {
        const r = getRegister(reg);
        if (!r)
            return;
        const t = editor.text;
        const p = cursor;
        if (r.blockwise) {
            const line = lineOf(t, p);
            const col = column(t, p) + (after && p < lineEnd(t, p) ? 1 : 0);
            putBlock(r, line, col, count);
            const nt = editor.text;
            const ls = lineToPos(nt, line);
            setCursor(clampNormal(nt, advance(nt, ls, col, lineEnd(nt, ls))));
            return;
        }
        let entries = repeated(r.hidden, r.text.length, count);
        if (r.linewise) {
            let body = r.text.repeat(count);
            let at;
            if (!after) {
                at = lineStart(t, p);
            } else {
                const le = lineEnd(t, p);
                if (le < t.length) {
                    at = le + 1;
                } else {
                    at = t.length;
                    body = "\n" + body.slice(0, -1);
                    entries = shifted(entries, 1);
                }
            }
            replaceRange(at, at, body, entries);
            const nt = editor.text;
            setCursor(clampNormal(nt, firstNonBlank(nt, body[0] === "\n" ? at + 1 : at)));
        } else {
            const at = after && p < lineEnd(t, p) ? charEnd(t, p) : p;
            const body = r.text.repeat(count);
            replaceRange(at, at, body, entries);
            setCursor(clampNormal(editor.text, at + Math.max(body.length - 1, 0)));
        }
    }

    // ---- Hidden text ------------------------------------------------------
    // Cmd+J turns text into a 💩. The document holds a plain 💩, and the text
    // is kept beside it in `hidden`: a list of { at, item } sorted by
    // position, where item is { text, hidden } (hidden text can have 💩s of
    // its own). Every edit shifts the list: vim's own in replaceRange, the
    // editor's (typing in insert mode) by diffing the text. Registers, undo
    // steps and the clipboard carry the entries for the text they hold, so a
    // 💩 yanks, pastes and undoes like any character. Files get a plain 💩.

    readonly property string poop: "\uD83D\uDCA9"
    // Replaced, never changed in place, so a copy of the reference is a snapshot.
    property var hidden: []
    // The text `hidden` and `cursors` match, to diff the editor's own edits
    // against.
    property string trackedText: ""
    property bool editing: false
    readonly property Connections editorEdits: Connections {
        target: vim.editor

        function onTextChanged() {
            vim.trackEdit();
        }
    }

    // The entries of `list` in [start, end), relative to start.
    function hiddenIn(list, start, end) {
        return list.filter(h => h.at >= start && h.at < end).map(h => ({ at: h.at - start, item: h.item }));
    }

    function shifted(list, by) {
        return list.map(h => ({ at: h.at + by, item: h.item }));
    }

    // `list` for text repeated `count` times.
    function repeated(list, length, count) {
        let r = [];
        for (let i = 0; i < count; i++)
            r = r.concat(shifted(list, i * length));
        return r;
    }

    // Updates `hidden` for text [start, end) replaced by `length` characters
    // with the entries `entries`. A 💩 the edit touches loses its text.
    function shiftHidden(start, end, length, entries) {
        const d = length - (end - start);
        hidden = hidden.filter(h => h.at + poop.length <= start)
            .concat(shifted(entries, start), shifted(hidden.filter(h => h.at >= end), d));
    }

    // Edits made by the editor itself, rather than through replaceRange.
    function trackEdit() {
        if (editing || !hidden.length && !cursors.length)
            return;
        const before = trackedText, after = editor.text;
        trackedText = after;
        const d = diff(before, after, [], []);
        if (d) {
            if (hidden.length)
                shiftHidden(d.start, d.end1, d.end2 - d.start, []);
            shiftCursors(d.start, d.end1, d.end2 - d.start);
        }
    }

    // The span that differs between two texts with their entries: `before`
    // [start, end1) became `after` [start, end2). Null if nothing differs.
    function diff(before, after, beforeHidden, afterHidden) {
        const bh = beforeHidden, ah = afterHidden;
        let s = 0;
        const max = Math.min(before.length, after.length);
        while (s < max && before[s] === after[s])
            s++;
        let e1 = before.length, e2 = after.length;
        while (e1 > s && e2 > s && before[e1 - 1] === after[e2 - 1]) {
            e1--;
            e2--;
        }
        // A 💩 on both sides is only unchanged if its text is too.
        for (let i = 0; ; i++) {
            const b = bh[i], a = ah[i];
            const bIn = b && b.at < s, aIn = a && a.at < s;
            if (!bIn && !aIn)
                break;
            if (bIn && aIn && b.at === a.at && b.item === a.item)
                continue;
            s = Math.min(bIn ? b.at : s, aIn ? a.at : s);
            break;
        }
        for (let i = 1; ; i++) {
            const b = bh[bh.length - i], a = ah[ah.length - i];
            const bIn = b && b.at >= e1, aIn = a && a.at >= e2;
            if (!bIn && !aIn)
                break;
            if (bIn && aIn && before.length - b.at === after.length - a.at && b.item === a.item)
                continue;
            const cut = Math.max(bIn ? b.at + poop.length - e1 : 0, aIn ? a.at + poop.length - e2 : 0);
            e1 += cut;
            e2 += cut;
            break;
        }
        if (s === e1 && s === e2)
            return null;
        return { start: s, end1: e1, end2: e2 };
    }

    // Entries for `text` replacing [start, end) with the same 💩s in the
    // same order (a case change or indenting), which keep their texts.
    function carriedHidden(start, end, text) {
        const old = hiddenIn(hidden, start, end);
        const t = editor.text.slice(start, end);
        const r = [];
        let k = 0;
        for (let i = t.indexOf(poop), j = text.indexOf(poop); i >= 0 && j >= 0;
                i = t.indexOf(poop, i + poop.length), j = text.indexOf(poop, j + poop.length)) {
            while (k < old.length && old[k].at < i)
                k++;
            if (k < old.length && old[k].at === i)
                r.push({ at: j, item: old[k].item });
        }
        return r;
    }

    // The hidden-text entry of the 💩 at p, or null.
    function hiddenAt(p) {
        return hidden.find(h => h.at === p) || null;
    }

    // text with every hidden text (and any hidden inside that) revealed.
    function revealAll(text, list) {
        let r = "", i = 0;
        for (const h of list) {
            r += text.slice(i, h.at) + revealAll(h.item.text, h.item.hidden);
            i = h.at + poop.length;
        }
        return r + text.slice(i);
    }

    // Entries read from the clipboard: checked, since any app could have
    // put them there.
    function validHidden(text, list) {
        if (!Array.isArray(list))
            return false;
        let last = -poop.length;
        for (const h of list) {
            if (!h || !Number.isInteger(h.at) || h.at < last + poop.length || !text.startsWith(poop, h.at)
                    || !h.item || typeof h.item.text !== "string" || !validHidden(h.item.text, h.item.hidden))
                return false;
            last = h.at;
        }
        return true;
    }

    // Hides the selected text in a 💩, or reveals the text in the 💩 under
    // the cursor (or selected) and selects it, so Cmd+J again hides it again.
    function toggleHidden() {
        if (commandLine !== "" || mode === "replace")
            return;
        const t = editor.text;
        let range = null;
        if (isVisual) {
            const lo = Math.min(anchor, cursor), hi = Math.max(anchor, cursor);
            range = mode === "visualLine" ? { start: lineStart(t, lo), end: lineEnd(t, hi) }
                : { start: lo, end: charEnd(t, hi) };
            lastVisual = { mode: mode, anchor: anchor, cursor: cursor };
        } else if (mode === "insert" && editor.selectionStart !== editor.selectionEnd) {
            range = { start: editor.selectionStart, end: editor.selectionEnd };
        }
        let h;
        if (range)
            h = range.end === range.start + poop.length ? hiddenAt(range.start) : null;
        else
            h = hiddenAt(cursor) || (mode === "insert" ? hiddenAt(cursor - poop.length) : null);
        if (!h && (!range || range.end <= range.start))
            return;
        if (mode === "insert")
            breakInsert();
        externalEdit(() => {
            if (h) {
                const text = h.item.text, start = h.at, e = start + text.length;
                replaceRange(start, start + poop.length, text, h.item.hidden);
                if (mode === "insert") {
                    setCursor(e);
                    syncing = true;
                    editor.select(start, e);
                    syncing = false;
                } else {
                    anchor = start;
                    setMode("visual");
                    setCursor(charStart(editor.text, e - 1));
                }
            } else {
                const item = { text: t.slice(range.start, range.end), hidden: hiddenIn(hidden, range.start, range.end) };
                replaceRange(range.start, range.end, poop, [{ at: 0, item: item }]);
                if (mode === "insert") {
                    setCursor(charEnd(editor.text, range.start));
                } else {
                    setMode("normal");
                    setCursor(range.start);
                }
            }
        });
    }

    // ---- Other edits -------------------------------------------------------

    function joinLines(count, spaces) {
        const ls = lineStart(editor.text, cursor);
        let pos = cursor;
        for (let i = 1; i < Math.max(count, 2); i++) {
            const t = editor.text;
            const le = lineEnd(t, ls);
            if (le >= t.length)
                break;
            let e = le + 1;
            let sep = "";
            if (spaces) {
                while (e < t.length && (t[e] === " " || t[e] === "\t"))
                    e++;
                const endsBlank = t[le - 1] === " " || t[le - 1] === "\t";
                if (le > ls && e < t.length && t[e] !== "\n" && t[e] !== ")" && !endsBlank)
                    sep = " ";
            }
            replaceRange(le, e, sep);
            pos = le;
        }
        setCursor(clampNormal(editor.text, pos));
    }

    // Adds `delta` to the number under or after the cursor on its line:
    // decimal (with an optional "-"), 0x hex or 0b binary. Hex and binary
    // numbers, and decimals with leading zeros, keep their width.
    function addToNumber(delta) {
        const t = editor.text;
        const ls = lineStart(t, cursor), le = lineEnd(t, cursor);
        const re = /0[xX][0-9a-fA-F]+|0[bB][01]+|-?(?!0[xX][0-9a-fA-F]|0[bB][01])[0-9]+/g;
        const line = t.slice(ls, le);
        let m;
        do
            m = re.exec(line);
        while (m && ls + m.index + m[0].length <= cursor);
        if (!m) {
            typeahead = [];
            return;
        }
        const s = m[0];
        let text;
        if (/^0[xXbB]/.test(s)) {
            const base = /^0[xX]/.test(s) ? 16 : 2;
            const digits = s.slice(2);
            text = Math.max(0, parseInt(digits, base) + delta).toString(base).padStart(digits.length, "0");
            const letters = digits.match(/[a-fA-F]/g);
            if (letters && /[A-F]/.test(letters[letters.length - 1]))
                text = text.toUpperCase();
            text = s.slice(0, 2) + text;
        } else {
            const n = parseInt(s, 10) + delta;
            const digits = s.replace("-", "");
            const width = digits.length > 1 && digits[0] === "0" ? digits.length : 1;
            text = (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(width, "0");
        }
        const start = ls + m.index;
        replaceRange(start, start + s.length, text);
        setCursor(start + text.length - 1);
    }

    function shiftLines(range, dir, times) {
        const t = editor.text;
        const s = lineStart(t, range.start);
        const e = lineEnd(t, Math.max(range.start, range.end - 1));
        const lines = t.slice(s, e).split("\n").map(line => {
            if (dir > 0)
                return line.length ? (line[0] === "\t" ? "\t" : "    ").repeat(times) + line : line;
            let k = 0, cols = 0;
            while (k < line.length && cols < 4 * times && (line[k] === " " || line[k] === "\t")) {
                cols += line[k] === "\t" ? 4 : 1;
                k++;
            }
            return line.slice(k);
        });
        const text = lines.join("\n");
        replaceRange(s, e, text, carriedHidden(s, e, text));
        setCursor(clampNormal(editor.text, firstNonBlank(editor.text, s)));
    }

    // how: "~" toggles the case, "u" lowers it, "U" raises it, and "?" (g?)
    // is ROT13.
    function changeCase(range, how) {
        const t = editor.text;
        const s = t.slice(range.start, range.end);
        const text = how === "u" ? s.toLowerCase() : how === "U" ? s.toUpperCase()
            : how === "?" ? rot13(s) : toggleCase(s);
        replaceRange(range.start, range.end, text, carriedHidden(range.start, range.end, text));
        setCursor(clampNormal(editor.text, range.start));
    }

    // Moves each ASCII letter 13 places along the alphabet.
    function rot13(s) {
        return s.replace(/[a-zA-Z]/g, c => {
            const base = c <= "Z" ? 65 : 97;
            return String.fromCharCode((c.charCodeAt(0) - base + 13) % 26 + base);
        });
    }

    function toggleCase(s) {
        let r = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i], u = c.toUpperCase();
            r += c === u ? c.toLowerCase() : u;
        }
        return r;
    }

    // ---- Command line ------------------------------------------------------

    function runCommandLine(line) {
        const kind = line[0], body = line.slice(1);
        if (kind === ":") {
            runEx(body.trim());
            return;
        }
        const pattern = body || (lastSearch && lastSearch.pattern);
        if (!pattern)
            return;
        lastSearch = { pattern: pattern, forward: kind === "/" };
        moveBy({ count: 0, motion: { name: "n" } });
    }

    function runEx(c) {
        if (c === "")
            return;
        if (/^\d+$/.test(c) || c === "$") {
            const t = editor.text;
            const line = c === "$" ? countLines(t) : Math.max(1, Math.min(parseInt(c, 10), countLines(t)));
            if (isVisual)
                setMode("normal");
            setCursor(clampNormal(t, firstNonBlank(t, lineToPos(t, line))));
            return;
        }
        if (["w", "write"].includes(c))
            writeRequested(false);
        else if (["wq", "x", "wq!", "x!", "xit", "exit"].includes(c))
            writeRequested(true);
        else if (["q", "quit", "qa", "qall"].includes(c))
            quitRequested(false);
        else if (["q!", "quit!", "qa!", "qall!"].includes(c))
            quitRequested(true);
        else if (["noh", "nohl", "nohlsearch"].includes(c)) {
            highlightPattern = "";
            highlightsCleared();
        }
        else if (/^se(t)?(\s|$)/.test(c))
            setOptions(c.replace(/^\S+\s*/, ""));
        else
            showError("E492: Not an editor command: " + c);
    }

    // The boolean options :set knows: full name, short name, property.
    readonly property var options: [
        { name: "number", short: "nu", property: "number" },
        { name: "relativenumber", short: "rnu", property: "relativeNumber" }
    ]

    // :set with args like "nu", "nonu", "nu!", "invnu", "nu?" or "nu&". No
    // args lists the options that are on.
    function setOptions(args) {
        const words = args.split(/\s+/).filter(w => w);
        const shown = [];
        if (!words.length)
            shown.push(...options.filter(o => vim[o.property]).map(o => "  " + o.name));
        for (const w of words) {
            const m = /^(no|inv)?([a-z]+)([!?&]?)$/.exec(w);
            const o = m && options.find(o => o.name === m[2] || o.short === m[2]);
            if (!o) {
                showError("E518: Unknown option: " + w);
                return;
            }
            const prefix = m[1] || "", suffix = m[3];
            if (prefix && suffix) {
                showError("E474: Invalid argument: " + w);
                return;
            }
            if (suffix === "?")
                shown.push((vim[o.property] ? "  " : "no") + o.name);
            else if (suffix === "&")
                vim[o.property] = false;
            else if (suffix === "!" || prefix === "inv")
                vim[o.property] = !vim[o.property];
            else
                vim[o.property] = prefix !== "no";
        }
        if (shown.length)
            showMessage(shown.join(" "));
    }

    // ---- Motions -----------------------------------------------------------
    // Each returns { pos, type: "exclusive" | "inclusive" | "linewise" } or
    // null when the motion fails. `quiet` (for extra cursors) leaves the view
    // where it is.

    function motion(t, p, m, count, explicit, forOp, quiet) {
        const n = t.length;
        switch (m.name) {
        case "h":
        case "<Left>":
        case "<BS>": {
            const ls = lineStart(t, p);
            return p > ls ? { pos: retreat(t, p, count, ls), type: "exclusive" } : null;
        }
        case "l":
        case "<Right>":
        case " ": {
            const le = lineEnd(t, p);
            return p < le ? { pos: advance(t, p, count, le), type: "exclusive" } : null;
        }
        case "j":
        case "<Down>":
            return lineMotion(t, p, count);
        case "k":
        case "<Up>":
            return lineMotion(t, p, -count);
        case "+":
        case "<CR>":
        case "-": {
            const r = lineMotion(t, p, m.name === "-" ? -count : count);
            return r && { pos: firstNonBlank(t, r.pos), type: "linewise" };
        }
        case "_": {
            const r = count > 1 ? lineMotion(t, p, count - 1) : { pos: p };
            return r && { pos: firstNonBlank(t, r.pos), type: "linewise" };
        }
        case "0":
        case "<Home>":
            return { pos: lineStart(t, p), type: "exclusive" };
        case "^":
            return { pos: firstNonBlank(t, p), type: "exclusive" };
        case "$":
        case "<End>": {
            let q = p;
            if (count > 1) {
                const r = lineMotion(t, p, count - 1);
                if (!r)
                    return null;
                q = r.pos;
            }
            return { pos: lineEnd(t, q), type: "exclusive", eol: true };
        }
        case "|": {
            return { pos: atColumn(t, lineStart(t, p), count - 1), type: "exclusive" };
        }
        case "gg":
        case "G": {
            const lines = countLines(t);
            const line = explicit ? Math.min(count, lines) : m.name === "gg" ? 1 : lines;
            return { pos: firstNonBlank(t, lineToPos(t, line)), type: "linewise" };
        }
        case "w":
        case "W": {
            const big = m.name === "W";
            let q = p, prev = p;
            for (let i = 0; i < count; i++) {
                prev = q;
                q = nextWordStart(t, q, big);
            }
            // "dw" on the last word of a line stops at the end of that line.
            if (forOp) {
                const le = lineEnd(t, prev);
                if (q > le && le > prev)
                    q = le;
            }
            return q === p ? null : { pos: q, type: "exclusive" };
        }
        case "b":
        case "B": {
            let q = p;
            for (let i = 0; i < count; i++)
                q = prevWordStart(t, q, m.name === "B");
            return q === p ? null : { pos: q, type: "exclusive" };
        }
        case "e":
        case "E": {
            let q = p;
            for (let i = 0; i < count; i++)
                q = wordEnd(t, q, m.name === "E");
            return q === p ? null : { pos: q, type: "inclusive" };
        }
        case "ge":
        case "gE": {
            let q = p;
            for (let i = 0; i < count; i++)
                q = prevWordEnd(t, q, m.name === "gE");
            return q === p ? null : { pos: q, type: "inclusive" };
        }
        case "f":
        case "F":
        case "t":
        case "T":
            lastFind = { kind: m.name, ch: m.ch };
            return findChar(t, p, m.name, m.ch, count, false);
        case ";":
        case ",": {
            if (!lastFind)
                return null;
            const reverse = { f: "F", F: "f", t: "T", T: "t" };
            const kind = m.name === ";" ? lastFind.kind : reverse[lastFind.kind];
            return findChar(t, p, kind, lastFind.ch, count, true);
        }
        case "%": {
            if (explicit) {
                const line = Math.min(Math.ceil(count * countLines(t) / 100), countLines(t));
                return { pos: firstNonBlank(t, lineToPos(t, line)), type: "linewise" };
            }
            return matchPair(t, p);
        }
        case "}": {
            let q = p;
            for (let i = 0; i < count; i++)
                q = nextParagraph(t, q);
            return { pos: q, type: "exclusive" };
        }
        case "{": {
            let q = p;
            for (let i = 0; i < count; i++)
                q = prevParagraph(t, q);
            return { pos: q, type: "exclusive" };
        }
        case "n":
        case "N": {
            if (!lastSearch) {
                showError("E35: No previous regular expression");
                return null;
            }
            const forward = m.name === "n" ? lastSearch.forward : !lastSearch.forward;
            highlightPattern = lastSearch.pattern;
            const q = search(t, lastSearch.pattern, forward, count, p);
            return q === null ? null : { pos: q, type: "exclusive" };
        }
        case "*":
        case "#": {
            const w = wordAt(t, p);
            if (!w)
                return null;
            lastSearch = { pattern: "\\b" + w.text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b", forward: m.name === "*" };
            highlightPattern = lastSearch.pattern;
            const q = search(t, lastSearch.pattern, lastSearch.forward, count, lastSearch.forward ? p : w.start);
            return q === null ? null : { pos: q, type: "exclusive" };
        }
        case "H":
        case "M":
        case "L": {
            if (!flickable)
                return null;
            const lines = countLines(t);
            const top = Math.min(lines - 1, Math.max(0, Math.ceil((flickable.contentY - editor.topPadding) / lineHeight)));
            const bottom = Math.max(top, Math.min(lines - 1,
                Math.floor((flickable.contentY + flickable.height - editor.topPadding) / lineHeight) - 1));
            const line = m.name === "H" ? Math.min(top + count - 1, bottom)
                : m.name === "L" ? Math.max(bottom - count + 1, top) : Math.floor((top + bottom) / 2);
            return { pos: firstNonBlank(t, lineToPos(t, line + 1)), type: "linewise" };
        }
        default: { // page scrolling
            const half = m.name === "<C-d>" || m.name === "<C-u>";
            const down = ["<C-d>", "<C-f>", "<PageDown>"].includes(m.name);
            const lines = (half ? Math.floor(pageLines / 2) : pageLines - 2) * (down ? 1 : -1);
            if (!forOp && !quiet)
                scrollLines(lines);
            return lineMotion(t, p, lines);
        }
        }
    }

    function lineMotion(t, p, delta) {
        let ls = lineStart(t, p);
        let moved = 0;
        if (delta > 0) {
            while (moved < delta) {
                const le = lineEnd(t, ls);
                if (le >= t.length)
                    break;
                ls = le + 1;
                moved++;
            }
        } else {
            while (moved < -delta && ls > 0) {
                ls = lineStart(t, ls - 1);
                moved++;
            }
        }
        if (moved === 0)
            return null;
        return { pos: atColumn(t, ls, wantCol), type: "linewise", keepCol: true };
    }

    // 0 for blanks, 1 for punctuation, 2 for word characters (or any
    // non-blank for WORD motions).
    function charClass(ch, big) {
        if (ch === undefined)
            return 0;
        const c = ch.charCodeAt(0);
        if (c === 32 || c === 9 || c === 10 || c === 13)
            return 0;
        if (big)
            return 2;
        if (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c === 95 || c >= 0xC0)
            return 2;
        return 1;
    }

    function isEmptyLine(t, ls) {
        return ls >= t.length || t[ls] === "\n";
    }

    function nextWordStart(t, p, big) {
        const n = t.length;
        if (p >= n)
            return n;
        const c = charClass(t[p], big);
        if (c !== 0)
            while (p < n && charClass(t[p], big) === c)
                p++;
        while (p < n) {
            if (t[p] === "\n") {
                p++;
                if (p < n && t[p] === "\n")
                    return p; // an empty line counts as a word
                continue;
            }
            if (charClass(t[p], big) !== 0)
                return p;
            p++;
        }
        return n;
    }

    function prevWordStart(t, p, big) {
        let q = p - 1;
        while (q > 0 && charClass(t[q], big) === 0) {
            if (t[q] === "\n" && t[q - 1] === "\n")
                return q;
            q--;
        }
        if (q <= 0)
            return 0;
        const c = charClass(t[q], big);
        while (q > 0 && charClass(t[q - 1], big) === c)
            q--;
        return q;
    }

    function wordEnd(t, p, big) {
        const n = t.length;
        let q = charEnd(t, p);
        while (q < n && charClass(t[q], big) === 0)
            q++;
        if (q >= n)
            return p;
        const c = charClass(t[q], big);
        for (let e = charEnd(t, q); e < n && charClass(t[e], big) === c; e = charEnd(t, q))
            q = e;
        return q;
    }

    function prevWordEnd(t, p, big) {
        let q = p;
        const c = charClass(t[q], big);
        if (c !== 0)
            while (q > 0 && charClass(t[q - 1], big) === c)
                q--;
        q--;
        while (q > 0 && charClass(t[q], big) === 0) {
            if (t[q] === "\n" && t[q - 1] === "\n")
                return q;
            q--;
        }
        return charStart(t, Math.max(q, 0));
    }

    function findChar(t, p, kind, ch, count, repeat) {
        const ls = lineStart(t, p), le = lineEnd(t, p);
        let q = p;
        if (kind === "f" || kind === "t") {
            for (let i = 0; i < count; i++) {
                // Repeating "t" skips a match right next to the cursor.
                const from = kind === "t" && repeat && i === 0 && t[q + 1] === ch ? q + 2 : q + 1;
                const idx = t.indexOf(ch, from);
                if (idx < 0 || idx >= le)
                    return null;
                q = idx;
            }
            return { pos: kind === "t" ? charStart(t, q - 1) : q, type: "inclusive" };
        }
        for (let i = 0; i < count; i++) {
            const from = kind === "T" && repeat && i === 0 && t[q - 1] === ch ? q - 2 : q - 1;
            if (from < ls)
                return null;
            const idx = t.lastIndexOf(ch, from);
            if (idx < ls)
                return null;
            q = idx;
        }
        return { pos: kind === "T" ? charEnd(t, q) : q, type: "exclusive" };
    }

    function matchPair(t, p) {
        const pairs = "()[]{}";
        const le = lineEnd(t, p);
        let q = p;
        while (q < le && pairs.indexOf(t[q]) < 0)
            q++;
        if (q >= le)
            return null;
        const i = pairs.indexOf(t[q]);
        const open = pairs[i & ~1], close = pairs[i | 1], step = i % 2 === 0 ? 1 : -1;
        let depth = 0;
        for (let k = q; k >= 0 && k < t.length; k += step) {
            if (t[k] === open)
                depth += step;
            else if (t[k] === close)
                depth -= step;
            if (depth === 0)
                return { pos: k, type: "inclusive" };
        }
        return null;
    }

    function nextParagraph(t, p) {
        const n = t.length;
        let q = lineStart(t, p);
        while (q < n && isEmptyLine(t, q))
            q++;
        while (q < n) {
            const le = lineEnd(t, q);
            if (le >= n)
                return n;
            q = le + 1;
            if (isEmptyLine(t, q))
                return q;
        }
        return n;
    }

    function prevParagraph(t, p) {
        let q = lineStart(t, p);
        while (q > 0 && isEmptyLine(t, q))
            q = lineStart(t, q - 1);
        while (q > 0) {
            q = lineStart(t, q - 1);
            if (isEmptyLine(t, q))
                return q;
        }
        return 0;
    }

    // A pattern that isn't a valid regular expression (e.g. while it's still
    // being typed) is searched for literally.
    function searchRegExp(pattern) {
        try {
            return new RegExp(pattern, "gm");
        } catch (e) {
            return new RegExp(pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gm");
        }
    }

    function search(t, pattern, forward, count, from) {
        const re = searchRegExp(pattern);
        let p = from;
        for (let i = 0; i < count; i++) {
            const q = forward ? searchForward(re, t, p, false) : searchBackward(re, t, p, false);
            if (q < 0) {
                showError("E486: Pattern not found: " + pattern);
                return null;
            }
            p = q;
        }
        return p;
    }

    function searchForward(re, t, p, quiet) {
        re.lastIndex = p + 1;
        let m = p + 1 <= t.length ? re.exec(t) : null;
        if (!m) {
            re.lastIndex = 0;
            m = re.exec(t);
            if (m && !quiet)
                showMessage("search hit BOTTOM, continuing at TOP");
        }
        return m ? m.index : -1;
    }

    function searchBackward(re, t, p, quiet) {
        let before = -1, last = -1, m;
        re.lastIndex = 0;
        while ((m = re.exec(t)) !== null) {
            if (m.index < p)
                before = m.index;
            last = m.index;
            if (m[0] === "")
                re.lastIndex++;
        }
        if (before < 0 && last >= 0 && !quiet)
            showMessage("search hit TOP, continuing at BOTTOM");
        return before >= 0 ? before : last;
    }

    // ---- Search preview ----------------------------------------------------

    function typedSearch() {
        const kind = commandLine[0];
        return kind === "/" || kind === "?" ? commandLine.slice(1) : null;
    }

    // Like vim's 'incsearch': while a search is typed, scroll to the match
    // Enter would jump to, and restore the view when the search is cancelled.
    function previewSearch() {
        const pattern = typedSearch();
        if (pattern === null) {
            if (searchView && flickable) {
                flickable.contentX = searchView.x;
                flickable.contentY = searchView.y;
            }
            searchView = null;
            searchTarget = -1;
            return;
        }
        if (!searchView && flickable)
            searchView = { x: flickable.contentX, y: flickable.contentY };
        const t = editor.text;
        const re = searchRegExp(pattern);
        searchTarget = pattern === "" ? -1
            : commandLine[0] === "/" ? searchForward(re, t, cursor, true) : searchBackward(re, t, cursor, true);
        if (!flickable)
            return;
        if (searchTarget < 0) {
            flickable.contentX = searchView.x;
            flickable.contentY = searchView.y;
            return;
        }
        const r = editor.positionToRectangle(searchTarget);
        const maxX = Math.max(0, flickable.contentWidth - flickable.width);
        const maxY = Math.max(0, flickable.contentHeight - flickable.height);
        // Text in the left padding is under the line numbers, if they're on.
        const x = r.x < searchView.x + editor.leftPadding || r.x + r.width > searchView.x + flickable.width
            ? r.x - flickable.width / 2 : searchView.x;
        const y = r.y < searchView.y || r.y + r.height > searchView.y + flickable.height
            ? r.y - flickable.height / 2 : searchView.y;
        flickable.contentX = Math.max(0, Math.min(x, maxX));
        flickable.contentY = Math.max(0, Math.min(y, maxY));
    }

    // Matches of the search being typed (or else of the last search, until
    // it's cleared) that fall in the visible lines, as highlightSpans.
    function searchHighlights() {
        const typed = typedSearch();
        const pattern = typed !== null ? typed : highlightPattern;
        if (!pattern)
            return [];
        const t = editor.text;
        const v = visibleRange(t);
        const re = searchRegExp(pattern);
        const spans = [];
        re.lastIndex = v.from;
        let m;
        while ((m = re.exec(t)) !== null && m.index <= v.to && spans.length < 5000) {
            if (m[0] === "") {
                re.lastIndex++;
                continue;
            }
            addHighlight(t, spans, m.index, m.index + m[0].length, m.index === highlightTarget);
        }
        return spans;
    }

    // The part of the text [from, to] in the visible lines.
    function visibleRange(t) {
        if (!flickable)
            return { from: 0, to: t.length };
        const top = Math.floor((flickable.contentY - editor.topPadding) / lineHeight);
        const bottom = Math.ceil((flickable.contentY + flickable.height - editor.topPadding) / lineHeight);
        return { from: lineToPos(t, Math.max(top, 0) + 1), to: lineEnd(t, lineToPos(t, Math.max(bottom, 0) + 1)) };
    }

    // Adds the highlight of a match [start, end) to spans, split into one
    // { start, end, current } span per line, where current means it's the
    // match to show as the current one.
    function addHighlight(t, spans, start, end, current) {
        for (let s = start; s < end;) {
            const nl = t.indexOf("\n", s);
            const e = nl < 0 || nl > end ? end : nl;
            if (e > s)
                spans.push({ start: s, end: e, current: current });
            s = e + 1;
        }
    }

    function wordAt(t, p) {
        const le = lineEnd(t, p);
        let s = p;
        while (s < le && charClass(t[s], false) !== 2)
            s++;
        if (s >= le)
            return null;
        while (s > 0 && charClass(t[s - 1], false) === 2)
            s--;
        let e = s;
        while (e < t.length && charClass(t[e], false) === 2)
            e++;
        return { start: s, text: t.slice(s, e) };
    }

    // ---- Text objects ------------------------------------------------------
    // Each returns { start, end, linewise } with `end` exclusive, or null.

    function textObject(t, p, obj, count) {
        switch (obj.ch) {
        case "w":
        case "W":
            return wordObject(t, p, obj.around, obj.ch === "W");
        case "p":
            return paragraphObject(t, p, obj.around);
        case "\"":
        case "'":
        case "`":
            return quoteObject(t, p, obj.around, obj.ch);
        case "(":
        case ")":
        case "b":
            return blockObject(t, p, obj.around, "(", ")", count);
        case "[":
        case "]":
            return blockObject(t, p, obj.around, "[", "]", count);
        case "{":
        case "}":
        case "B":
            return blockObject(t, p, obj.around, "{", "}", count);
        default:
            return blockObject(t, p, obj.around, "<", ">", count);
        }
    }

    function isBlank(ch) {
        return ch === " " || ch === "\t";
    }

    function wordObject(t, p, around, big) {
        const ls = lineStart(t, p), le = lineEnd(t, p);
        if (p >= le)
            return { start: p, end: p, linewise: false };
        const c = charClass(t[p], big);
        const same = i => charClass(t[i], big) === c;
        let s = p, e = p + 1;
        while (s > ls && same(s - 1))
            s--;
        while (e < le && same(e))
            e++;
        if (around) {
            if (c !== 0) {
                let e2 = e;
                while (e2 < le && isBlank(t[e2]))
                    e2++;
                if (e2 > e)
                    e = e2;
                else
                    while (s > ls && isBlank(t[s - 1]))
                        s--;
            } else if (e < le) {
                const c2 = charClass(t[e], big);
                while (e < le && charClass(t[e], big) === c2)
                    e++;
            }
        }
        return { start: s, end: e, linewise: false };
    }

    function quoteObject(t, p, around, q) {
        const ls = lineStart(t, p), le = lineEnd(t, p);
        const quotes = [];
        for (let i = ls; i < le; i++)
            if (t[i] === q && (i === ls || t[i - 1] !== "\\"))
                quotes.push(i);
        let open = -1, close = -1;
        for (let k = 0; k + 1 < quotes.length; k += 2)
            if (p >= quotes[k] && p <= quotes[k + 1]) {
                open = quotes[k];
                close = quotes[k + 1];
                break;
            }
        if (open < 0)
            for (let k = 0; k + 1 < quotes.length; k += 2)
                if (quotes[k] > p) {
                    open = quotes[k];
                    close = quotes[k + 1];
                    break;
                }
        if (open < 0)
            return null;
        if (!around)
            return { start: open + 1, end: close, linewise: false };
        let s = open, e = close + 1;
        let e2 = e;
        while (e2 < le && isBlank(t[e2]))
            e2++;
        if (e2 > e)
            e = e2;
        else
            while (s > ls && isBlank(t[s - 1]))
                s--;
        return { start: s, end: e, linewise: false };
    }

    function blockObject(t, p, around, open, close, count) {
        let o = t[p] === open ? p : -1;
        let from = p - 1;
        for (let i = 0; i < count; i++) {
            if (i > 0 || o < 0) {
                let depth = 0;
                o = -1;
                for (let k = from; k >= 0; k--) {
                    if (t[k] === close) {
                        depth++;
                    } else if (t[k] === open) {
                        if (depth === 0) {
                            o = k;
                            break;
                        }
                        depth--;
                    }
                }
                if (o < 0)
                    return null;
            }
            from = o - 1;
        }
        let c = -1, depth = 0;
        for (let k = o; k < t.length; k++) {
            if (t[k] === open)
                depth++;
            else if (t[k] === close && --depth === 0) {
                c = k;
                break;
            }
        }
        if (c < 0)
            return null;
        if (around)
            return { start: o, end: c + 1, linewise: false };
        // A block whose braces sit on their own lines is changed linewise.
        if (t[o + 1] === "\n") {
            const cls = lineStart(t, c);
            if (/^[ \t]*$/.test(t.slice(cls, c)) && cls > o + 2)
                return { start: o + 2, end: cls, linewise: true };
            return { start: o + 2, end: c, linewise: false };
        }
        return { start: o + 1, end: c, linewise: false };
    }

    function paragraphObject(t, p, around) {
        const n = t.length;
        const ls = lineStart(t, p);
        const empty = isEmptyLine(t, ls);
        const nextLine = q => {
            const le = lineEnd(t, q);
            return le + 1 < n ? le + 1 : -1;
        };
        let s = ls;
        while (s > 0 && isEmptyLine(t, lineStart(t, s - 1)) === empty)
            s = lineStart(t, s - 1);
        let e = ls;
        for (let q = nextLine(e); q >= 0 && isEmptyLine(t, q) === empty; q = nextLine(q))
            e = q;
        if (around) {
            let q = nextLine(e);
            if (q >= 0) {
                for (; q >= 0 && isEmptyLine(t, q) !== empty; q = nextLine(q))
                    e = q;
            } else {
                while (s > 0 && isEmptyLine(t, lineStart(t, s - 1)) !== empty)
                    s = lineStart(t, s - 1);
            }
        }
        return { start: s, end: Math.min(lineEnd(t, e) + 1, n), linewise: true };
    }

    // ---- Text helpers ------------------------------------------------------

    function lineStart(t, p) {
        return p <= 0 ? 0 : t.lastIndexOf("\n", p - 1) + 1;
    }

    function lineEnd(t, p) {
        const i = t.indexOf("\n", p);
        return i < 0 ? t.length : i;
    }

    function firstNonBlank(t, p) {
        let q = lineStart(t, p);
        while (q < t.length && isBlank(t[q]))
            q++;
        return q;
    }

    // Normal mode keeps the cursor on a character, never past the line's end.
    function clampNormal(t, p) {
        p = Math.max(0, Math.min(p, t.length));
        const ls = lineStart(t, p), le = lineEnd(t, p);
        return charStart(t, le > ls && p >= le ? le - 1 : p);
    }

    // A character is one code point plus the code points that attach to it:
    // combining marks, variation selectors, emoji modifiers and tags, and
    // whatever follows a zero-width joiner. Like Qt, vim moves over one as a
    // whole, so the cursor never lands inside an emoji (or a hidden-text 💩).
    function attaches(t, i) {
        const c = t.codePointAt(i);
        return c >= 0x300 && c <= 0x36F || c >= 0x1AB0 && c <= 0x1AFF || c >= 0x1DC0 && c <= 0x1DFF
            || c >= 0x20D0 && c <= 0x20FF || c >= 0xFE00 && c <= 0xFE0F || c >= 0xFE20 && c <= 0xFE2F
            || c === 0x200D || c >= 0x1F3FB && c <= 0x1F3FF || c >= 0xE0000 && c <= 0xE0FFF
            || t.charCodeAt(i - 1) === 0x200D;
    }

    function isLowSurrogate(t, i) {
        const c = t.charCodeAt(i), h = t.charCodeAt(i - 1);
        return c >= 0xDC00 && c <= 0xDFFF && h >= 0xD800 && h <= 0xDBFF;
    }

    // End of the character at p.
    function charEnd(t, p) {
        const n = t.length;
        if (p >= n)
            return n;
        if (t[p] === "\n")
            return p + 1;
        let q = p + 1;
        while (q < n && (isLowSurrogate(t, q) || t[q] !== "\n" && attaches(t, q)))
            q++;
        return q;
    }

    // Start of the character that p is in.
    function charStart(t, p) {
        if (p >= t.length)
            return Math.max(p, 0);
        let q = p;
        while (q > 0 && t[q - 1] !== "\n" && (isLowSurrogate(t, q) || attaches(t, q)))
            q--;
        return q;
    }

    // Steps over up to `count` characters, but not past `limit`.
    function advance(t, p, count, limit) {
        for (let i = 0; i < count && p < limit; i++)
            p = Math.min(charEnd(t, p), limit);
        return p;
    }

    function retreat(t, p, count, limit) {
        for (let i = 0; i < count && p > limit; i++)
            p = Math.max(charStart(t, p - 1), limit);
        return p;
    }

    // Column of p in its line, counted in characters.
    function column(t, p) {
        // p can be past the end: the editor may report its cursor before the
        // text change that moved it.
        p = Math.min(p, t.length);
        let col = 0;
        for (let q = lineStart(t, p); q < p; q = charEnd(t, q))
            col++;
        return col;
    }

    // Position of column `col` in the line starting at ls, or of the line's
    // last character when it's shorter.
    function atColumn(t, ls, col) {
        const le = lineEnd(t, ls);
        let q = ls;
        for (let i = 0; i < col && charEnd(t, q) < le; i++)
            q = charEnd(t, q);
        return q;
    }

    function countLines(t) {
        let lines = 1;
        for (let i = t.indexOf("\n"); i >= 0; i = t.indexOf("\n", i + 1))
            lines++;
        return lines;
    }

    // Lines covered by a linewise span, which ends after its last newline.
    function spannedLines(s) {
        return countLines(s) - (s.endsWith("\n") ? 1 : 0);
    }

    function lineToPos(t, line) {
        let pos = 0;
        for (let i = 1; i < line; i++) {
            const nl = t.indexOf("\n", pos);
            if (nl < 0)
                break;
            pos = nl + 1;
        }
        return pos;
    }

    // The line number (from 1) of position p.
    function lineOf(t, p) {
        let line = 1;
        for (let i = t.indexOf("\n"); i >= 0 && i < p; i = t.indexOf("\n", i + 1))
            line++;
        return line;
    }

    // ---- View ----------------------------------------------------------

    function scrollLines(lines) {
        if (!flickable)
            return;
        const max = Math.max(0, flickable.contentHeight - flickable.height);
        flickable.contentY = Math.max(0, Math.min(flickable.contentY + lines * lineHeight, max));
    }

    // Scrolls as little as shows the cursor.
    function showCursor() {
        if (!flickable)
            return;
        const f = flickable, r = editor.positionToRectangle(Math.min(cursor, editor.length));
        const top = editor.topPadding + (lineOf(editor.text, cursor) - 1) * lineHeight;
        const maxY = Math.max(0, f.contentHeight - f.height);
        if (top < f.contentY)
            f.contentY = top <= editor.topPadding ? 0 : top;
        else if (top + lineHeight > f.contentY + f.height)
            f.contentY = Math.min(maxY, top + lineHeight - f.height);
        // The left edge is the padding (see keepCursorClear in main.qml).
        const maxX = Math.max(0, f.contentWidth - f.width);
        if (r.x < f.contentX + editor.leftPadding)
            f.contentX = Math.max(0, r.x - editor.leftPadding);
        else if (r.x + r.width > f.contentX + f.width)
            f.contentX = Math.min(maxX, r.x + r.width - f.width);
    }

    // Ctrl-E and Ctrl-Y: scrolls the view `lines` whole lines (down if
    // positive), and moves the cursor only as far as keeps it in view.
    function scrollText(lines) {
        if (!flickable)
            return;
        const f = flickable, h = lineHeight, pad = editor.topPadding;
        const at = Math.max(0, (f.contentY - pad) / h); // the top line, maybe partly hidden
        const top = Math.max(0, lines > 0 ? Math.floor(at + 1e-6) + lines : Math.ceil(at - 1e-6) + lines);
        f.contentY = top === 0 ? 0 : Math.min(Math.max(0, f.contentHeight - f.height), pad + top * h);
        const t = editor.text, n = countLines(t);
        const first = Math.min(n - 1, Math.max(0, Math.ceil((f.contentY - pad) / h - 1e-6)));
        // A line counts as shown with the space below its text cut off.
        const last = Math.max(first, Math.min(n - 1, Math.floor((f.contentY + f.height - pad) / h + 0.25) - 1));
        const line = lineOf(t, cursor) - 1;
        const d = line < first ? first - line : line > last ? last - line : 0;
        if (d)
            moveBy({ count: Math.abs(d), motion: { name: d > 0 ? "j" : "k" } });
    }

    function scrollToCursor(where) {
        if (!flickable)
            return;
        const r = editor.positionToRectangle(cursor);
        const y = where === "t" ? r.y - editor.topPadding
            : where === "b" ? r.y + r.height + editor.bottomPadding - flickable.height
            : r.y + r.height / 2 - flickable.height / 2;
        const max = Math.max(0, flickable.contentHeight - flickable.height);
        flickable.contentY = Math.max(0, Math.min(y, max));
    }
}
