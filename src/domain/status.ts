export const powerJackStatuses = ["planned", "active", "complete", "halted", "skipped"] as const;

export type PowerJackStatus = (typeof powerJackStatuses)[number];

export function isPowerJackStatus(value: string): value is PowerJackStatus {
  return powerJackStatuses.includes(value as PowerJackStatus);
}
