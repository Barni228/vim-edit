#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>

// Installs an application-wide event filter that turns QFileOpenEvent
// (sent by macOS when a file is opened via Finder / "Open With") into a
// call to `target.openFile(QString)`.
void installFileOpenFilter(QObject& target);

// On macOS, Qt titles the PreferencesRole menu item "Preferences...".
// Rename it to "Settings…" to match current macOS conventions.
void useSettingsMenuTitle();

// Sets the Qt Quick Controls style. Must run before QML is loaded.
void setControlsStyle(const QString& style);

// System clipboard access for the vim "+ and "* registers. Other registers
// never touch the clipboard. Along with the text, VimEdit can store data of
// its own (the hidden texts behind 💩s), which only VimEdit reads.
QString clipboardText();
QString clipboardData();
void setClipboardText(const QString& text, const QString& data);

// Gives every line of a TextEdit's document (a QQuickTextDocument) the same
// height, so a line with an emoji (from a taller font) doesn't grow. New
// lines inherit it, but setting the TextEdit's text resets it. The bottom
// margin adds to each line's height; Qt puts a fixed-height line's baseline
// at 4/5 of it, and the margin lets the text sit higher in the whole line.
void setLineFormat(QObject* textDocument, double height, double bottomMargin);

// The installed font families whose text characters are all the same width,
// in alphabetical order: the fonts the editor offers. It loads every font,
// which takes a moment (a few hundred ms for a few hundred families).
QStringList monospaceFamilies();
