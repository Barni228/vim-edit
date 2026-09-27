#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!(<QtCore/QObject>);
        type QObject = cxx_qt::QObject;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;

        include!("platform.h");

        /// Forwards macOS "Open With" (QFileOpenEvent) to `target.openFile(path)`.
        #[cxx_name = "installFileOpenFilter"]
        fn install_file_open_filter(target: Pin<&mut QObject>);

        /// Titles the macOS app-menu PreferencesRole item "Settings…".
        #[cxx_name = "useSettingsMenuTitle"]
        fn use_settings_menu_title();

        /// Reads the system clipboard (vim's "+ and "* registers).
        #[cxx_name = "clipboardText"]
        fn clipboard_text() -> QString;

        /// Writes the system clipboard.
        #[cxx_name = "setClipboardText"]
        fn set_clipboard_text(text: &QString);
    }
}
