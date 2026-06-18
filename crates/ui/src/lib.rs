mod app;
mod storage;
mod styles;

pub use app::App;

pub fn launch() {
    dioxus::launch(App);
}
