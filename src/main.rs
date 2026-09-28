// Release builds on Windows are GUI apps (no console window).
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod document;
mod platform;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    // Qt Quick's default Windows style has no dark theme; FluentWinUI3 follows
    // the system's light or dark mode.
    #[cfg(windows)]
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        // SAFETY: no other threads are running yet.
        unsafe { std::env::set_var("QT_QUICK_CONTROLS_STYLE", "FluentWinUI3") };
    }

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
