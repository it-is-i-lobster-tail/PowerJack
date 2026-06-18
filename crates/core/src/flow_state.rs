use std::collections::BTreeMap;

pub const MAX_FOCUS_MUSCLES: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TemplateStep {
    MuscleFocus,
    DaysPerWeek,
    ExerciseBuilder,
    SaveTemplate,
}

impl TemplateStep {
    pub const ALL: [Self; 4] = [
        Self::MuscleFocus,
        Self::DaysPerWeek,
        Self::ExerciseBuilder,
        Self::SaveTemplate,
    ];

    pub fn title(self) -> &'static str {
        match self {
            Self::MuscleFocus => "Muscle Focus",
            Self::DaysPerWeek => "Days Per Week",
            Self::ExerciseBuilder => "Exercise Builder",
            Self::SaveTemplate => "Save Template",
        }
    }

    pub fn previous(self) -> Option<Self> {
        match self {
            Self::MuscleFocus => None,
            Self::DaysPerWeek => Some(Self::MuscleFocus),
            Self::ExerciseBuilder => Some(Self::DaysPerWeek),
            Self::SaveTemplate => Some(Self::ExerciseBuilder),
        }
    }

    pub fn next(self) -> Option<Self> {
        match self {
            Self::MuscleFocus => Some(Self::DaysPerWeek),
            Self::DaysPerWeek => Some(Self::ExerciseBuilder),
            Self::ExerciseBuilder => Some(Self::SaveTemplate),
            Self::SaveTemplate => None,
        }
    }

    pub fn position(self) -> usize {
        Self::ALL.iter().position(|step| *step == self).unwrap_or(0) + 1
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FocusMuscle {
    pub id: i64,
    pub name: String,
}

impl FocusMuscle {
    pub fn new(id: i64, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectedExercise {
    pub id: i64,
    pub name: String,
}

impl SelectedExercise {
    pub fn new(id: i64, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectedTemplate {
    pub id: i64,
    pub name: String,
    pub workouts_per_week: i64,
}

impl SelectedTemplate {
    pub fn new(id: i64, name: impl Into<String>, workouts_per_week: i64) -> Self {
        Self {
            id,
            name: name.into(),
            workouts_per_week,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TemplateFlowState {
    pub selected_template: Option<SelectedTemplate>,
    pub program_length_weeks: Option<u8>,
    pub focus_muscles: Vec<FocusMuscle>,
    pub days_per_week: Option<u8>,
    pub exercises_by_day: BTreeMap<u8, Vec<SelectedExercise>>,
}

impl TemplateFlowState {
    pub fn select_template(&mut self, template: SelectedTemplate) {
        if self
            .selected_template
            .as_ref()
            .is_some_and(|selected| selected.id == template.id)
        {
            self.selected_template = None;
            self.program_length_weeks = None;
        } else {
            self.selected_template = Some(template);
            self.program_length_weeks = None;
        }
    }

    pub fn template_is_selected(&self, id: i64) -> bool {
        self.selected_template
            .as_ref()
            .is_some_and(|template| template.id == id)
    }

    pub fn can_continue_from_template_selection(&self) -> bool {
        self.selected_template.is_some()
    }

    pub fn set_program_length_weeks(&mut self, weeks: u8) {
        self.program_length_weeks = Some(weeks);
    }

    pub fn can_start_selected_template_program(&self) -> bool {
        self.selected_template.is_some() && self.program_length_weeks.is_some()
    }

    pub fn toggle_focus_muscle(&mut self, muscle: FocusMuscle) {
        if let Some(index) = self
            .focus_muscles
            .iter()
            .position(|selected| selected.id == muscle.id)
        {
            self.focus_muscles.remove(index);
        } else if self.can_select_more_focus_muscles() {
            self.focus_muscles.push(muscle);
        }
    }

    pub fn can_select_more_focus_muscles(&self) -> bool {
        self.focus_muscles.len() < MAX_FOCUS_MUSCLES
    }

    pub fn can_toggle_focus_muscle(&self, id: i64) -> bool {
        self.focus_is_selected(id) || self.can_select_more_focus_muscles()
    }

    pub fn focus_muscle_count(&self) -> usize {
        self.focus_muscles.len()
    }

    pub fn focus_muscle_limit(&self) -> usize {
        MAX_FOCUS_MUSCLES
    }

    pub fn set_days_per_week(&mut self, days: u8) {
        self.days_per_week = Some(days);
        self.exercises_by_day.retain(|day, _| *day <= days);
    }

    pub fn toggle_exercise_for_day(&mut self, day: u8, exercise: SelectedExercise) {
        let day_exercises = self.exercises_by_day.entry(day).or_default();
        if let Some(index) = day_exercises
            .iter()
            .position(|selected| selected.id == exercise.id)
        {
            day_exercises.remove(index);
        } else {
            day_exercises.push(exercise);
        }
    }

    pub fn focus_is_selected(&self, id: i64) -> bool {
        self.focus_muscles.iter().any(|muscle| muscle.id == id)
    }

    pub fn exercise_is_selected(&self, day: u8, id: i64) -> bool {
        self.exercises_by_day
            .get(&day)
            .is_some_and(|exercises| exercises.iter().any(|exercise| exercise.id == id))
    }

    pub fn can_continue(&self, step: TemplateStep) -> bool {
        match step {
            TemplateStep::MuscleFocus => !self.focus_muscles.is_empty(),
            TemplateStep::DaysPerWeek => self.days_per_week.is_some(),
            TemplateStep::ExerciseBuilder => self.exercise_builder_is_valid(),
            TemplateStep::SaveTemplate => self.exercise_builder_is_valid(),
        }
    }

    fn exercise_builder_is_valid(&self) -> bool {
        let Some(days_per_week) = self.days_per_week else {
            return false;
        };

        (1..=days_per_week).all(|day| {
            self.exercises_by_day
                .get(&day)
                .is_some_and(|exercises| !exercises.is_empty())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_required_focus_muscles() {
        let mut state = TemplateFlowState::default();

        assert!(!state.can_continue(TemplateStep::MuscleFocus));

        state.toggle_focus_muscle(FocusMuscle::new(1, "Chest"));

        assert!(state.can_continue(TemplateStep::MuscleFocus));
    }

    #[test]
    fn limits_focus_muscles_to_four() {
        let mut state = TemplateFlowState::default();

        for id in 1..=4 {
            state.toggle_focus_muscle(FocusMuscle::new(id, format!("m{id}")));
        }

        assert_eq!(state.focus_muscle_count(), 4);
        assert!(!state.can_select_more_focus_muscles());
        assert!(!state.can_toggle_focus_muscle(5));

        state.toggle_focus_muscle(FocusMuscle::new(5, "m5"));
        assert_eq!(state.focus_muscle_count(), 4);
        assert!(!state.focus_is_selected(5));
    }

    #[test]
    fn allows_deselecting_focus_muscle_at_limit() {
        let mut state = TemplateFlowState::default();

        for id in 1..=4 {
            state.toggle_focus_muscle(FocusMuscle::new(id, format!("m{id}")));
        }

        assert!(state.can_toggle_focus_muscle(4));
        state.toggle_focus_muscle(FocusMuscle::new(4, "m4"));

        assert_eq!(state.focus_muscle_count(), 3);
        assert!(!state.focus_is_selected(4));
        assert!(state.can_toggle_focus_muscle(5));
    }

    #[test]
    fn validates_required_days_per_week() {
        let mut state = TemplateFlowState::default();

        assert!(!state.can_continue(TemplateStep::DaysPerWeek));

        state.set_days_per_week(4);

        assert!(state.can_continue(TemplateStep::DaysPerWeek));
    }

    #[test]
    fn validates_exercise_selections_for_each_configured_day() {
        let mut state = TemplateFlowState::default();
        state.set_days_per_week(2);

        assert!(!state.can_continue(TemplateStep::ExerciseBuilder));

        state.toggle_exercise_for_day(1, SelectedExercise::new(1, "Bench Press"));
        assert!(!state.can_continue(TemplateStep::ExerciseBuilder));

        state.toggle_exercise_for_day(2, SelectedExercise::new(2, "Squat"));
        assert!(state.can_continue(TemplateStep::ExerciseBuilder));
    }

    #[test]
    fn preserves_state_while_steps_move_back_and_forward() {
        let mut state = TemplateFlowState::default();
        state.toggle_focus_muscle(FocusMuscle::new(1, "Back"));
        state.set_days_per_week(3);
        state.toggle_exercise_for_day(1, SelectedExercise::new(3, "Row"));

        assert_eq!(
            TemplateStep::MuscleFocus.next(),
            Some(TemplateStep::DaysPerWeek)
        );
        assert_eq!(
            TemplateStep::ExerciseBuilder.previous(),
            Some(TemplateStep::DaysPerWeek)
        );
        assert!(state.focus_is_selected(1));
        assert_eq!(state.days_per_week, Some(3));
        assert!(state.exercise_is_selected(1, 3));
    }

    #[test]
    fn selected_template_controls_program_setup() {
        let mut state = TemplateFlowState::default();

        assert!(!state.can_continue_from_template_selection());
        assert!(!state.can_start_selected_template_program());

        state.select_template(SelectedTemplate::new(7, "Base", 3));

        assert!(state.template_is_selected(7));
        assert!(state.can_continue_from_template_selection());
        assert!(!state.can_start_selected_template_program());

        state.set_program_length_weeks(8);

        assert!(state.can_start_selected_template_program());

        state.select_template(SelectedTemplate::new(7, "Base", 3));

        assert!(!state.template_is_selected(7));
        assert_eq!(state.program_length_weeks, None);
    }
}
