use dioxus::prelude::*;

use super::{
    flow_state::{FocusMuscle, SelectedExercise, TemplateFlowState, TemplateStep},
    storage,
    styles::APP_CSS,
};

const EXERCISES: &[(i64, &str)] = &[
    (1, "Bench Press"),
    (2, "Row"),
    (3, "Squat"),
    (4, "Overhead Press"),
    (5, "Romanian Deadlift"),
];

#[derive(Clone, Debug, PartialEq)]
struct MuscleOptionData {
    id: i64,
    name: String,
}

fn load_muscle_options() -> Result<Vec<MuscleOptionData>, String> {
    storage::list_muscles().map(|muscles| {
        muscles
            .into_iter()
            .map(|muscle| MuscleOptionData {
                id: muscle.id.0,
                name: muscle.name,
            })
            .collect()
    })
}

#[derive(Clone, Routable, Debug, PartialEq)]
enum Route {
    #[route("/")]
    SelectTemplate {},
    #[route("/new-template/muscle-focus")]
    MuscleFocus {},
    #[route("/new-template/days-per-week")]
    DaysPerWeek {},
    #[route("/new-template/exercise-builder")]
    ExerciseBuilder {},
    #[route("/new-template/save")]
    SaveTemplate {},
}

#[allow(non_snake_case)]
pub fn App() -> Element {
    use_context_provider(|| Signal::new(TemplateFlowState::default()));

    rsx! {
        style { "{APP_CSS}" }
        Router::<Route> {}
    }
}

#[allow(non_snake_case)]
fn SelectTemplate() -> Element {
    let nav = use_navigator();

    rsx! {
        main { class: "app-root",
            section { class: "screen",
                Header { title: "PowerJack" }
                div { class: "select-template",
                    div { class: "panel",
                        h1 { class: "step-title", "Select Template" }
                        p {
                            "Choose an existing template or start a new reusable workout template."
                        }
                    }
                    button {
                        class: "primary-action",
                        "data-testid": "new-template-action",
                        onclick: move |_| {
                            nav.push(Route::MuscleFocus {});
                        },
                        "New Template"
                    }
                }
            }
        }
    }
}

#[allow(non_snake_case)]
fn MuscleFocus() -> Element {
    rsx! {
        FlowShell { step: TemplateStep::MuscleFocus,
            MuscleFocusStep {}
        }
    }
}

#[allow(non_snake_case)]
fn DaysPerWeek() -> Element {
    rsx! {
        FlowShell { step: TemplateStep::DaysPerWeek,
            DaysPerWeekStep {}
        }
    }
}

#[allow(non_snake_case)]
fn ExerciseBuilder() -> Element {
    rsx! {
        FlowShell { step: TemplateStep::ExerciseBuilder,
            ExerciseBuilderStep {}
        }
    }
}

#[allow(non_snake_case)]
fn SaveTemplate() -> Element {
    let flow = use_context::<Signal<TemplateFlowState>>();
    let state = flow.read();
    let focus = state
        .focus_muscles
        .iter()
        .map(|muscle| muscle.name.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    let days = state
        .days_per_week
        .map(|days| days.to_string())
        .unwrap_or_else(|| "Not selected".to_string());
    let exercise_count = state
        .exercises_by_day
        .values()
        .map(|exercises| exercises.len())
        .sum::<usize>();

    rsx! {
        FlowShell { step: TemplateStep::SaveTemplate,
            div { class: "panel",
                h1 { class: "step-title", "Save Template" }
                p { class: "lede",
                    "Review only for now. Saving to SQLite belongs to the next story."
                }
                div { class: "summary-list",
                    div { class: "summary-row",
                        span { "Focus" }
                        strong { "{focus}" }
                    }
                    div { class: "summary-row",
                        span { "Days" }
                        strong { "{days}" }
                    }
                    div { class: "summary-row",
                        span { "Exercises" }
                        strong { "{exercise_count}" }
                    }
                }
            }
        }
    }
}

#[component]
fn Header(title: &'static str) -> Element {
    rsx! {
        header { class: "header",
            h1 { class: "brand", "{title}" }
            button { class: "profile-button", title: "Profile", "◎" }
        }
    }
}

#[component]
fn FlowShell(step: TemplateStep, children: Element) -> Element {
    let nav = use_navigator();
    let flow = use_context::<Signal<TemplateFlowState>>();
    let can_continue = flow.read().can_continue(step);
    let step_position = step.position();
    let title = step.title();

    let back_route = step
        .previous()
        .map(route_for_step)
        .unwrap_or(Route::SelectTemplate {});
    let next_route = step.next().map(route_for_step);
    let next_label = if next_route.is_some() { "Next" } else { "Done" };

    rsx! {
        main { class: "app-root",
            section { class: "screen",
                Header { title: "New Template" }
                div { class: "flow-main",
                    div { class: "step-meta",
                        span { "Step {step_position} of 4" }
                        span { "{title}" }
                    }
                    {children}
                }
                nav { class: "bottom-nav",
                    button {
                        class: "nav-button secondary-action",
                        "data-testid": "flow-back",
                        onclick: move |_| {
                            nav.push(back_route.clone());
                        },
                        "Back"
                    }
                    button {
                        class: "nav-button",
                        "data-testid": "flow-next",
                        disabled: !can_continue,
                        onclick: move |_| {
                            if let Some(route) = next_route.clone() {
                                nav.push(route);
                            }
                        },
                        "{next_label}"
                    }
                }
            }
        }
    }
}

#[allow(non_snake_case)]
fn MuscleFocusStep() -> Element {
    let flow = use_context::<Signal<TemplateFlowState>>();
    let muscles = use_resource(|| async { load_muscle_options() });
    let state = flow.read();
    let selected_count = state.focus_muscle_count();
    let selection_limit = state.focus_muscle_limit();
    drop(state);

    rsx! {
        div { class: "panel",
            h1 { class: "step-title", "Muscle Focus" }
            p { class: "lede",
                "Pick the muscles this template should emphasize. {selected_count}/{selection_limit}"
            }
            match &*muscles.read_unchecked() {
                Some(Ok(muscles)) if muscles.is_empty() => rsx! {
                    p { class: "hint", "No muscles found in the database." }
                },
                Some(Ok(muscles)) => rsx! {
                    div { class: "option-grid",
                        for muscle in muscles {
                            MuscleOption { id: muscle.id, name: muscle.name.clone(), flow }
                        }
                    }
                },
                Some(Err(_)) => rsx! {
                    p { class: "hint", "Muscles could not be loaded from the database." }
                },
                None => rsx! {
                    p { class: "hint", "Loading muscles..." }
                }
            }
        }
    }
}

#[component]
fn MuscleOption(id: i64, name: String, mut flow: Signal<TemplateFlowState>) -> Element {
    let state = flow.read();
    let selected = state.focus_is_selected(id);
    let disabled = !state.can_toggle_focus_muscle(id);
    drop(state);

    let class_name = if selected {
        "option-button selected"
    } else if disabled {
        "option-button disabled"
    } else {
        "option-button"
    };

    rsx! {
        button {
            class: "{class_name}",
            "data-testid": "focus-{id}",
            disabled,
            onclick: move |_| flow.write().toggle_focus_muscle(FocusMuscle::new(id, name.clone())),
            span { "{name}" }
            if selected {
                span { class: "check", "Selected" }
            }
        }
    }
}

#[allow(non_snake_case)]
fn DaysPerWeekStep() -> Element {
    let mut flow = use_context::<Signal<TemplateFlowState>>();
    let selected_days = flow.read().days_per_week;

    rsx! {
        div { class: "panel",
            h1 { class: "step-title", "Days Per Week" }
            p { class: "lede", "Choose how many workout days this template should create." }
            div { class: "option-grid",
                for days in 2..=6 {
                    button {
                        class: if selected_days == Some(days) { "option-button selected" } else { "option-button" },
                        "data-testid": "days-{days}",
                        onclick: move |_| flow.write().set_days_per_week(days),
                        span { "{days} days" }
                        if selected_days == Some(days) {
                            span { class: "check", "Selected" }
                        }
                    }
                }
            }
        }
    }
}

#[allow(non_snake_case)]
fn ExerciseBuilderStep() -> Element {
    let flow = use_context::<Signal<TemplateFlowState>>();
    let days = flow.read().days_per_week.unwrap_or(0);

    rsx! {
        div { class: "panel",
            h1 { class: "step-title", "Exercise Builder" }
            p { class: "lede",
                "Add at least one exercise to each day. Search and save come later."
            }
            if days == 0 {
                p { class: "hint", "Choose days per week first." }
            } else {
                for day in 1..=days {
                    div { class: "day-group",
                        h3 { "Day {day}" }
                        div { class: "option-grid",
                            for (id, name) in EXERCISES {
                                ExerciseOption { day, id: *id, name: *name, flow }
                            }
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn ExerciseOption(
    day: u8,
    id: i64,
    name: &'static str,
    mut flow: Signal<TemplateFlowState>,
) -> Element {
    let selected = flow.read().exercise_is_selected(day, id);
    let class_name = if selected {
        "option-button selected"
    } else {
        "option-button"
    };

    rsx! {
        button {
            class: "{class_name}",
            "data-testid": "exercise-day-{day}-{id}",
            onclick: move |_| {
                flow.write()
                    .toggle_exercise_for_day(day, SelectedExercise::new(id, name));
            },
            span { "{name}" }
            if selected {
                span { class: "check", "Added" }
            }
        }
    }
}

fn route_for_step(step: TemplateStep) -> Route {
    match step {
        TemplateStep::MuscleFocus => Route::MuscleFocus {},
        TemplateStep::DaysPerWeek => Route::DaysPerWeek {},
        TemplateStep::ExerciseBuilder => Route::ExerciseBuilder {},
        TemplateStep::SaveTemplate => Route::SaveTemplate {},
    }
}
