export function normalizeExerciseSearchText(value: string): string {
  return value.trim().toLowerCase().replace(/-/g, " ").replace(/\s+/g, " ");
}
