import type { AppServices } from "../../../app/AppServices";
import type { AppState } from "../../../domain/app-state/AppState";
import type { AppStateRepository } from "../../../domain/app-state/AppStateRepository";
import type { CompletedSetEvent } from "../../../domain/analytics/TrainingAnalytics";
import type { TrainingAnalyticsRepository } from "../../../domain/analytics/TrainingAnalyticsRepository";
import type { ExerciseSummary, Muscle } from "../../../domain/exercises/Exercise";
import type { ExerciseCatalogRepository } from "../../../domain/exercises/ExerciseCatalogRepository";
import type { Program } from "../../../domain/programs/Program";
import type {
  PersistedProgramScheduleCell,
  ProgramOverviewSnapshot,
} from "../../../domain/programs/ProgramOverview";
import {
  buildProgramSchedule,
  calculateProgramProgress,
  countProgramOverviewSetStatus,
  createProgramOverviewStatusCounts,
} from "../../../domain/programs/ProgramOverview";
import type { ProgramRepository } from "../../../domain/programs/ProgramRepository";
import type { PowerJackStatus } from "../../../domain/status";
import type {
  CompletedTemplateDraft,
  Template,
  TemplateAggregate,
  TemplateSummary,
} from "../../../domain/templates/Template";
import type { TemplateRepository } from "../../../domain/templates/TemplateRepository";
import type {
  ActiveWorkoutLiftView,
  ActiveWorkoutSetView,
  ActiveWorkoutView,
  ActiveWorkoutWeekItem,
  Feedback,
  Lift,
  ManualCheckinStatus,
  Workout,
  WorkoutSet,
} from "../../../domain/workouts/Workout";
import {
  generateNextLiftPrescription,
  maxWorkingSets,
  type ProgressionLiftHistory,
} from "../../../domain/workouts/progression/generateNextLiftPrescription";
import type {
  ManualCheckinDecision,
  WorkoutRepository,
} from "../../../domain/workouts/WorkoutRepository";
import { buildReferenceCatalog } from "../seeds/buildReferenceCatalog";

const deterministicTimestamp = "2026-06-18T00:00:00.000Z";

class InMemoryAppStateRepository implements AppStateRepository {
  private state: AppState = {
    id: 1,
    activeProgramId: null,
    activeWorkoutId: null,
    activeLiftId: null,
    userBodyWeightLb: null,
    userBodyWeightUpdatedLast: null,
    createdAt: deterministicTimestamp,
    updatedAt: deterministicTimestamp,
  };

  load(): Promise<AppState | null> {
    return Promise.resolve(this.state);
  }

  loadSync(): AppState {
    return this.state;
  }

  resetForAgent(): Promise<void> {
    this.state = {
      ...this.state,
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
      userBodyWeightLb: null,
      userBodyWeightUpdatedLast: null,
      updatedAt: deterministicTimestamp,
    };
    return Promise.resolve();
  }

  setActive(programId: number, workoutId: number, liftId: number | null): AppState {
    this.state = {
      ...this.state,
      activeProgramId: programId,
      activeWorkoutId: workoutId,
      activeLiftId: liftId,
      updatedAt: deterministicTimestamp,
    };
    return this.state;
  }

  setActiveLift(liftId: number | null): AppState {
    this.state = {
      ...this.state,
      activeLiftId: liftId,
      updatedAt: deterministicTimestamp,
    };
    return this.state;
  }

  clearActive(): AppState {
    this.state = {
      ...this.state,
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
      updatedAt: deterministicTimestamp,
    };
    return this.state;
  }
}

class InMemoryExerciseCatalogRepository implements ExerciseCatalogRepository {
  private readonly catalog = buildReferenceCatalog();

  listMuscles(): Promise<Muscle[]> {
    return Promise.resolve(this.catalog.muscles);
  }

  searchExercises(query: string): Promise<ExerciseSummary[]> {
    const normalizedQuery = query.toLowerCase();

    const results = this.catalog.exercises
      .filter((exercise) => {
        if (!normalizedQuery) {
          return true;
        }

        return (
          exercise.name.toLowerCase().includes(normalizedQuery) ||
          exercise.primaryMuscleName.toLowerCase().includes(normalizedQuery) ||
          exercise.equipmentName.toLowerCase().includes(normalizedQuery) ||
          exercise.secondaryMuscleNames.some((muscle) => muscle.toLowerCase().includes(normalizedQuery))
        );
      })
      .slice(0, 40);

    return Promise.resolve(results);
  }
}

class InMemoryTemplateRepository implements TemplateRepository {
  private readonly catalog = buildReferenceCatalog();
  private templates: TemplateSummary[] = [];
  private templateDetails = new Map<number, Template>();
  private templateAggregates = new Map<number, TemplateAggregate>();
  private deletedTemplateIds = new Set<number>();
  private activeTemplateChecker: (templateId: number) => boolean = () => false;
  private nextId = 1;

  list(): Promise<TemplateSummary[]> {
    return Promise.resolve(
      this.templates
        .filter((template) => !this.deletedTemplateIds.has(template.id))
        .map((template) => ({
          ...template,
          usedByActiveProgram: this.activeTemplateChecker(template.id),
        })),
    );
  }

  findById(id: number): Promise<Template | null> {
    if (this.deletedTemplateIds.has(id)) {
      return Promise.resolve(null);
    }

    const template = this.templates.find((item) => item.id === id);

    if (!template) {
      return Promise.resolve(null);
    }

    return Promise.resolve({
      id: template.id,
      name: template.name,
      workoutsPerWeek: template.workoutsPerWeek,
      focusMuscleIds: this.templateDetails.get(id)?.focusMuscleIds ?? [],
      createdAt: template.createdAt,
      updatedAt: template.updatedAt,
    });
  }

  loadAggregate(id: number): Promise<TemplateAggregate | null> {
    if (this.deletedTemplateIds.has(id)) {
      return Promise.resolve(null);
    }

    const aggregate = this.templateAggregates.get(id);
    return Promise.resolve(aggregate ? cloneTemplateAggregate(aggregate) : null);
  }

  save(draft: CompletedTemplateDraft): Promise<TemplateSummary> {
    const timestamp = deterministicTimestamp;
    const summary: TemplateSummary = {
      id: this.nextId,
      name: draft.name,
      workoutsPerWeek: draft.workoutsPerWeek,
      exerciseCount: draft.days.reduce((total, day) => total + day.exerciseIds.length, 0),
      focusMuscles: draft.focusMuscleIds
        .map((id) => this.catalog.muscles.find((muscle) => muscle.id === id))
        .filter((muscle): muscle is NonNullable<typeof muscle> => Boolean(muscle))
        .map((muscle) => ({ id: muscle.id, name: muscle.name })),
      usedByActiveProgram: false,
      createdAt: timestamp,
      updatedAt: timestamp,
    };

    this.nextId += 1;
    this.templates = [summary, ...this.templates];
    this.templateDetails.set(summary.id, {
      id: summary.id,
      name: summary.name,
      workoutsPerWeek: summary.workoutsPerWeek,
      focusMuscleIds: [...draft.focusMuscleIds],
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    this.templateAggregates.set(summary.id, {
      id: summary.id,
      name: summary.name,
      workoutsPerWeek: summary.workoutsPerWeek,
      focusMuscleIds: [...draft.focusMuscleIds],
      days: draft.days.map((day) => ({
        id: summary.id * 100 + day.order,
        order: day.order,
        exerciseIds: [...day.exerciseIds],
      })),
    });
    return Promise.resolve(summary);
  }

  update(id: number, draft: CompletedTemplateDraft): Promise<TemplateSummary> {
    const existing = this.templates.find((template) => template.id === id);

    if (!existing || this.deletedTemplateIds.has(id)) {
      return Promise.reject(new Error("Template could not be loaded."));
    }

    const summary: TemplateSummary = {
      ...existing,
      name: draft.name,
      workoutsPerWeek: draft.workoutsPerWeek,
      exerciseCount: draft.days.reduce((total, day) => total + day.exerciseIds.length, 0),
      focusMuscles: draft.focusMuscleIds
        .map((muscleId) => this.catalog.muscles.find((muscle) => muscle.id === muscleId))
        .filter((muscle): muscle is NonNullable<typeof muscle> => Boolean(muscle))
        .map((muscle) => ({ id: muscle.id, name: muscle.name })),
      usedByActiveProgram: this.activeTemplateChecker(id),
      updatedAt: deterministicTimestamp,
    };

    this.templates = [summary, ...this.templates.filter((template) => template.id !== id)];
    this.templateDetails.set(id, {
      id,
      name: summary.name,
      workoutsPerWeek: summary.workoutsPerWeek,
      focusMuscleIds: [...draft.focusMuscleIds],
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
    });
    this.templateAggregates.set(id, {
      id,
      name: summary.name,
      workoutsPerWeek: summary.workoutsPerWeek,
      focusMuscleIds: [...draft.focusMuscleIds],
      days: draft.days.map((day) => ({
        id: id * 100 + day.order,
        order: day.order,
        exerciseIds: [...day.exerciseIds],
      })),
    });

    return Promise.resolve(summary);
  }

  softDelete(id: number): Promise<void> {
    this.deletedTemplateIds.add(id);
    return Promise.resolve();
  }

  isUsedByActiveProgram(id: number): Promise<boolean> {
    return Promise.resolve(this.activeTemplateChecker(id));
  }

  replaceExerciseInTemplateDay(input: {
    templateId: number;
    workoutDay: number;
    liftOrder: number;
    exerciseId: number;
  }): void {
    const aggregate = this.templateAggregates.get(input.templateId);
    const summary = this.templates.find((template) => template.id === input.templateId);

    if (!aggregate || !summary || this.deletedTemplateIds.has(input.templateId)) {
      throw new Error("Lift template was not found.");
    }

    const day = aggregate.days.find((item) => item.order === input.workoutDay);

    if (!day || input.liftOrder < 1 || input.liftOrder > day.exerciseIds.length) {
      throw new Error("Lift template was not found.");
    }

    day.exerciseIds[input.liftOrder - 1] = input.exerciseId;
    summary.updatedAt = deterministicTimestamp;
    const detail = this.templateDetails.get(input.templateId);

    if (detail) {
      detail.updatedAt = deterministicTimestamp;
    }
  }

  setActiveTemplateChecker(activeTemplateChecker: (templateId: number) => boolean): void {
    this.activeTemplateChecker = activeTemplateChecker;
  }

  reset(): void {
    this.templates = [];
    this.templateDetails.clear();
    this.templateAggregates.clear();
    this.deletedTemplateIds.clear();
    this.nextId = 1;
  }
}

class InMemoryTrainingRepository implements ProgramRepository, WorkoutRepository, TrainingAnalyticsRepository {
  private readonly catalog = buildReferenceCatalog();
  private programs: Program[] = [];
  private workouts: Workout[] = [];
  private lifts: Lift[] = [];
  private sets: WorkoutSet[] = [];
  private feedback: Feedback[] = [];
  private nextProgramId = 1;
  private nextWorkoutId = 1;
  private nextLiftId = 1;
  private nextSetId = 1;
  private nextFeedbackId = 1;

  constructor(
    private readonly appState: InMemoryAppStateRepository,
    private readonly templates: InMemoryTemplateRepository,
  ) {}

  async loadOverview(programId: number): Promise<ProgramOverviewSnapshot | null> {
    const program = this.programs.find((item) => item.id === programId);

    if (!program) {
      return null;
    }

    const template = await this.templates.loadAggregate(program.templateId);

    if (!template) {
      return null;
    }

    const persistedCells: PersistedProgramScheduleCell[] = this.workouts
      .filter((workout) => workout.programId === program.id)
      .map((workout) => {
        let statusCounts = createProgramOverviewStatusCounts();
        const sets = this.getSetsForWorkout(workout.id);

        for (const set of sets) {
          statusCounts = countProgramOverviewSetStatus(statusCounts, set.status);
        }

        return {
          workoutId: workout.id,
          week: workout.programWeek,
          day: workout.workoutDay,
          totalSets: sets.length,
          statusCounts,
        };
      });
    const schedule = buildProgramSchedule({
      programLengthWeeks: program.programLengthWeeks,
      workoutsPerWeek: template.workoutsPerWeek,
      persistedCells,
      plannedSetCountsByDay: new Map(
        template.days.map((day) => [day.order, day.exerciseIds.length * 2] as const),
      ),
    });
    const progress = calculateProgramProgress(schedule);

    return {
      program: {
        id: program.id,
        name: program.name,
        status: program.status,
        locked: program.locked,
        templateId: program.templateId,
        templateName: template.name,
        programLengthWeeks: program.programLengthWeeks,
        workoutsPerWeek: template.workoutsPerWeek,
        focusMuscles: template.focusMuscleIds
          .map((muscleId) => this.catalog.muscles.find((muscle) => muscle.id === muscleId))
          .filter((muscle): muscle is NonNullable<typeof muscle> => Boolean(muscle))
          .map((muscle) => ({ id: muscle.id, name: muscle.name })),
        completedSets: progress.completedSets,
        totalSets: progress.totalSets,
        progressPercent: progress.progressPercent,
      },
      schedule,
    };
  }

  async startFromTemplate(input: {
    template: TemplateAggregate;
    programLengthWeeks: number;
    replaceActiveProgram?: boolean;
  }): Promise<AppState> {
    const currentAppState = await this.appState.load();

    if (currentAppState?.activeProgramId && !input.replaceActiveProgram) {
      throw new Error("An active program already exists.");
    }

    if (currentAppState?.activeProgramId && input.replaceActiveProgram) {
      this.haltActiveProgram(currentAppState.activeProgramId);
    }

    const usageCount = this.programs.filter((program) => program.templateId === input.template.id).length + 1;
    const program: Program = {
      id: this.nextProgramId,
      name: `${input.template.name} x${usageCount}`,
      programLengthWeeks: input.programLengthWeeks,
      status: "active",
      locked: false,
      templateId: input.template.id,
      createdAt: deterministicTimestamp,
      updatedAt: deterministicTimestamp,
    };
    this.nextProgramId += 1;
    this.programs.push(program);

    let activeWorkoutId: number | null = null;
    let activeLiftId: number | null = null;

    for (const day of input.template.days) {
      const isActiveDay = day.order === 1;
      const workout = this.createWorkout({
        programId: program.id,
        programWeek: 1,
        workoutDay: day.order,
        status: isActiveDay ? "active" : "planned",
        locked: !isActiveDay,
      });

      if (isActiveDay) {
        activeWorkoutId = workout.id;
      }

      for (const [exerciseIndex, exerciseId] of day.exerciseIds.entries()) {
        const lift = this.createLift({
          workoutId: workout.id,
          exerciseId,
          order: exerciseIndex + 1,
          status: isActiveDay ? "active" : "planned",
          locked: !isActiveDay,
        });

        if (isActiveDay && activeLiftId === null) {
          activeLiftId = lift.id;
        }

        for (let setOrder = 1; setOrder <= 2; setOrder += 1) {
          this.createSet({
            liftId: lift.id,
            order: setOrder,
            status: isActiveDay ? "active" : "planned",
            locked: !isActiveDay,
            plannedReps: null,
            plannedWeight: null,
          });
        }
      }
    }

    if (!activeWorkoutId) {
      throw new Error("Template did not create an active workout.");
    }

    return this.appState.setActive(program.id, activeWorkoutId, activeLiftId);
  }

  isTemplateUsedByActiveProgram(templateId: number): boolean {
    const activeProgramId = this.appState.loadSync().activeProgramId;
    const activeProgram = this.programs.find((program) => program.id === activeProgramId);
    return Boolean(activeProgram && activeProgram.status === "active" && activeProgram.templateId === templateId);
  }

  async loadActive(): Promise<ActiveWorkoutView | null> {
    const state = await this.appState.load();
    return state?.activeWorkoutId ? this.loadWorkoutView(state.activeWorkoutId) : null;
  }

  loadWorkoutView(workoutId: number): Promise<ActiveWorkoutView | null> {
    const workout = this.workouts.find((item) => item.id === workoutId);

    if (!workout) {
      return Promise.resolve(null);
    }

    const program = this.programs.find((item) => item.id === workout.programId);

    if (!program) {
      return Promise.resolve(null);
    }

    const weekWorkouts = this.workouts
      .filter((item) => item.programId === program.id && item.programWeek === workout.programWeek)
      .sort((left, right) => left.workoutDay - right.workoutDay)
      .map(
        (item): ActiveWorkoutWeekItem => ({
          id: item.id,
          workoutDay: item.workoutDay,
          status: item.status,
          locked: item.locked,
        }),
      );
    const currentWeekIndex = weekWorkouts.findIndex((item) => item.id === workout.id);
    const lifts = this.buildLiftViews(workout.id);
    const countableSets = lifts.flatMap((lift) => lift.sets).filter((set) => set.status !== "skipped");
    const completedCountableSets = countableSets.filter((set) => set.status === "complete");

    return Promise.resolve({
      program,
      workout,
      weekWorkouts,
      previousWorkoutId:
        currentWeekIndex > 0 ? weekWorkouts[currentWeekIndex - 1]?.id ?? null : null,
      nextWorkoutId:
        currentWeekIndex >= 0 && currentWeekIndex < weekWorkouts.length - 1
          ? weekWorkouts[currentWeekIndex + 1]?.id ?? null
          : null,
      completedSets: completedCountableSets.length,
      totalSets: countableSets.length,
      canFinish:
        workout.status === "active" &&
        !workout.locked &&
        lifts.length > 0 &&
        completedCountableSets.length === countableSets.length &&
        lifts.every((lift) => lift.status === "skipped" || (lift.status === "complete" && lift.feedbackSubmitted)),
      isReadOnly: workout.locked || workout.status !== "active",
      lifts,
    });
  }

  async updateSetActuals(input: {
    setId: number;
    actualReps: number | null;
    actualWeight: number | null;
  }): Promise<ActiveWorkoutView> {
    const set = this.sets.find((item) => item.id === input.setId);

    if (!set) {
      throw new Error("Workout set was not found.");
    }

    const lift = this.lifts.find((item) => item.id === set.liftId);
    const workout = lift ? this.workouts.find((item) => item.id === lift.workoutId) : null;

    if (!lift || !workout) {
      throw new Error("Workout could not be loaded.");
    }

    if (set.locked || workout.locked || workout.status !== "active") {
      throw new Error("This set is locked.");
    }

    const repsOnly = this.isRepsOnlyExercise(lift.exerciseId);
    set.actualReps = input.actualReps;
    set.actualWeight = repsOnly ? null : input.actualWeight;
    set.status = input.actualReps !== null && (repsOnly || set.actualWeight !== null) ? "complete" : "active";
    set.updatedAt = deterministicTimestamp;

    const liftSets = this.sets.filter((item) => item.liftId === lift.id);
    lift.status = liftSets.every((item) => item.status === "complete" || item.status === "skipped")
      ? "complete"
      : "active";
    lift.updatedAt = deterministicTimestamp;
    this.appState.setActiveLift(lift.id);

    const view = await this.loadWorkoutView(workout.id);

    if (!view) {
      throw new Error("Workout could not be loaded after set update.");
    }

    return view;
  }

  async addSetToLift(input: { liftId: number }): Promise<ActiveWorkoutView> {
    const { lift, workout } = this.requireEditableLift(input.liftId);
    const liftSets = this.sets.filter((item) => item.liftId === lift.id);

    if (liftSets.length >= maxWorkingSets) {
      throw new Error(`A lift can have at most ${maxWorkingSets} sets.`);
    }

    const nextOrder = liftSets.reduce((maxOrder, set) => Math.max(maxOrder, set.order), 0) + 1;
    this.createSet({
      liftId: lift.id,
      order: nextOrder,
      status: "active",
      locked: false,
      plannedReps: null,
      plannedWeight: null,
    });
    lift.status = "active";
    lift.updatedAt = deterministicTimestamp;
    this.appState.setActiveLift(lift.id);

    const view = await this.loadWorkoutView(workout.id);

    if (!view) {
      throw new Error("Workout could not be loaded after set add.");
    }

    return view;
  }

  async removeLastSetFromLift(input: { liftId: number }): Promise<ActiveWorkoutView> {
    const { lift, workout } = this.requireEditableLift(input.liftId);
    const liftSets = this.sets
      .filter((item) => item.liftId === lift.id)
      .sort((left, right) => left.order - right.order);

    if (liftSets.length <= 1) {
      throw new Error("A lift must have at least one set.");
    }

    const lastSet = liftSets[liftSets.length - 1];

    if (!lastSet) {
      throw new Error("Workout set was not found.");
    }

    this.sets = this.sets.filter((set) => set.id !== lastSet.id);
    this.refreshLiftStatusFromSets(lift.id);
    this.appState.setActiveLift(lift.id);

    const view = await this.loadWorkoutView(workout.id);

    if (!view) {
      throw new Error("Workout could not be loaded after set removal.");
    }

    return view;
  }

  async changeLiftExercise(input: {
    liftId: number;
    exerciseId: number;
  }): Promise<ActiveWorkoutView> {
    const { lift, workout, program } = this.requireEditableLift(input.liftId);

    if (!this.catalog.exercises.some((exercise) => exercise.id === input.exerciseId)) {
      throw new Error("Exercise was not found.");
    }

    if (lift.exerciseId === input.exerciseId) {
      const view = await this.loadWorkoutView(workout.id);

      if (!view) {
        throw new Error("Workout could not be loaded after exercise change.");
      }

      return view;
    }

    this.templates.replaceExerciseInTemplateDay({
      templateId: program.templateId,
      workoutDay: workout.workoutDay,
      liftOrder: lift.order,
      exerciseId: input.exerciseId,
    });
    this.feedback = this.feedback.filter((feedback) => feedback.liftId !== lift.id);
    this.sets = this.sets.filter((set) => set.liftId !== lift.id);
    lift.exerciseId = input.exerciseId;
    lift.status = "active";
    lift.locked = false;
    lift.manualCheckinStatus = "none";
    lift.manualCheckinSourceLiftId = null;
    lift.updatedAt = deterministicTimestamp;

    for (let setOrder = 1; setOrder <= 2; setOrder += 1) {
      this.createSet({
        liftId: lift.id,
        order: setOrder,
        status: "active",
        locked: false,
        plannedReps: null,
        plannedWeight: null,
      });
    }

    this.appState.setActiveLift(lift.id);
    const view = await this.loadWorkoutView(workout.id);

    if (!view) {
      throw new Error("Workout could not be loaded after exercise change.");
    }

    return view;
  }

  async submitLiftFeedback(input: {
    liftId: number;
    levelOfPain: number;
    levelOfEffort: number;
  }): Promise<ActiveWorkoutView> {
    validatePainValue(input.levelOfPain);
    validateEffortValue(input.levelOfEffort);

    const lift = this.lifts.find((item) => item.id === input.liftId);
    const workout = lift ? this.workouts.find((item) => item.id === lift.workoutId) : null;

    if (!lift || !workout) {
      throw new Error("Lift was not found.");
    }

    if (lift.locked || workout.locked || workout.status !== "active") {
      throw new Error("This lift is locked.");
    }

    if (lift.status !== "complete") {
      throw new Error("Complete this lift before saving feedback.");
    }

    const existingFeedback = this.feedback.find((item) => item.liftId === lift.id);

    if (!existingFeedback) {
      this.feedback.push({
        id: this.nextFeedbackId,
        levelOfPain: input.levelOfPain,
        levelOfEffort: input.levelOfEffort,
        liftId: lift.id,
        createdAt: deterministicTimestamp,
        updatedAt: deterministicTimestamp,
      });
      this.nextFeedbackId += 1;
    }

    const view = await this.loadWorkoutView(workout.id);

    if (!view) {
      throw new Error("Workout could not be loaded after feedback.");
    }

    return view;
  }

  async resolveManualCheckIn(input: {
    liftId: number;
    decision: ManualCheckinDecision;
  }): Promise<ActiveWorkoutView> {
    const lift = this.lifts.find((item) => item.id === input.liftId);
    const workout = lift ? this.workouts.find((item) => item.id === lift.workoutId) : null;

    if (!lift || !workout) {
      throw new Error("Lift was not found.");
    }

    if (workout.locked || workout.status !== "active") {
      throw new Error("This workout is locked.");
    }

    if (lift.manualCheckinStatus !== "pending") {
      throw new Error("This lift does not need a manual check-in.");
    }

    if (input.decision === "skip") {
      lift.status = "skipped";
      lift.locked = true;
      lift.manualCheckinStatus = "resolved";
      lift.updatedAt = deterministicTimestamp;

      for (const set of this.sets.filter((item) => item.liftId === lift.id)) {
        set.actualReps = null;
        set.actualWeight = null;
        set.status = "skipped";
        set.locked = true;
        set.updatedAt = deterministicTimestamp;
      }

      const view = await this.loadWorkoutView(workout.id);

      if (!view) {
        throw new Error("Workout could not be loaded after manual check-in.");
      }

      return view;
    }

    if (input.decision === "reset") {
      this.sets = this.sets.filter((set) => set.liftId !== lift.id);

      for (let setOrder = 1; setOrder <= 2; setOrder += 1) {
        this.createSet({
          liftId: lift.id,
          order: setOrder,
          status: "active",
          locked: false,
          plannedReps: null,
          plannedWeight: null,
        });
      }
    } else if (input.decision !== "continue") {
      throw new Error("Choose a manual check-in option.");
    }

    lift.status = "active";
    lift.locked = false;
    lift.manualCheckinStatus = "resolved";
    lift.updatedAt = deterministicTimestamp;

    for (const set of this.sets.filter((item) => item.liftId === lift.id)) {
      set.status = "active";
      set.locked = false;
      set.updatedAt = deterministicTimestamp;
    }

    this.appState.setActiveLift(lift.id);
    const view = await this.loadWorkoutView(workout.id);

    if (!view) {
      throw new Error("Workout could not be loaded after manual check-in.");
    }

    return view;
  }

  async finishWorkout(workoutId: number): Promise<ActiveWorkoutView | null> {
    const workout = this.workouts.find((item) => item.id === workoutId);

    if (!workout) {
      throw new Error("Workout was not found.");
    }

    const program = this.programs.find((item) => item.id === workout.programId);

    if (!program) {
      throw new Error("Program was not found.");
    }

    if (workout.locked) {
      throw new Error("This workout is locked.");
    }

    const workoutSets = this.getSetsForWorkout(workout.id);

    if (workoutSets.some((set) => set.status !== "complete" && set.status !== "skipped")) {
      throw new Error("Complete every set before finishing the workout.");
    }

    const completedLifts = this.lifts.filter(
      (lift) => lift.workoutId === workout.id && lift.status === "complete",
    );
    const hasMissingFeedback = completedLifts.some(
      (lift) => !this.feedback.some((feedback) => feedback.liftId === lift.id),
    );

    if (hasMissingFeedback) {
      throw new Error("Submit feedback for every completed lift before finishing the workout.");
    }

    this.lockCompletedWorkout(workout.id);

    let nextWorkout = this.workouts
      .filter(
        (item) =>
          item.programId === program.id &&
          item.programWeek === workout.programWeek &&
          item.workoutDay > workout.workoutDay,
      )
      .sort((left, right) => left.workoutDay - right.workoutDay)[0];

    if (!nextWorkout && workout.programWeek < program.programLengthWeeks) {
      const nextWeek = workout.programWeek + 1;
      const nextWeekExists = this.workouts.some(
        (item) => item.programId === program.id && item.programWeek === nextWeek,
      );

      if (!nextWeekExists) {
        await this.createProgramWeek(program, nextWeek);
      }

      nextWorkout = this.workouts
        .filter((item) => item.programId === program.id && item.programWeek === nextWeek)
        .sort((left, right) => left.workoutDay - right.workoutDay)[0];
    }

    if (!nextWorkout) {
      program.status = "complete";
      program.locked = true;
      program.updatedAt = deterministicTimestamp;
      this.appState.clearActive();
      return null;
    }

    this.activateWorkout(nextWorkout.id);
    return this.loadWorkoutView(nextWorkout.id);
  }

  loadCompletedSetEvents(input: {
    fromInclusive: string;
    toExclusive: string;
  }): Promise<CompletedSetEvent[]> {
    const from = new Date(input.fromInclusive);
    const to = new Date(input.toExclusive);

    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
      return Promise.reject(new Error("Invalid analytics date range."));
    }

    const completedEvents = this.sets
      .filter((set) => {
        const completedAt = new Date(set.updatedAt);
        return (
          set.status === "complete" &&
          set.actualReps !== null &&
          completedAt >= from &&
          completedAt < to
        );
      })
      .flatMap((set): CompletedSetEvent[] => {
        const lift = this.lifts.find((item) => item.id === set.liftId);
        const exercise = lift ? this.catalog.exercises.find((item) => item.id === lift.exerciseId) : null;
        const muscle = exercise
          ? this.catalog.muscles.find((item) => item.name === exercise.primaryMuscleName)
          : null;

        if (!lift || !exercise || !muscle) {
          return [];
        }

        return [
          {
            setId: set.id,
            muscleId: muscle.id,
            muscleName: muscle.name,
            completedAt: set.updatedAt,
          },
        ];
      });

    return Promise.resolve(completedEvents);
  }

  loadCompletedSetEventsForProgram(programId: number): Promise<CompletedSetEvent[]> {
    const completedEvents = this.sets
      .filter((set) => {
        const lift = this.lifts.find((item) => item.id === set.liftId);
        const workout = lift ? this.workouts.find((item) => item.id === lift.workoutId) : null;

        return (
          workout?.programId === programId &&
          set.status === "complete" &&
          set.actualReps !== null &&
          set.actualWeight !== null
        );
      })
      .flatMap((set): CompletedSetEvent[] => {
        const lift = this.lifts.find((item) => item.id === set.liftId);
        const exercise = lift ? this.catalog.exercises.find((item) => item.id === lift.exerciseId) : null;
        const muscle = exercise
          ? this.catalog.muscles.find((item) => item.name === exercise.primaryMuscleName)
          : null;

        if (!lift || !exercise || !muscle) {
          return [];
        }

        return [
          {
            setId: set.id,
            muscleId: muscle.id,
            muscleName: muscle.name,
            completedAt: set.updatedAt,
          },
        ];
      });

    return Promise.resolve(completedEvents);
  }

  reset(): void {
    this.programs = [];
    this.workouts = [];
    this.lifts = [];
    this.sets = [];
    this.feedback = [];
    this.nextProgramId = 1;
    this.nextWorkoutId = 1;
    this.nextLiftId = 1;
    this.nextSetId = 1;
    this.nextFeedbackId = 1;
  }

  private haltActiveProgram(programId: number): void {
    const program = this.programs.find((item) => item.id === programId);

    if (program) {
      program.status = "halted";
      program.locked = true;
      program.updatedAt = deterministicTimestamp;
    }

    for (const workout of this.workouts.filter((item) => item.programId === programId)) {
      if (workout.status !== "complete") {
        workout.status = "halted";
      }
      workout.locked = true;
      workout.updatedAt = deterministicTimestamp;

      for (const lift of this.lifts.filter((item) => item.workoutId === workout.id)) {
        if (lift.status !== "complete") {
          lift.status = "halted";
        }
        lift.locked = true;
        lift.updatedAt = deterministicTimestamp;

        for (const set of this.sets.filter((item) => item.liftId === lift.id)) {
          if (set.status !== "complete") {
            set.status = "halted";
          }
          set.locked = true;
          set.updatedAt = deterministicTimestamp;
        }
      }
    }
  }

  private createWorkout(input: {
    programId: number;
    programWeek: number;
    workoutDay: number;
    status: PowerJackStatus;
    locked: boolean;
  }): Workout {
    const workout: Workout = {
      id: this.nextWorkoutId,
      order: input.workoutDay,
      workoutDay: input.workoutDay,
      programWeek: input.programWeek,
      hidden: false,
      locked: input.locked,
      status: input.status,
      programId: input.programId,
      createdAt: deterministicTimestamp,
      updatedAt: deterministicTimestamp,
    };
    this.nextWorkoutId += 1;
    this.workouts.push(workout);
    return workout;
  }

  private createLift(input: {
    workoutId: number;
    exerciseId: number;
    order: number;
    status: PowerJackStatus;
    locked: boolean;
    manualCheckinStatus?: ManualCheckinStatus;
    manualCheckinSourceLiftId?: number | null;
  }): Lift {
    const lift: Lift = {
      id: this.nextLiftId,
      exerciseId: input.exerciseId,
      workoutId: input.workoutId,
      locked: input.locked,
      hidden: false,
      order: input.order,
      status: input.status,
      planned: true,
      manualCheckinStatus: input.manualCheckinStatus ?? "none",
      manualCheckinSourceLiftId: input.manualCheckinSourceLiftId ?? null,
      createdAt: deterministicTimestamp,
      updatedAt: deterministicTimestamp,
    };
    this.nextLiftId += 1;
    this.lifts.push(lift);
    return lift;
  }

  private createSet(input: {
    liftId: number;
    order: number;
    status: PowerJackStatus;
    locked: boolean;
    plannedReps: number | null;
    plannedWeight: number | null;
  }): WorkoutSet {
    const set: WorkoutSet = {
      id: this.nextSetId,
      plannedReps: input.plannedReps,
      actualReps: null,
      plannedWeight: input.plannedWeight,
      actualWeight: null,
      order: input.order,
      liftId: input.liftId,
      locked: input.locked,
      hidden: false,
      status: input.status,
      planned: true,
      createdAt: deterministicTimestamp,
      updatedAt: deterministicTimestamp,
    };
    this.nextSetId += 1;
    this.sets.push(set);
    return set;
  }

  private buildLiftViews(workoutId: number): ActiveWorkoutLiftView[] {
    return this.lifts
      .filter((lift) => lift.workoutId === workoutId)
      .sort((left, right) => left.order - right.order)
      .map((lift) => ({
        id: lift.id,
        exerciseId: lift.exerciseId,
        exerciseName: this.exerciseName(lift.exerciseId),
        repsOnly: this.isRepsOnlyExercise(lift.exerciseId),
        order: lift.order,
        status: lift.status,
        locked: lift.locked,
        feedbackSubmitted: this.feedback.some((feedback) => feedback.liftId === lift.id),
        manualCheckinStatus: lift.manualCheckinStatus,
        manualCheckinSourceLiftId: lift.manualCheckinSourceLiftId,
        manualCheckinSourcePain: this.feedback.find(
          (feedback) => feedback.liftId === lift.manualCheckinSourceLiftId,
        )?.levelOfPain ?? null,
        sets: this.sets
          .filter((set) => set.liftId === lift.id)
          .sort((left, right) => left.order - right.order)
          .map(
            (set): ActiveWorkoutSetView => ({
              id: set.id,
              order: set.order,
              plannedReps: set.plannedReps,
              actualReps: set.actualReps,
              plannedWeight: set.plannedWeight,
              actualWeight: set.actualWeight,
              status: set.status,
              locked: set.locked,
            }),
          ),
      }));
  }

  private exerciseName(exerciseId: number): string {
    return this.catalog.exercises.find((exercise) => exercise.id === exerciseId)?.name ?? "Exercise";
  }

  private isRepsOnlyExercise(exerciseId: number): boolean {
    return this.catalog.exercises.find((exercise) => exercise.id === exerciseId)?.repsOnly ?? false;
  }

  private getSetsForWorkout(workoutId: number): WorkoutSet[] {
    const liftIds = new Set(this.lifts.filter((lift) => lift.workoutId === workoutId).map((lift) => lift.id));
    return this.sets.filter((set) => liftIds.has(set.liftId));
  }

  private requireEditableLift(liftId: number): {
    lift: Lift;
    workout: Workout;
    program: Program;
  } {
    const lift = this.lifts.find((item) => item.id === liftId);
    const workout = lift ? this.workouts.find((item) => item.id === lift.workoutId) : null;
    const program = workout ? this.programs.find((item) => item.id === workout.programId) : null;

    if (!lift || !workout || !program) {
      throw new Error("Lift was not found.");
    }

    if (lift.locked || workout.locked || workout.status !== "active") {
      throw new Error("This lift is locked.");
    }

    if (lift.manualCheckinStatus === "pending") {
      throw new Error("Resolve manual check-in before editing this lift.");
    }

    if (this.lifts.some((item) => item.workoutId === workout.id && item.manualCheckinStatus === "pending")) {
      throw new Error("Resolve manual check-in before editing this workout.");
    }

    return { lift, workout, program };
  }

  private refreshLiftStatusFromSets(liftId: number): void {
    const lift = this.lifts.find((item) => item.id === liftId);

    if (!lift) {
      throw new Error("Lift was not found.");
    }

    const liftSets = this.sets.filter((set) => set.liftId === liftId);
    lift.status = liftSets.every((set) => set.status === "complete" || set.status === "skipped")
      ? "complete"
      : "active";
    lift.updatedAt = deterministicTimestamp;
  }

  private lockCompletedWorkout(workoutId: number): void {
    const workout = this.workouts.find((item) => item.id === workoutId);

    if (workout) {
      workout.status = "complete";
      workout.locked = true;
      workout.updatedAt = deterministicTimestamp;
    }

    for (const lift of this.lifts.filter((item) => item.workoutId === workoutId)) {
      lift.status = lift.status === "skipped" ? "skipped" : "complete";
      lift.locked = true;
      lift.updatedAt = deterministicTimestamp;

      for (const set of this.sets.filter((item) => item.liftId === lift.id)) {
        set.status = set.status === "skipped" ? "skipped" : "complete";
        set.locked = true;
        set.updatedAt = deterministicTimestamp;
      }
    }
  }

  private activateWorkout(workoutId: number): void {
    const workout = this.workouts.find((item) => item.id === workoutId);

    if (!workout) {
      throw new Error("Workout was not found.");
    }

    workout.status = "active";
    workout.locked = false;
    workout.hidden = false;
    workout.updatedAt = deterministicTimestamp;

    let activeLiftId: number | null = null;

    for (const lift of this.lifts.filter((item) => item.workoutId === workoutId)) {
      lift.status = "active";
      lift.locked = lift.manualCheckinStatus === "pending";
      lift.hidden = false;
      lift.updatedAt = deterministicTimestamp;

      if (activeLiftId === null) {
        activeLiftId = lift.id;
      }

      for (const set of this.sets.filter((item) => item.liftId === lift.id)) {
        set.status = "active";
        set.locked = lift.manualCheckinStatus === "pending";
        set.hidden = false;
        set.updatedAt = deterministicTimestamp;
      }
    }

    this.appState.setActive(workout.programId, workout.id, activeLiftId);
  }

  private async createProgramWeek(program: Program, programWeek: number): Promise<void> {
    const template = await this.templates.loadAggregate(program.templateId);

    if (!template) {
      throw new Error("Program template could not be loaded.");
    }

    for (const day of template.days) {
      const workout = this.createWorkout({
        programId: program.id,
        programWeek,
        workoutDay: day.order,
        status: "planned",
        locked: true,
      });

      for (const [exerciseIndex, exerciseId] of day.exerciseIds.entries()) {
        const prescription = this.nextLiftPrescription({
          program,
          programWeek,
          workoutDay: day.order,
          liftOrder: exerciseIndex + 1,
          exerciseId,
          focusMuscleIds: template.focusMuscleIds,
        });
        const manualCheckinStatus: ManualCheckinStatus = prescription.manualCheckinSourceLiftId
          ? "pending"
          : "none";
        const lift = this.createLift({
          workoutId: workout.id,
          exerciseId,
          order: exerciseIndex + 1,
          status: "planned",
          locked: true,
          manualCheckinStatus,
          manualCheckinSourceLiftId: prescription.manualCheckinSourceLiftId,
        });

        for (const setPlan of prescription.sets) {
          this.createSet({
            liftId: lift.id,
            order: setPlan.order,
            status: "planned",
            locked: true,
            plannedReps: setPlan.plannedReps,
            plannedWeight: setPlan.plannedWeight,
          });
        }
      }
    }
  }

  private nextLiftPrescription(input: {
    program: Program;
    programWeek: number;
    workoutDay: number;
    liftOrder: number;
    exerciseId: number;
    focusMuscleIds: number[];
  }) {
    const current = this.liftHistory({
      programId: input.program.id,
      programWeek: input.programWeek - 1,
      workoutDay: input.workoutDay,
      liftOrder: input.liftOrder,
      exerciseId: input.exerciseId,
    });

    if (!current) {
      throw new Error("Previous lift could not be loaded for progression.");
    }

    const exercise = this.catalog.exercises.find((item) => item.id === input.exerciseId);

    if (!exercise) {
      throw new Error("Exercise could not be loaded for progression.");
    }

    const primaryMuscle = this.catalog.muscles.find((muscle) => muscle.name === exercise.primaryMuscleName);

    if (!primaryMuscle) {
      throw new Error("Exercise primary muscle could not be loaded for progression.");
    }

    return generateNextLiftPrescription({
      current,
      previous: this.liftHistory({
        programId: input.program.id,
        programWeek: input.programWeek - 2,
        workoutDay: input.workoutDay,
        liftOrder: input.liftOrder,
        exerciseId: input.exerciseId,
      }),
      twoWeeksAgo: this.liftHistory({
        programId: input.program.id,
        programWeek: input.programWeek - 3,
        workoutDay: input.workoutDay,
        liftOrder: input.liftOrder,
        exerciseId: input.exerciseId,
      }),
      exercise: {
        primaryMuscleId: primaryMuscle.id,
        minRepsHypertrophy: exercise.minRepsHypertrophy,
        maxRepsHypertrophy: exercise.maxRepsHypertrophy,
        repsOnly: exercise.repsOnly,
      },
      focusMuscleIds: input.focusMuscleIds,
      programLengthWeeks: input.program.programLengthWeeks,
    });
  }

  private liftHistory(input: {
    programId: number;
    programWeek: number;
    workoutDay: number;
    liftOrder: number;
    exerciseId: number;
  }): ProgressionLiftHistory | null {
    if (input.programWeek < 1) {
      return null;
    }

    const previousWorkout = this.workouts.find(
      (workout) =>
        workout.programId === input.programId &&
        workout.programWeek === input.programWeek &&
        workout.workoutDay === input.workoutDay,
    );

    if (!previousWorkout) {
      return null;
    }

    const previousLift = this.lifts.find(
      (lift) =>
        lift.workoutId === previousWorkout.id &&
        lift.order === input.liftOrder &&
        lift.exerciseId === input.exerciseId,
    );

    if (!previousLift) {
      return null;
    }

    const feedback = this.feedback.find((item) => item.liftId === previousLift.id);

    return {
      id: previousLift.id,
      programWeek: previousWorkout.programWeek,
      status: previousLift.status,
      levelOfPain: feedback?.levelOfPain ?? null,
      levelOfEffort: feedback?.levelOfEffort ?? null,
      manualCheckinSourceLiftId: previousLift.manualCheckinSourceLiftId,
      sets: this.sets
        .filter((set) => set.liftId === previousLift.id)
        .sort((left, right) => left.order - right.order)
        .map((set) => ({
          order: set.order,
          plannedReps: set.plannedReps,
          plannedWeight: set.plannedWeight,
          actualReps: set.actualReps,
          actualWeight: set.actualWeight,
          status: set.status,
        })),
    };
  }
}

function cloneTemplateAggregate(template: TemplateAggregate): TemplateAggregate {
  return {
    ...template,
    focusMuscleIds: [...template.focusMuscleIds],
    days: template.days.map((day) => ({
      ...day,
      exerciseIds: [...day.exerciseIds],
    })),
  };
}

function validatePainValue(value: number): void {
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error("Choose a pain value from 1 to 5.");
  }
}

function validateEffortValue(value: number): void {
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error("Choose an effort value from 1 to 5.");
  }
}

export function createInMemoryAppServices(): AppServices {
  const appState = new InMemoryAppStateRepository();
  const templates = new InMemoryTemplateRepository();
  const training = new InMemoryTrainingRepository(appState, templates);
  templates.setActiveTemplateChecker((templateId) => training.isTemplateUsedByActiveProgram(templateId));

  return {
    mode: "memory",
    appState,
    exercises: new InMemoryExerciseCatalogRepository(),
    templates,
    programs: training,
    workouts: training,
    analytics: training,
    resetForAgent: async () => {
      await appState.resetForAgent();
      training.reset();
      templates.reset();
    },
  };
}
