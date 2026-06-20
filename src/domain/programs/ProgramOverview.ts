import type { EntityId } from "../ids";
import type { PowerJackStatus } from "../status";

export interface ProgramOverviewFocusMuscle {
  id: EntityId;
  name: string;
}

export interface ProgramOverviewStatusCounts {
  planned: number;
  active: number;
  complete: number;
  halted: number;
  skipped: number;
}

export interface PersistedProgramScheduleCell {
  workoutId: EntityId;
  week: number;
  day: number;
  totalSets: number;
  statusCounts: ProgramOverviewStatusCounts;
}

export interface ProgramOverviewScheduleCell {
  workoutId: EntityId | null;
  week: number;
  day: number;
  totalSets: number;
  statusCounts: ProgramOverviewStatusCounts;
  source: "persisted" | "planned";
}

export interface ActiveProgramOverviewScheduleCell extends ProgramOverviewScheduleCell {
  isActive: boolean;
}

export interface ProgramOverviewSummary {
  id: EntityId;
  name: string;
  status: PowerJackStatus;
  locked: boolean;
  templateId: EntityId;
  templateName: string;
  programLengthWeeks: number;
  workoutsPerWeek: number;
  focusMuscles: ProgramOverviewFocusMuscle[];
  completedSets: number;
  totalSets: number;
  progressPercent: number;
}

export interface ProgramOverviewSnapshot {
  program: ProgramOverviewSummary;
  schedule: ProgramOverviewScheduleCell[];
}

export interface ProgramOverviewSegment {
  status: "complete" | "skipped" | "halted";
  count: number;
  widthPercent: number;
}

export function createProgramOverviewStatusCounts(
  overrides: Partial<ProgramOverviewStatusCounts> = {},
): ProgramOverviewStatusCounts {
  return {
    planned: overrides.planned ?? 0,
    active: overrides.active ?? 0,
    complete: overrides.complete ?? 0,
    halted: overrides.halted ?? 0,
    skipped: overrides.skipped ?? 0,
  };
}

export function countProgramOverviewSetStatus(
  counts: ProgramOverviewStatusCounts,
  status: PowerJackStatus,
): ProgramOverviewStatusCounts {
  return {
    ...counts,
    [status]: counts[status] + 1,
  };
}

export function buildProgramSchedule(input: {
  programLengthWeeks: number;
  workoutsPerWeek: number;
  persistedCells: PersistedProgramScheduleCell[];
  plannedSetCountsByDay: Map<number, number>;
}): ProgramOverviewScheduleCell[] {
  const persistedCellsByPosition = new Map<string, PersistedProgramScheduleCell>();

  for (const cell of input.persistedCells) {
    persistedCellsByPosition.set(scheduleCellKey(cell.week, cell.day), cell);
  }

  const cells: ProgramOverviewScheduleCell[] = [];

  for (let week = 1; week <= input.programLengthWeeks; week += 1) {
    for (let day = 1; day <= input.workoutsPerWeek; day += 1) {
      const persistedCell = persistedCellsByPosition.get(scheduleCellKey(week, day));

      if (persistedCell) {
        cells.push({
          ...persistedCell,
          source: "persisted",
        });
        continue;
      }

      const plannedSetCount = input.plannedSetCountsByDay.get(day) ?? 0;
      cells.push({
        workoutId: null,
        week,
        day,
        totalSets: plannedSetCount,
        statusCounts: createProgramOverviewStatusCounts({ planned: plannedSetCount }),
        source: "planned",
      });
    }
  }

  return cells;
}

export function calculateProgramProgress(schedule: ProgramOverviewScheduleCell[]): {
  completedSets: number;
  totalSets: number;
  progressPercent: number;
} {
  const completedSets = schedule.reduce((total, cell) => total + cell.statusCounts.complete, 0);
  const totalSets = schedule.reduce((total, cell) => total + cell.totalSets, 0);

  return {
    completedSets,
    totalSets,
    progressPercent: totalSets > 0 ? Math.round((completedSets / totalSets) * 100) : 0,
  };
}

export function markActiveProgramSchedule(input: {
  schedule: ProgramOverviewScheduleCell[];
  displayedProgramId: EntityId;
  activeProgramId: EntityId | null;
  activeWorkoutId: EntityId | null;
}): ActiveProgramOverviewScheduleCell[] {
  const activeWorkoutId =
    input.activeProgramId === input.displayedProgramId ? input.activeWorkoutId : null;

  return input.schedule.map((cell) => ({
    ...cell,
    isActive: activeWorkoutId !== null && cell.workoutId === activeWorkoutId,
  }));
}

export function calculateProgramElapsedWeeks(input: {
  schedule: ActiveProgramOverviewScheduleCell[];
  programLengthWeeks: number;
  workoutsPerWeek: number;
}): number {
  const programLengthWeeks = Math.max(input.programLengthWeeks, 1);
  const workoutsPerWeek = Math.max(input.workoutsPerWeek, 1);
  const activeCell = input.schedule.find((cell) => cell.isActive);
  const latestPersistedCell = input.schedule
    .filter((cell) => cell.source === "persisted")
    .sort((left, right) => {
      if (right.week !== left.week) {
        return right.week - left.week;
      }

      return right.day - left.day;
    })[0];
  const currentCell = activeCell ?? latestPersistedCell ?? input.schedule[0];

  if (!currentCell) {
    return 1 / workoutsPerWeek;
  }

  const week = clampNumber(currentCell.week, 1, programLengthWeeks);
  const day = clampNumber(currentCell.day, 1, workoutsPerWeek);

  return Math.max((week - 1) + day / workoutsPerWeek, 1 / workoutsPerWeek);
}

export function buildProgramOverviewSegments(
  cell: ProgramOverviewScheduleCell,
): ProgramOverviewSegment[] {
  if (cell.totalSets <= 0) {
    return [];
  }

  return (["complete", "skipped", "halted"] as const)
    .map((status) => ({
      status,
      count: cell.statusCounts[status],
      widthPercent: (cell.statusCounts[status] / cell.totalSets) * 100,
    }))
    .filter((segment) => segment.count > 0);
}

function scheduleCellKey(week: number, day: number): string {
  return `${week}:${day}`;
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
