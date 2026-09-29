use std::pin::Pin;

use cxx_qt::casting::Upcast;
use cxx_qt_lib::{QString, QUrl};

use crate::platform;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qurl.h");
        type QUrl = cxx_qt_lib::QUrl;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type Document = super::DocumentRust;

        /// Emitted after a file was read successfully.
        #[qsignal]
        fn loaded(self: Pin<&mut Document>, path: QString, text: QString);

        /// Emitted when reading or writing fails.
        #[qsignal]
        fn failed(self: Pin<&mut Document>, message: QString);

        #[qinvokable]
        fn open_file(self: Pin<&mut Document>, path: &QString);

        #[qinvokable]
        fn save_file(self: Pin<&mut Document>, path: &QString, text: &QString) -> bool;

        /// Path passed on the command line (how Windows/Linux "Open With" launches us).
        #[qinvokable]
        fn startup_file(self: &Document) -> QString;

        #[qinvokable]
        fn url_to_path(self: &Document, url: &QUrl) -> QString;

        #[qinvokable]
        fn clipboard_text(self: &Document) -> QString;

        #[qinvokable]
        fn clipboard_data(self: &Document) -> QString;

        #[qinvokable]
        fn set_clipboard_text(self: &Document, text: &QString, data: &QString);

        /// Gives every line of a TextEdit's `textDocument` the same height,
        /// plus margins below it and on its left.
        #[qinvokable]
        unsafe fn set_line_format(
            self: &Document,
            text_document: *mut QObject,
            height: f64,
            bottom_margin: f64,
            left_margin: f64,
        );
    }

    impl cxx_qt::Initialize for Document {}
}

#[derive(Default)]
pub struct DocumentRust;

impl cxx_qt::Initialize for qobject::Document {
    fn initialize(self: Pin<&mut Self>) {
        platform::ffi::install_file_open_filter(self.upcast_pin());
    }
}

impl qobject::Document {
    fn open_file(self: Pin<&mut Self>, path: &QString) {
        match std::fs::read_to_string(path.to_string()) {
            Ok(text) => self.loaded(path.clone(), QString::from(text.as_str())),
            Err(err) => self.failed(QString::from(
                format!("Could not open {path}: {err}").as_str(),
            )),
        }
    }

    fn save_file(self: Pin<&mut Self>, path: &QString, text: &QString) -> bool {
        match std::fs::write(path.to_string(), text.to_string()) {
            Ok(()) => true,
            Err(err) => {
                self.failed(QString::from(
                    format!("Could not save {path}: {err}").as_str(),
                ));
                false
            }
        }
    }

    fn startup_file(&self) -> QString {
        std::env::args()
            .skip(1)
            .find(|arg| !arg.starts_with('-'))
            .map(|arg| QString::from(arg.as_str()))
            .unwrap_or_default()
    }

    fn url_to_path(&self, url: &QUrl) -> QString {
        url.to_local_file().unwrap_or_default()
    }

    fn clipboard_text(&self) -> QString {
        platform::ffi::clipboard_text()
    }

    fn clipboard_data(&self) -> QString {
        platform::ffi::clipboard_data()
    }

    fn set_clipboard_text(&self, text: &QString, data: &QString) {
        platform::ffi::set_clipboard_text(text, data);
    }

    /// # Safety
    ///
    /// `text_document` must be null or point to a live QObject.
    unsafe fn set_line_format(
        &self,
        text_document: *mut qobject::QObject,
        height: f64,
        bottom_margin: f64,
        left_margin: f64,
    ) {
        unsafe {
            platform::ffi::set_line_format(text_document.cast(), height, bottom_margin, left_margin)
        };
    }
}
