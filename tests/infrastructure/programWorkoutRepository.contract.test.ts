import { describe, expect, it } from "vitest";
import { loadProgramOverview } from "../../src/application/programs/loadProgramOverview";
import { startProgramFromTemplate } from "../../src/application/programs/startProgramFromTemplate";
import { saveTemplate, updateTemplate } from "../../src/application/templates/saveTemplate";
import { addSetToLift } from "../../src/application/workouts/addSetToLift";
import { changeLiftExercise } from "../../src/application/workouts/changeLiftExercise";
import { finishWorkout } from "../../src/application/workouts/finishWorkout";
import { removeLastSetFromLift } from "../../src/application/workouts/removeLastSetFromLift";
import { resolveManualCheckIn } from "../../src/application/workouts/resolveManualCheckIn";
import { submitLiftFeedback } from "../../src/application/workouts/submitLiftFeedback";
import { updateWorkoutSet } from "../../src/application/workouts/updateWorkoutSet";
import type { AppServices } from "../../src/app/AppServices";
import type { CompletedSetEvent } from "../../src/domain/analytics/TrainingAnalytics";
import type { ActiveWorkoutView } from "../../src/domain/workouts/Workout";
import { createInMemoryAppServices } from "../../src/infrastructure/database/repositories/InMemoryRepositories";

describe("Program and Workout repository contracts", () => {
  it("starts a program from a template and creates week 1 as active/planned workouts", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4 },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    const view = await loadRequiredActiveWorkout(services);
    const appState = await services.appState.load();

    expect(view.program).toMatchObject({
      name: "Back In Action x1",
      programLengthWeeks: 4,
      status: "active",
      locked: false,
    });
    expect(view.workout).toMatchObject({
      workoutDay: 1,
      programWeek: 1,
      status: "active",
      locked: false,
    });
    expect(view.weekWorkouts).toEqual([
      expect.objectContaining({ workoutDay: 1, status: "active", locked: false }),
      expect.objectContaining({ workoutDay: 2, status: "planned", locked: true }),
    ]);
    expect(view.lifts).toHaveLength(1);
    expect(view.lifts[0]?.sets).toHaveLength(2);
    expect(view.lifts[0]?.sets).toEqual([
      expect.objectContaining({ order: 1, status: "active", locked: false }),
      expect.objectContaining({ order: 2, status: "active", locked: false }),
    ]);
    expect(appState).toMatchObject({
      activeProgramId: view.program.id,
      activeWorkoutId: view.workout.id,
      activeLiftId: view.lifts[0]?.id,
    });
  });

  it("loads a reusable program overview with future weeks synthesized from the template", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4 },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    let view = await loadRequiredActiveWorkout(services);
    const firstSet = view.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );

    const overview = await loadProgramOverview(view.program.id, {
      appState: services.appState,
      programs: services.programs,
      analytics: services.analytics,
    });

    expect(overview?.program).toMatchObject({
      id: view.program.id,
      templateName: "Back In Action",
      workoutsPerWeek: 2,
      completedSets: 1,
      totalSets: 16,
      progressPercent: 6,
    });
    expect(overview?.schedule).toHaveLength(8);
    expect(overview?.schedule[0]).toMatchObject({
      workoutId: view.workout.id,
      isActive: true,
    });
    expect(overview?.schedule[0]?.statusCounts.complete).toBe(1);
    expect(overview?.schedule[0]?.statusCounts.active).toBe(1);
    expect(overview?.schedule[2]).toMatchObject({
      week: 2,
      day: 1,
      source: "planned",
      totalSets: 2,
    });
    expect(overview?.schedule[2]?.statusCounts.planned).toBe(2);
    expect(overview?.volumeRows).toEqual([
      expect.objectContaining({
        muscleName: "Chest",
        completedSets: 1,
        averageSetsPerWeek: 2,
      }),
      expect.objectContaining({
        muscleName: "Shoulders",
        completedSets: 0.5,
        averageSetsPerWeek: 1,
      }),
      expect.objectContaining({
        muscleName: "Triceps",
        completedSets: 0.5,
        averageSetsPerWeek: 1,
      }),
    ]);
  });

  it("updates set and lift status when values are entered or cleared", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);
    const firstSet = view.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );

    expect(view.completedSets).toBe(1);
    expect(view.lifts[0]?.status).toBe("active");
    expect(view.lifts[0]?.sets[0]).toMatchObject({
      actualReps: 12,
      actualWeight: 220,
      status: "complete",
    });

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: null, actualWeight: 220 },
      services.workouts,
    );

    expect(view.completedSets).toBe(0);
    expect(view.lifts[0]?.status).toBe("active");
    expect(view.lifts[0]?.sets[0]).toMatchObject({
      actualReps: null,
      actualWeight: 220,
      status: "active",
    });
  });

  it("adds a manual set and uses the completed set count for next-week progression", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);
    const lift = view.lifts[0];

    if (!lift) {
      throw new Error("Expected lift.");
    }

    view = await addSetToLift({ liftId: lift.id }, services.workouts);

    expect(view.totalSets).toBe(3);
    expect(view.completedSets).toBe(0);
    expect(view.lifts[0]?.sets).toHaveLength(3);
    expect(view.lifts[0]?.sets[2]).toMatchObject({
      order: 3,
      actualReps: null,
      actualWeight: null,
      status: "active",
      locked: false,
    });

    view = await completeWorkout(services, view, [10, 8, 7], 100);
    view = await submitFeedbackForCompletedLifts(services, view);
    const weekTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!weekTwo) {
      throw new Error("Expected week 2.");
    }

    expect(weekTwo.lifts[0]?.sets).toEqual([
      expect.objectContaining({ order: 1, plannedReps: 11, plannedWeight: 100 }),
      expect.objectContaining({ order: 2, plannedReps: 9, plannedWeight: 100 }),
      expect.objectContaining({ order: 3, plannedReps: 8, plannedWeight: 100 }),
    ]);
  });

  it("removes the last manual set, including logged values, and keeps at least one set", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);
    const lift = view.lifts[0];

    if (!lift) {
      throw new Error("Expected lift.");
    }

    view = await addSetToLift({ liftId: lift.id }, services.workouts);
    const thirdSet = view.lifts[0]?.sets[2];

    if (!thirdSet) {
      throw new Error("Expected third set.");
    }

    view = await updateWorkoutSet(
      { setId: thirdSet.id, actualReps: 7, actualWeight: 100 },
      services.workouts,
    );

    expect(view).toMatchObject({ completedSets: 1, totalSets: 3 });

    view = await removeLastSetFromLift({ liftId: lift.id }, services.workouts);

    expect(view).toMatchObject({ completedSets: 0, totalSets: 2 });
    expect(view.lifts[0]).toMatchObject({ status: "active" });
    expect(view.lifts[0]?.sets).toHaveLength(2);

    view = await removeLastSetFromLift({ liftId: lift.id }, services.workouts);

    expect(view.totalSets).toBe(1);
    await expect(removeLastSetFromLift({ liftId: lift.id }, services.workouts)).rejects.toThrow(
      "A lift must have at least one set.",
    );
  });

  it("changes a lift exercise, resets the lift, clears feedback, and updates future weeks", async () => {
    const services = createInMemoryAppServices();
    const pullUpId = await findExerciseId(services, "Pull Up");
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [10, 8], 100);
    view = await submitFeedbackForCompletedLifts(services, view);

    expect(view.lifts[0]).toMatchObject({
      exerciseName: "Barbell Bench Press",
      status: "complete",
      feedbackSubmitted: true,
    });

    view = await changeLiftExercise(
      { liftId: view.lifts[0]?.id ?? 0, exerciseId: pullUpId },
      services.workouts,
    );

    expect(view).toMatchObject({ completedSets: 0, totalSets: 2, canFinish: false });
    expect(view.lifts[0]).toMatchObject({
      exerciseName: "Pull Up",
      repsOnly: true,
      status: "active",
      feedbackSubmitted: false,
    });
    expect(view.lifts[0]?.sets).toEqual([
      expect.objectContaining({ order: 1, actualReps: null, actualWeight: null, status: "active" }),
      expect.objectContaining({ order: 2, actualReps: null, actualWeight: null, status: "active" }),
    ]);

    view = await completeWorkout(services, view, [8, 7], 100);
    view = await submitFeedbackForCompletedLifts(services, view);
    const weekTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!weekTwo) {
      throw new Error("Expected week 2.");
    }

    expect(weekTwo.lifts[0]).toMatchObject({
      exerciseName: "Pull Up",
      repsOnly: true,
    });
  });

  it("blocks manual lift edits for locked workouts", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);
    await startTemplateProgram(services, template.id);
    const activeView = await loadRequiredActiveWorkout(services);
    const plannedWorkoutId = activeView.nextWorkoutId;

    if (!plannedWorkoutId) {
      throw new Error("Expected planned workout.");
    }

    const plannedView = await services.workouts.loadWorkoutView(plannedWorkoutId);
    const plannedLiftId = plannedView?.lifts[0]?.id;

    if (!plannedLiftId) {
      throw new Error("Expected planned lift.");
    }

    await expect(addSetToLift({ liftId: plannedLiftId }, services.workouts)).rejects.toThrow(
      "This lift is locked.",
    );
    await expect(removeLastSetFromLift({ liftId: plannedLiftId }, services.workouts)).rejects.toThrow(
      "This lift is locked.",
    );
    await expect(
      changeLiftExercise({ liftId: plannedLiftId, exerciseId: 3 }, services.workouts),
    ).rejects.toThrow("This lift is locked.");
  });

  it("blocks active program replacement until confirmed, then halts and locks the old program", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    const oldView = await loadRequiredActiveWorkout(services);
    const firstSet = oldView.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );

    await expect(startTemplateProgram(services, template.id)).rejects.toThrow("An active program already exists.");

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4, replaceActiveProgram: true },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    const newView = await loadRequiredActiveWorkout(services);
    const oldLockedView = await services.workouts.loadWorkoutView(oldView.workout.id);
    const appState = await services.appState.load();

    expect(newView.program.id).not.toBe(oldView.program.id);
    expect(newView.program.name).toBe("Back In Action x2");
    expect(appState).toMatchObject({
      activeProgramId: newView.program.id,
      activeWorkoutId: newView.workout.id,
    });
    expect(oldLockedView?.program).toMatchObject({ status: "halted", locked: true });
    expect(oldLockedView?.workout).toMatchObject({ status: "halted", locked: true });
    expect(oldLockedView?.lifts[0]).toMatchObject({ status: "halted", locked: true });
    expect(oldLockedView?.completedSets).toBe(1);
    expect(oldLockedView?.lifts[0]?.sets[0]).toMatchObject({ status: "complete", locked: true });
    expect(oldLockedView?.lifts[0]?.sets[1]).toMatchObject({ status: "halted", locked: true });
  });

  it("lists active halted and complete program summaries newest first", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let completeView = await loadRequiredActiveWorkout(services);

    for (let week = 1; week <= 4; week += 1) {
      const completedView = await submitFeedbackForCompletedLifts(
        services,
        await completeWorkout(services, completeView, [10, 8], 100),
      );
      const nextView = await finishWorkout(completedView.workout.id, services.workouts);

      if (week < 4) {
        if (!nextView) {
          throw new Error("Expected next week workout.");
        }

        completeView = nextView;
      }
    }

    await startTemplateProgram(services, template.id);
    const haltedCandidate = await loadRequiredActiveWorkout(services);
    const firstSet = haltedCandidate.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );
    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4, replaceActiveProgram: true },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    const summaries = await services.programs.listSummaries();

    expect(summaries.map((summary) => summary.status)).toEqual(["active", "halted", "complete"]);
    expect(summaries.map((summary) => summary.name)).toEqual([
      "Back In Action x3",
      "Back In Action x2",
      "Back In Action x1",
    ]);
    expect(summaries[0]).toMatchObject({
      templateName: "Back In Action",
      focusMuscles: [{ id: 1, name: "Back" }],
      progressPercent: 0,
    });
    expect(summaries[1]).toMatchObject({ progressPercent: 13 });
    expect(summaries[2]).toMatchObject({ progressPercent: 100 });
  });

  it("finishes workouts, activates the next workout, and creates the next week with progression", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [10, 8], 100);
    expect(view.canFinish).toBe(false);

    view = await submitFeedbackForCompletedLifts(services, view);
    expect(view.canFinish).toBe(true);

    const dayTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!dayTwo) {
      throw new Error("Expected day 2.");
    }

    expect(dayTwo.workout).toMatchObject({
      workoutDay: 2,
      programWeek: 1,
      status: "active",
      locked: false,
    });

    let completedDayTwo = await completeWorkout(services, dayTwo, [6, 5], 200);
    completedDayTwo = await submitFeedbackForCompletedLifts(services, completedDayTwo);
    const weekTwoDayOne = await finishWorkout(completedDayTwo.workout.id, services.workouts);

    if (!weekTwoDayOne) {
      throw new Error("Expected week 2 day 1.");
    }

    expect(weekTwoDayOne.workout).toMatchObject({
      workoutDay: 1,
      programWeek: 2,
      status: "active",
      locked: false,
    });
    expect(weekTwoDayOne.lifts[0]?.sets).toEqual([
      expect.objectContaining({ plannedReps: 11, plannedWeight: 100, actualReps: null }),
      expect.objectContaining({ plannedReps: 9, plannedWeight: 100, actualReps: null }),
    ]);
  });

  it("uses active template edits only for future generated weeks", async () => {
    const services = createInMemoryAppServices();
    const benchPressId = await findExerciseId(services, "Barbell Bench Press");
    const squatId = await findExerciseId(services, "Barbell Back Squat");
    const dumbbellBenchId = await findExerciseId(services, "Dumbbell Bench Press");
    const template = await createTemplate(services, [[benchPressId], [squatId]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    await updateTemplate(
      template.id,
      {
        name: "Back In Action",
        focusMuscleIds: [1],
        workoutsPerWeek: 2,
        days: [
          { order: 1, exerciseIds: [dumbbellBenchId] },
          { order: 2, exerciseIds: [squatId] },
        ],
      },
      services.templates,
    );

    const currentWeekDayOne = await services.workouts.loadWorkoutView(view.workout.id);
    expect(currentWeekDayOne?.lifts[0]?.exerciseId).toBe(benchPressId);

    view = await completeWorkout(services, view, [10, 8], 100);
    view = await submitFeedbackForCompletedLifts(services, view);
    let dayTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!dayTwo) {
      throw new Error("Expected day 2.");
    }

    expect(dayTwo.lifts[0]?.exerciseId).toBe(squatId);

    dayTwo = await completeWorkout(services, dayTwo, [6, 5], 200);
    dayTwo = await submitFeedbackForCompletedLifts(services, dayTwo);
    const weekTwoDayOne = await finishWorkout(dayTwo.workout.id, services.workouts);

    if (!weekTwoDayOne) {
      throw new Error("Expected week 2 day 1.");
    }

    expect(weekTwoDayOne.workout).toMatchObject({ workoutDay: 1, programWeek: 2 });
    expect(weekTwoDayOne.lifts[0]?.exerciseId).toBe(dumbbellBenchId);
  });

  it("logs reps-only exercises without weight and progresses reps without planned weight", async () => {
    const services = createInMemoryAppServices();
    const pullUpId = await findExerciseId(services, "Pull Up");
    const template = await createTemplate(services, [[pullUpId]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    expect(view.lifts[0]).toMatchObject({
      exerciseName: "Pull Up",
      repsOnly: true,
    });

    const firstSet = view.lifts[0]?.sets[0];
    const secondSet = view.lifts[0]?.sets[1];

    if (!firstSet || !secondSet) {
      throw new Error("Expected two pull-up sets.");
    }

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 8, actualWeight: null },
      services.workouts,
    );

    expect(view.completedSets).toBe(1);
    expect(view.lifts[0]?.sets[0]).toMatchObject({
      actualReps: 8,
      actualWeight: null,
      status: "complete",
    });

    view = await updateWorkoutSet(
      { setId: secondSet.id, actualReps: 7, actualWeight: 180 },
      services.workouts,
    );

    expect(view.completedSets).toBe(2);
    expect(view.lifts[0]).toMatchObject({ status: "complete" });
    expect(view.lifts[0]?.sets[1]).toMatchObject({
      actualReps: 7,
      actualWeight: null,
      status: "complete",
    });

    const completedSetEvents = await services.analytics.loadCompletedSetEvents({
      fromInclusive: "2026-06-17T00:00:00.000Z",
      toExclusive: "2026-06-19T00:00:00.000Z",
    });

    expect(completedSetEvents).toHaveLength(8);
    expect(sumSetCredits(completedSetEvents, "Back")).toBe(2);
    expect(sumSetCredits(completedSetEvents, "Biceps")).toBe(1);
    expect(sumSetCredits(completedSetEvents, "Forearms")).toBe(1);
    expect(sumSetCredits(completedSetEvents, "Core")).toBe(1);

    view = await submitFeedbackForCompletedLifts(services, view);
    const weekTwoDayOne = await finishWorkout(view.workout.id, services.workouts);

    if (!weekTwoDayOne) {
      throw new Error("Expected week 2 day 1.");
    }

    expect(weekTwoDayOne.lifts[0]).toMatchObject({
      exerciseName: "Pull Up",
      repsOnly: true,
    });
    expect(weekTwoDayOne.lifts[0]?.sets).toEqual([
      expect.objectContaining({ plannedReps: 9, plannedWeight: null, actualWeight: null }),
      expect.objectContaining({ plannedReps: 8, plannedWeight: null, actualWeight: null }),
    ]);
  });

  it("averages weighted primary and secondary volume through the current program day", async () => {
    const services = createInMemoryAppServices();
    const deadliftId = await findExerciseId(services, "Barbell Deadlift");
    const pullUpId = await findExerciseId(services, "Pull Up");
    const pulldownId = await findExerciseId(services, "Cable Lat Pulldown");
    const rearDeltFlyId = await findExerciseId(services, "Cable Rear Delt Fly");
    const squatId = await findExerciseId(services, "Barbell Back Squat");
    const template = await createTemplate(services, [
      [deadliftId, pullUpId, pulldownId, rearDeltFlyId],
      [squatId],
    ]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [10, 10], 10);
    view = await submitFeedbackForCompletedLifts(services, view);
    const dayTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!dayTwo) {
      throw new Error("Expected day 2.");
    }

    const overview = await loadProgramOverview(dayTwo.program.id, {
      appState: services.appState,
      programs: services.programs,
      analytics: services.analytics,
    });

    expect(overview?.volumeRows).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ muscleName: "Back", completedSets: 6, averageSetsPerWeek: 6 }),
        expect.objectContaining({ muscleName: "Glutes", completedSets: 2, averageSetsPerWeek: 2 }),
        expect.objectContaining({ muscleName: "Shoulders", completedSets: 2, averageSetsPerWeek: 2 }),
        expect.objectContaining({ muscleName: "Biceps", completedSets: 2, averageSetsPerWeek: 2 }),
        expect.objectContaining({ muscleName: "Forearms", completedSets: 3, averageSetsPerWeek: 3 }),
      ]),
    );
  });

  it("requires one feedback row for each completed lift before finishing", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [12, 10], 220);

    expect(view.lifts[0]).toMatchObject({
      status: "complete",
      feedbackSubmitted: false,
    });
    expect(view.canFinish).toBe(false);
    await expect(finishWorkout(view.workout.id, services.workouts)).rejects.toThrow(
      "Submit feedback for every completed lift before finishing the workout.",
    );

    view = await submitLiftFeedback(
      { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 1, levelOfEffort: 3 },
      services.workouts,
    );
    expect(view.lifts[0]?.feedbackSubmitted).toBe(true);
    expect(view.canFinish).toBe(true);

    view = await submitLiftFeedback(
      { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 4, levelOfEffort: 5 },
      services.workouts,
    );
    expect(view.lifts[0]?.feedbackSubmitted).toBe(true);
    expect(view.canFinish).toBe(true);
  });

  it("requires manual check-in after a high-pain lift and carries skipped lifts forward", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [10, 8], 100);
    view = await submitLiftFeedback(
      { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 4, levelOfEffort: 3 },
      services.workouts,
    );
    const weekTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!weekTwo) {
      throw new Error("Expected week 2.");
    }

    expect(weekTwo.lifts[0]).toMatchObject({
      manualCheckinStatus: "pending",
      manualCheckinSourcePain: 4,
      locked: true,
    });
    expect(weekTwo.lifts[0]?.sets).toEqual([
      expect.objectContaining({ plannedReps: 10, plannedWeight: 100, locked: true }),
      expect.objectContaining({ plannedReps: 8, plannedWeight: 100, locked: true }),
    ]);
    expect(weekTwo.canFinish).toBe(false);

    const skippedWeekTwo = await resolveManualCheckIn(
      { liftId: weekTwo.lifts[0]?.id ?? 0, decision: "skip" },
      services.workouts,
    );

    expect(skippedWeekTwo).toMatchObject({
      completedSets: 0,
      totalSets: 0,
      canFinish: true,
    });
    expect(skippedWeekTwo.lifts[0]).toMatchObject({ status: "skipped", locked: true });
    expect(skippedWeekTwo.lifts[0]?.sets).toEqual([
      expect.objectContaining({ status: "skipped", locked: true }),
      expect.objectContaining({ status: "skipped", locked: true }),
    ]);

    const weekThree = await finishWorkout(skippedWeekTwo.workout.id, services.workouts);

    if (!weekThree) {
      throw new Error("Expected week 3.");
    }

    expect(weekThree.lifts[0]).toMatchObject({
      manualCheckinStatus: "pending",
      manualCheckinSourcePain: 4,
      locked: true,
    });
    expect(weekThree.lifts[0]?.sets).toEqual([
      expect.objectContaining({ plannedReps: 10, plannedWeight: 100 }),
      expect.objectContaining({ plannedReps: 8, plannedWeight: 100 }),
    ]);
  });

  it("resets a high-pain manual check-in lift to two blank active sets", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [10, 8], 100);
    view = await submitLiftFeedback(
      { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 5, levelOfEffort: 3 },
      services.workouts,
    );
    const weekTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!weekTwo) {
      throw new Error("Expected week 2.");
    }

    const resetView = await resolveManualCheckIn(
      { liftId: weekTwo.lifts[0]?.id ?? 0, decision: "reset" },
      services.workouts,
    );

    expect(resetView.lifts[0]).toMatchObject({
      status: "active",
      locked: false,
      manualCheckinStatus: "resolved",
    });
    expect(resetView.lifts[0]?.sets).toEqual([
      expect.objectContaining({
        order: 1,
        plannedReps: null,
        plannedWeight: null,
        actualReps: null,
        actualWeight: null,
        status: "active",
        locked: false,
      }),
      expect.objectContaining({
        order: 2,
        plannedReps: null,
        plannedWeight: null,
        actualReps: null,
        actualWeight: null,
        status: "active",
        locked: false,
      }),
    ]);
    expect(resetView.canFinish).toBe(false);
  });

  it("clears active app state after the final workout and counts later program names", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    for (let week = 1; week <= 4; week += 1) {
      const completedView = await submitFeedbackForCompletedLifts(
        services,
        await completeWorkout(services, view, [10, 8], 100),
      );
      const nextView = await finishWorkout(completedView.workout.id, services.workouts);

      if (week < 4) {
        if (!nextView) {
          throw new Error("Expected next week workout.");
        }

        view = nextView;
      } else {
        expect(nextView).toBeNull();
      }
    }

    await expect(services.appState.load()).resolves.toMatchObject({
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
    });

    await startTemplateProgram(services, template.id);
    const secondProgram = await loadRequiredActiveWorkout(services);

    expect(secondProgram.program.name).toBe("Back In Action x2");
  });
});

async function createTemplate(services: AppServices, exerciseIdsByDay: number[][]) {
  return saveTemplate(
    {
      name: "Back In Action",
      focusMuscleIds: [1],
      workoutsPerWeek: exerciseIdsByDay.length,
      days: exerciseIdsByDay.map((exerciseIds, index) => ({
        order: index + 1,
        exerciseIds,
      })),
    },
    services.templates,
  );
}

async function findExerciseId(services: AppServices, name: string): Promise<number> {
  const exercises = await services.exercises.searchExercises(name);
  const exercise = exercises.find((item) => item.name === name);

  if (!exercise) {
    throw new Error(`Expected exercise ${name}.`);
  }

  return exercise.id;
}

async function submitFeedbackForCompletedLifts(
  services: AppServices,
  view: ActiveWorkoutView,
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const lift of view.lifts.filter((lift) => lift.status === "complete" && !lift.feedbackSubmitted)) {
    nextView = await submitLiftFeedback(
      { liftId: lift.id, levelOfPain: 1, levelOfEffort: 3 },
      services.workouts,
    );
  }

  return nextView;
}

function sumSetCredits(events: CompletedSetEvent[], muscleName: string): number {
  return events
    .filter((event) => event.muscleName === muscleName)
    .reduce((total, event) => total + event.setCredit, 0);
}

async function startTemplateProgram(services: AppServices, templateId: number) {
  return startProgramFromTemplate(
    { templateId, programLengthWeeks: 4 },
    {
      appState: services.appState,
      templates: services.templates,
      programs: services.programs,
    },
  );
}

async function loadRequiredActiveWorkout(services: AppServices): Promise<ActiveWorkoutView> {
  const view = await services.workouts.loadActive();

  if (!view) {
    throw new Error("Expected active workout.");
  }

  return view;
}

async function completeWorkout(
  services: AppServices,
  view: ActiveWorkoutView,
  repsBySet: number[],
  weight: number,
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const lift of view.lifts) {
    for (const set of lift.sets) {
      nextView = await updateWorkoutSet(
        {
          setId: set.id,
          actualReps: repsBySet[set.order - 1] ?? repsBySet[0] ?? 10,
          actualWeight: weight,
        },
        services.workouts,
      );
    }
  }

  return nextView;
}
