use dioxus::prelude::*;
use powerjack_core::flow_state::{
    FocusMuscle, SelectedExercise, SelectedTemplate, TemplateFlowState, TemplateStep,
};

use super::{storage, styles::APP_CSS};

const EXERCISES: &[(i64, &str)] = &[
    (1, "Bench Press"),
    (2, "Row"),
    (3, "Squat"),
    (4, "Overhead Press"),
    (5, "Romanian Deadlift"),
];

const MUSCLE_FOCUS_SCRIPT: &str = r#"
(() => {
  const limit = 4;
  const init = () => {
    const inputs = Array.from(document.querySelectorAll('[data-muscle-focus-input="true"]'));
    const count = document.getElementById('muscle-focus-count');
    const next = document.getElementById('flow-next');
    if (!inputs.length || !count || !next || next.dataset.muscleFocusReady === 'true') return;

    const selectedInputs = () => inputs.filter((input) => input.checked);

    const sync = () => {
      const selected = selectedInputs();
      count.textContent = `${selected.length}/${limit}`;

      for (const input of inputs) {
        input.disabled = !input.checked && selected.length >= limit;
      }

      const canContinue = selected.length > 0;
      next.classList.toggle('disabled', !canContinue);
      next.setAttribute('aria-disabled', canContinue ? 'false' : 'true');
      next.tabIndex = canContinue ? 0 : -1;
    };

    for (const input of inputs) {
      input.addEventListener('change', () => {
        if (input.checked && selectedInputs().length > limit) {
          input.checked = false;
        }
        sync();
      });
    }

    next.addEventListener('click', (event) => {
      if (next.getAttribute('aria-disabled') === 'true') {
        event.preventDefault();
      }
    });

    next.dataset.muscleFocusReady = 'true';
    sync();
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
"#;

#[derive(Clone, Debug, PartialEq)]
struct MuscleOptionData {
    id: i64,
    name: String,
}

#[derive(Clone, Debug, PartialEq)]
struct TemplateOptionData {
    id: i64,
    name: String,
    workouts_per_week: i64,
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

fn load_template_options() -> Result<Vec<TemplateOptionData>, String> {
    storage::list_templates().map(|templates| {
        templates
            .into_iter()
            .map(|template| TemplateOptionData {
                id: template.id.0,
                name: template.name,
                workouts_per_week: template.workouts_per_week,
            })
            .collect()
    })
}

#[derive(Clone, Routable, Debug, PartialEq)]
enum Route {
    #[route("/")]
    SelectTemplate {},
    #[route("/program-length")]
    ProgramLength {},
    #[route("/program-ready")]
    ProgramReady {},
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
    let flow = use_context::<Signal<TemplateFlowState>>();
    let templates = use_signal(load_template_options);
    let can_continue = flow.read().can_continue_from_template_selection();

    rsx! {
        main { class: "app-root setup-root",
            section { class: "setup-screen setup-screen-centered",
                div { class: "setup-panel select-template-panel",
                    h1 { class: "screen-title", "Select Template" }
                    p { class: "screen-subtitle",
                        "Choose an existing template or create a new reusable workout template."
                    }

                    div { class: "template-list",
                        match &*templates.read() {
                            Ok(templates) if templates.is_empty() => rsx! {
                                div { class: "empty-state",
                                    span { "No saved templates yet." }
                                }
                            },
                            Ok(templates) => rsx! {
                                for template in templates {
                                    TemplateOption {
                                        id: template.id,
                                        name: template.name.clone(),
                                        workouts_per_week: template.workouts_per_week,
                                        flow
                                    }
                                }
                            },
                            Err(_) => rsx! {
                                div { class: "empty-state error-state",
                                    span { "Templates could not be loaded." }
                                }
                            }
                        }
                    }

                    a {
                        class: "create-template-action",
                        "data-testid": "new-template-action",
                        href: "/new-template/muscle-focus",
                        span { class: "button-icon", "+" }
                        span { "New Template" }
                    }

                    nav { class: "panel-nav",
                        button {
                            class: "nav-button secondary-action",
                            "data-testid": "select-template-back",
                            disabled: true,
                            "Back"
                        }
                        button {
                            class: "nav-button",
                            "data-testid": "select-template-next",
                            disabled: !can_continue,
                            onclick: move |_| {
                                if can_continue {
                                    nav.push(Route::ProgramLength {});
                                }
                            },
                            "Next"
                            span { class: "button-arrow", "->" }
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn TemplateOption(
    id: i64,
    name: String,
    workouts_per_week: i64,
    mut flow: Signal<TemplateFlowState>,
) -> Element {
    let selected = flow.read().template_is_selected(id);
    let class_name = if selected {
        "template-option selected"
    } else {
        "template-option"
    };

    rsx! {
        button {
            class: "{class_name}",
            "data-testid": "template-{id}",
            onclick: move |_| {
                flow.write()
                    .select_template(SelectedTemplate::new(id, name.clone(), workouts_per_week));
            },
            span { class: "template-option-name", "{name}" }
            span { class: "template-option-meta", "{workouts_per_week} days/week" }
        }
    }
}

#[allow(non_snake_case)]
fn ProgramLength() -> Element {
    let nav = use_navigator();
    let mut flow = use_context::<Signal<TemplateFlowState>>();
    let mut error = use_signal(|| None::<String>);
    let state = flow.read();
    let selected_template = state.selected_template.clone();
    let selected_weeks = state.program_length_weeks;
    let can_start = state.can_start_selected_template_program();
    drop(state);

    let title = selected_template
        .as_ref()
        .map(|template| template.name.as_str())
        .unwrap_or("Selected Template");
    let subtitle = selected_template
        .as_ref()
        .map(|template| format!("{} days per week", template.workouts_per_week))
        .unwrap_or_else(|| "Choose a template first.".to_string());

    rsx! {
        main { class: "app-root setup-root",
            section { class: "setup-screen",
                div { class: "setup-panel program-length-panel",
                    p { class: "eyebrow", "New Program" }
                    h1 { class: "screen-title", "{title}" }
                    p { class: "screen-subtitle", "{subtitle}" }

                    h2 { class: "section-title", "Program Length in Weeks" }
                    div { class: "week-grid",
                        for weeks in [4_u8, 6, 8, 10, 12] {
                            button {
                                class: if selected_weeks == Some(weeks) { "week-option selected" } else { "week-option" },
                                "data-testid": "program-weeks-{weeks}",
                                onclick: move |_| flow.write().set_program_length_weeks(weeks),
                                "{weeks}"
                            }
                        }
                    }

                    if let Some(message) = error.read().as_ref() {
                        p { class: "hint error-text", "{message}" }
                    }

                    nav { class: "panel-nav",
                        button {
                            class: "nav-button secondary-action",
                            "data-testid": "program-length-back",
                            onclick: move |_| {
                                nav.push(Route::SelectTemplate {});
                            },
                            "Back"
                        }
                        button {
                            class: "nav-button",
                            "data-testid": "program-length-start",
                            disabled: !can_start,
                            onclick: move |_| {
                                let state = flow.read();
                                let Some(template) = state.selected_template.clone() else {
                                    return;
                                };
                                let Some(weeks) = state.program_length_weeks else {
                                    return;
                                };
                                drop(state);

                                match storage::create_program_from_template(
                                    template.id,
                                    template.name.as_str(),
                                    weeks as i64,
                                ) {
                                    Ok(_) => {
                                        nav.push(Route::ProgramReady {});
                                    }
                                    Err(message) => error.set(Some(message)),
                                }
                            },
                            "Start"
                            span { class: "button-arrow", "->" }
                        }
                    }
                }
            }
        }
    }
}

#[allow(non_snake_case)]
fn ProgramReady() -> Element {
    let flow = use_context::<Signal<TemplateFlowState>>();
    let state = flow.read();
    let template_name = state
        .selected_template
        .as_ref()
        .map(|template| template.name.as_str())
        .unwrap_or("Program");
    let weeks = state
        .program_length_weeks
        .map(|weeks| weeks.to_string())
        .unwrap_or_else(|| "0".to_string());

    rsx! {
        main { class: "app-root setup-root",
            section { class: "setup-screen setup-screen-centered",
                div { class: "setup-panel complete-panel",
                    p { class: "eyebrow", "New Program" }
                    h1 { class: "screen-title", "Program Ready" }
                    p { class: "screen-subtitle",
                        "{template_name} is active for {weeks} weeks."
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
        }
    }
}

#[component]
fn FlowShell(step: TemplateStep, children: Element) -> Element {
    let nav = use_navigator();
    let flow = use_context::<Signal<TemplateFlowState>>();
    let can_continue = flow.read().can_continue(step);
    let step_position = step.position();

    let back_href = step.previous().map(href_for_step).unwrap_or("/");
    let next_route = step.next().map(route_for_step);
    let next_label = if next_route.is_some() { "Next" } else { "Done" };

    rsx! {
        main { class: "app-root",
            section { class: "screen",
                Header { title: "New Template" }
                div { class: "flow-main",
                    div { class: "step-meta",
                        span { "Step {step_position} of 4" }
                    }
                    {children}
                }
                nav { class: "bottom-nav",
                    a {
                        class: "nav-button secondary-action",
                        "data-testid": "flow-back",
                        href: "{back_href}",
                        "Back"
                    }
                    if step == TemplateStep::MuscleFocus {
                        a {
                            id: "flow-next",
                            class: "nav-button disabled",
                            "data-testid": "flow-next",
                            href: "/new-template/days-per-week",
                            "aria-disabled": "true",
                            tabindex: "-1",
                            "{next_label}"
                        }
                    } else {
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
}

#[allow(non_snake_case)]
fn MuscleFocusStep() -> Element {
    let flow = use_context::<Signal<TemplateFlowState>>();
    let muscles = use_signal(load_muscle_options);

    rsx! {
        div { class: "panel",
            h1 { class: "step-title", "Muscle Focus" }
            p { class: "lede",
                "Pick the muscles this template should emphasize. "
                span { id: "muscle-focus-count", "0/4" }
            }
            match &*muscles.read() {
                Ok(muscles) if muscles.is_empty() => rsx! {
                    p { class: "hint", "No muscles found in the database." }
                },
                Ok(muscles) => rsx! {
                    div { class: "option-grid",
                        for muscle in muscles {
                            MuscleOption { id: muscle.id, name: muscle.name.clone(), flow }
                        }
                    }
                },
                Err(_) => rsx! {
                    p { class: "hint", "Muscles could not be loaded from the database." }
                }
            }
        }
        script { dangerous_inner_html: "{MUSCLE_FOCUS_SCRIPT}" }
    }
}

#[component]
fn MuscleOption(id: i64, name: String, mut flow: Signal<TemplateFlowState>) -> Element {
    rsx! {
        label {
            class: "muscle-choice",
            "data-testid": "focus-{id}",
            input {
                class: "muscle-choice-input",
                r#type: "checkbox",
                name: "focus_muscle",
                value: "{id}",
                "data-muscle-focus-input": "true",
                onchange: move |_| flow.write().toggle_focus_muscle(FocusMuscle::new(id, name.clone())),
            }
            span { class: "option-button muscle-choice-body",
                span { "{name}" }
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

fn href_for_step(step: TemplateStep) -> &'static str {
    match step {
        TemplateStep::MuscleFocus => "/new-template/muscle-focus",
        TemplateStep::DaysPerWeek => "/new-template/days-per-week",
        TemplateStep::ExerciseBuilder => "/new-template/exercise-builder",
        TemplateStep::SaveTemplate => "/new-template/save",
    }
}
