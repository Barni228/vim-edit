use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("VimEdit").qml_file("qml/main.qml"))
        .qt_module("Gui")
        .qt_module("Quick")
        .files(["src/document.rs", "src/platform.rs"])
        .cpp_file("cpp/platform.cpp")
        .include_dir("cpp")
        .build();
}
