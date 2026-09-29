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

    // Qt Quick's default Windows style has no dark theme. Fusion follows the
    // system's light or dark mode, title bar and menus included (FluentWinUI3
    // left those light). Setting QT_QUICK_CONTROLS_STYLE from here doesn't
    // work: Qt reads the C runtime's copy of the environment, made at startup.
    #[cfg(windows)]
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        platform::ffi::set_controls_style(&QString::from("Fusion"));
    }

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/VimEdit/qml/main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
