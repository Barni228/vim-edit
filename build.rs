use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("VimEdit").qml_files(["qml/main.qml", "qml/Vim.qml", "qml/FindBar.qml", "qml/SettingsWindow.qml", "qml/HelpPanel.qml"]),
    )
    .qt_module("Gui")
    .qt_module("Quick")
    .qt_module("QuickControls2")
    .files(["src/document.rs", "src/platform.rs"])
    .cpp_file("cpp/platform.cpp")
    .include_dir("cpp")
    .build();
}
