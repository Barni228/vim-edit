#pragma once

#include <QtCore/QObject>

// Installs an application-wide event filter that turns QFileOpenEvent
// (sent by macOS when a file is opened via Finder / "Open With") into a
// call to `target.openFile(QString)`.
void installFileOpenFilter(QObject& target);

// On macOS, Qt titles the PreferencesRole menu item "Preferences...".
// Rename it to "Settings…" to match current macOS conventions.
void useSettingsMenuTitle();
