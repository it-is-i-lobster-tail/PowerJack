import {
  buildProgramSetVolumeReport,
  type ProgramSetVolumeMuscleRow,
} from "../../domain/analytics/TrainingAnalytics";
import type { TrainingAnalyticsRepository } from "../../domain/analytics/TrainingAnalyticsRepository";
import type { AppStateRepository } from "../../domain/app-state/AppStateRepository";
import type { EntityId } from "../../domain/ids";
import {
  calculateProgramElapsedWeeks,
  markActiveProgramSchedule,
  type ActiveProgramOverviewScheduleCell,
  type ProgramOverviewSummary,
} from "../../domain/programs/ProgramOverview";
import type { ProgramRepository } from "../../domain/programs/ProgramRepository";

export interface ProgramOverviewView {
  program: ProgramOverviewSummary;
  schedule: ActiveProgramOverviewScheduleCell[];
  volumeRows: ProgramSetVolumeMuscleRow[];
}

export async function loadProgramOverview(
  programId: EntityId,
  repositories: {
    appState: AppStateRepository;
    programs: ProgramRepository;
    analytics: TrainingAnalyticsRepository;
  },
): Promise<ProgramOverviewView | null> {
  const overview = await repositories.programs.loadOverview(programId);

  if (!overview) {
    return null;
  }

  const [appState, completedSetEvents] = await Promise.all([
    repositories.appState.load(),
    repositories.analytics.loadCompletedSetEventsForProgram(programId),
  ]);
  const schedule = markActiveProgramSchedule({
    schedule: overview.schedule,
    displayedProgramId: overview.program.id,
    activeProgramId: appState?.activeProgramId ?? null,
    activeWorkoutId: appState?.activeWorkoutId ?? null,
  });
  const elapsedWeeks = calculateProgramElapsedWeeks({
    schedule,
    programLengthWeeks: overview.program.programLengthWeeks,
    workoutsPerWeek: overview.program.workoutsPerWeek,
  });
  const volumeReport = buildProgramSetVolumeReport({
    events: completedSetEvents,
    elapsedWeeks,
    focusMuscleIds: overview.program.focusMuscles.map((muscle) => muscle.id),
  });

  return {
    program: overview.program,
    schedule,
    volumeRows: volumeReport.rows,
  };
}
