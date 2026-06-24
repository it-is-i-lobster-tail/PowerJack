export const completedSetStatsMuscles = [
  ["Chest", "chest"],
  ["Back", "back"],
  ["Biceps", "biceps"],
  ["Triceps", "triceps"],
  ["Shoulders", "shoulders"],
  ["Core", "core"],
  ["Quads", "quads"],
  ["Hamstrings", "hamstrings"],
  ["Glutes", "glutes"],
  ["Calves", "calves"],
  ["Forearms", "forearms"],
] as const;

export type CompletedSetStatsMuscleName = (typeof completedSetStatsMuscles)[number][0];
export type CompletedSetStatsColumn = (typeof completedSetStatsMuscles)[number][1];
export type CompletedSetStatsValues = Record<CompletedSetStatsColumn, number>;

export const completedSetStatsColumns = completedSetStatsMuscles.map(([, column]) => column);
export const completedSetStatsValuePlaceholders = completedSetStatsColumns.map(() => "?").join(", ");
export const completedSetStatsColumnByMuscleName: ReadonlyMap<string, CompletedSetStatsColumn> = new Map(
  completedSetStatsMuscles.map(([muscleName, column]) => [muscleName, column]),
);

export function createEmptyCompletedSetStatsValues(): CompletedSetStatsValues {
  return {
    back: 0,
    biceps: 0,
    calves: 0,
    chest: 0,
    core: 0,
    forearms: 0,
    glutes: 0,
    hamstrings: 0,
    quads: 0,
    shoulders: 0,
    triceps: 0,
  };
}
