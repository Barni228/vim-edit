#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>

// Installs an application-wide event filter that turns QFileOpenEvent
// (sent by macOS when a file is opened via Finder / "Open With") into a
// call to `target.openFile(QString)`.
void installFileOpenFilter(QObject& target);

// On macOS, Qt titles the PreferencesRole menu item "Preferences...".
// Rename it to "Settings…" to match current macOS conventions.
void useSettingsMenuTitle();

// System clipboard access for the vim "+ and "* registers. Other registers
// never touch the clipboard.
QString clipboardText();
void setClipboardText(const QString& text);
