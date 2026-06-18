mod app;
pub mod flow_state;
mod storage;
mod styles;

pub fn launch() {
    dioxus::launch(app::App);
}
