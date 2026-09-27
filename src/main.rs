// Release builds on Windows are GUI apps (no console window).
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod document;
mod platform;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("VimEdit"));
        app.set_organization_name(&QString::from("VimEdit"));
    }
    platform::ffi::use_settings_menu_title();

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/VimEdit/qml/main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
