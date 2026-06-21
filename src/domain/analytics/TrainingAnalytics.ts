import type { EntityId } from "../ids";

export type SetVisualizationRange = "week" | "month" | "quarter" | "year";
export type SetVisualizationView = "bars" | "heatmap" | "sparklines" | "compare";
export type SetVolumeBand = "not-ideal" | "maintaining" | "growth" | "max-growth" | "overtraining";

export const setVisualizationRanges: SetVisualizationRange[] = ["week", "month", "quarter", "year"];
export const setVisualizationViews: SetVisualizationView[] = ["bars", "heatmap", "sparklines", "compare"];

export interface CompletedSetEvent {
  setId: EntityId;
  muscleId: EntityId;
  muscleName: string;
  completedAt: string;
  setCredit: number;
}

export interface CompletedSetMuscle {
  id: EntityId;
  name: string;
}

export interface SetVolumeBucket {
  key: string;
  label: string;
  shortLabel: string;
  startDate: string;
  endDate: string;
  durationWeeks: number;
}

export interface SetVolumeMuscleRow {
  muscleId: EntityId;
  muscleName: string;
  completedSets: number;
  previousCompletedSets: number;
  delta: number;
  bucketCounts: number[];
  metricValue: number;
  previousMetricValue: number;
  metricDelta: number;
  bucketValues: number[];
}

export interface SetVolumeReport {
  range: SetVisualizationRange;
  periodStart: string;
  periodEnd: string;
  previousPeriodStart: string;
  previousPeriodEnd: string;
  periodLabel: string;
  previousPeriodLabel: string;
  buckets: SetVolumeBucket[];
  totalCompletedSets: number;
  previousTotalCompletedSets: number;
  delta: number;
  metricLabel: string;
  metricUnitLabel: string;
  metricValue: number;
  previousMetricValue: number;
  metricDelta: number;
  rows: SetVolumeMuscleRow[];
}

export interface ProgramSetVolumeMuscleRow {
  muscleId: EntityId;
  muscleName: string;
  completedSets: number;
  averageSetsPerWeek: number;
  isFocusMuscle: boolean;
}

export interface ProgramSetVolumeReport {
  totalCompletedSets: number;
  rows: ProgramSetVolumeMuscleRow[];
}

export interface PeriodBounds {
  currentStart: Date;
  currentEnd: Date;
  previousStart: Date;
  previousEnd: Date;
}

const dayMs = 24 * 60 * 60 * 1000;
const monthNames = new Intl.DateTimeFormat("en-US", { month: "long" });
const shortMonthNames = new Intl.DateTimeFormat("en-US", { month: "short" });
const dayNames = new Intl.DateTimeFormat("en-US", { weekday: "short" });

export function buildSetVolumeReport(input: {
  events: CompletedSetEvent[];
  periodStart: Date;
  range: SetVisualizationRange;
}): SetVolumeReport {
  const bounds = getPeriodBounds(input.range, input.periodStart);
  const buckets = buildBuckets(input.range, bounds.currentStart, bounds.currentEnd);
  const rowsByMuscle = new Map<EntityId, SetVolumeMuscleRow>();
  const currentSetIds = new Set<EntityId>();
  const previousSetIds = new Set<EntityId>();

  for (const event of input.events) {
    const completedAt = parseCompletedAt(event.completedAt);
    const row = ensureRow(rowsByMuscle, event, buckets.length);

    if (isWithin(completedAt, bounds.currentStart, bounds.currentEnd)) {
      currentSetIds.add(event.setId);
      row.completedSets += event.setCredit;

      const bucketIndex = buckets.findIndex((bucket) =>
        isWithin(completedAt, new Date(bucket.startDate), new Date(bucket.endDate)),
      );

      if (bucketIndex >= 0) {
        row.bucketCounts[bucketIndex] += event.setCredit;
      }
    } else if (isWithin(completedAt, bounds.previousStart, bounds.previousEnd)) {
      previousSetIds.add(event.setId);
      row.previousCompletedSets += event.setCredit;
    }
  }

  const rows = Array.from(rowsByMuscle.values())
    .filter((row) => row.completedSets > 0 || row.previousCompletedSets > 0)
    .map((row) => ({
      ...row,
      delta: row.completedSets - row.previousCompletedSets,
      metricValue: normalizeCompletedSets(row.completedSets, input.range, weeksBetween(bounds.currentStart, bounds.currentEnd)),
      previousMetricValue: normalizeCompletedSets(
        row.previousCompletedSets,
        input.range,
        weeksBetween(bounds.previousStart, bounds.previousEnd),
      ),
      metricDelta:
        normalizeCompletedSets(row.completedSets, input.range, weeksBetween(bounds.currentStart, bounds.currentEnd)) -
        normalizeCompletedSets(row.previousCompletedSets, input.range, weeksBetween(bounds.previousStart, bounds.previousEnd)),
      bucketValues: row.bucketCounts.map((count, index) =>
        normalizeCompletedSets(count, input.range, buckets[index]?.durationWeeks ?? 1),
      ),
    }))
    .sort((left, right) => {
      if (right.metricValue !== left.metricValue) {
        return right.metricValue - left.metricValue;
      }

      if (right.previousMetricValue !== left.previousMetricValue) {
        return right.previousMetricValue - left.previousMetricValue;
      }

      return left.muscleName.localeCompare(right.muscleName);
    });

  const totalCompletedSets = currentSetIds.size;
  const previousTotalCompletedSets = previousSetIds.size;
  const metricValue = normalizeCompletedSets(totalCompletedSets, input.range, weeksBetween(bounds.currentStart, bounds.currentEnd));
  const previousMetricValue = normalizeCompletedSets(
    previousTotalCompletedSets,
    input.range,
    weeksBetween(bounds.previousStart, bounds.previousEnd),
  );

  return {
    range: input.range,
    periodStart: bounds.currentStart.toISOString(),
    periodEnd: bounds.currentEnd.toISOString(),
    previousPeriodStart: bounds.previousStart.toISOString(),
    previousPeriodEnd: bounds.previousEnd.toISOString(),
    periodLabel: formatPeriodLabel(input.range, bounds.currentStart),
    previousPeriodLabel: formatPeriodLabel(input.range, bounds.previousStart),
    buckets,
    totalCompletedSets,
    previousTotalCompletedSets,
    delta: totalCompletedSets - previousTotalCompletedSets,
    metricLabel: input.range === "week" ? "Completed sets" : "Average completed sets",
    metricUnitLabel: input.range === "week" ? "sets" : "sets/week",
    metricValue,
    previousMetricValue,
    metricDelta: metricValue - previousMetricValue,
    rows,
  };
}

export function buildProgramSetVolumeReport(input: {
  events: CompletedSetEvent[];
  elapsedWeeks: number;
  focusMuscleIds: EntityId[];
}): ProgramSetVolumeReport {
  const focusMuscleIds = new Set(input.focusMuscleIds);
  const rowsByMuscle = new Map<EntityId, ProgramSetVolumeMuscleRow>();
  const setIds = new Set<EntityId>();
  const durationWeeks = input.elapsedWeeks > 0 ? input.elapsedWeeks : 1;

  for (const event of input.events) {
    setIds.add(event.setId);
    const existingRow = rowsByMuscle.get(event.muscleId);

    if (existingRow) {
      existingRow.completedSets += event.setCredit;
      existingRow.averageSetsPerWeek = existingRow.completedSets / durationWeeks;
      continue;
    }

    rowsByMuscle.set(event.muscleId, {
      muscleId: event.muscleId,
      muscleName: event.muscleName,
      completedSets: event.setCredit,
      averageSetsPerWeek: event.setCredit / durationWeeks,
      isFocusMuscle: focusMuscleIds.has(event.muscleId),
    });
  }

  const rows = Array.from(rowsByMuscle.values()).sort((left, right) => {
    if (right.averageSetsPerWeek !== left.averageSetsPerWeek) {
      return right.averageSetsPerWeek - left.averageSetsPerWeek;
    }

    return left.muscleName.localeCompare(right.muscleName);
  });

  return {
    totalCompletedSets: setIds.size,
    rows,
  };
}

export function classifyWeeklySetVolume(value: number): SetVolumeBand {
  if (value >= 25) {
    return "overtraining";
  }

  if (value >= 15) {
    return "max-growth";
  }

  if (value >= 7) {
    return "growth";
  }

  if (value >= 4) {
    return "maintaining";
  }

  return "not-ideal";
}

export function buildCompletedSetEventsForMuscles(input: {
  setId: EntityId;
  completedAt: string;
  primaryMuscle: CompletedSetMuscle;
  secondaryMuscles: CompletedSetMuscle[];
}): CompletedSetEvent[] {
  return [
    {
      setId: input.setId,
      muscleId: input.primaryMuscle.id,
      muscleName: input.primaryMuscle.name,
      completedAt: input.completedAt,
      setCredit: 1,
    },
    ...input.secondaryMuscles
      .filter((muscle) => muscle.id !== input.primaryMuscle.id)
      .map((muscle) => ({
        setId: input.setId,
        muscleId: muscle.id,
        muscleName: muscle.name,
        completedAt: input.completedAt,
        setCredit: 0.5,
      })),
  ];
}

export function getDefaultPeriodStart(range: SetVisualizationRange, now = new Date()): Date {
  return startOfRange(range, now);
}

export function getPeriodBounds(range: SetVisualizationRange, periodStart: Date): PeriodBounds {
  const currentStart = startOfRange(range, periodStart);
  const currentEnd = addRange(currentStart, range, 1);
  const previousStart = addRange(currentStart, range, -1);

  return {
    currentStart,
    currentEnd,
    previousStart,
    previousEnd: currentStart,
  };
}

export function addRange(date: Date, range: SetVisualizationRange, amount: number): Date {
  switch (range) {
    case "week":
      return addDays(date, amount * 7);
    case "month":
      return new Date(date.getFullYear(), date.getMonth() + amount, 1);
    case "quarter":
      return new Date(date.getFullYear(), date.getMonth() + amount * 3, 1);
    case "year":
      return new Date(date.getFullYear() + amount, 0, 1);
  }
}

export function serializePeriodStart(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function parsePeriodStart(value: string | null, range: SetVisualizationRange, now = new Date()): Date {
  if (!value) {
    return getDefaultPeriodStart(range, now);
  }

  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);

  if (!match) {
    return getDefaultPeriodStart(range, now);
  }

  const year = Number(match[1]);
  const month = Number(match[2]) - 1;
  const day = Number(match[3]);
  const parsed = new Date(year, month, day);

  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.getFullYear() !== year ||
    parsed.getMonth() !== month ||
    parsed.getDate() !== day
  ) {
    return getDefaultPeriodStart(range, now);
  }

  return startOfRange(range, parsed);
}

export function isSetVisualizationRange(value: string | null): value is SetVisualizationRange {
  return value === "week" || value === "month" || value === "quarter" || value === "year";
}

export function isSetVisualizationView(value: string | null): value is SetVisualizationView {
  return value === "bars" || value === "heatmap" || value === "sparklines" || value === "compare";
}

function ensureRow(
  rowsByMuscle: Map<EntityId, SetVolumeMuscleRow>,
  event: CompletedSetEvent,
  bucketCount: number,
): SetVolumeMuscleRow {
  const existing = rowsByMuscle.get(event.muscleId);

  if (existing) {
    return existing;
  }

  const row: SetVolumeMuscleRow = {
    muscleId: event.muscleId,
    muscleName: event.muscleName,
    completedSets: 0,
    previousCompletedSets: 0,
    delta: 0,
    bucketCounts: Array.from({ length: bucketCount }, () => 0),
    metricValue: 0,
    previousMetricValue: 0,
    metricDelta: 0,
    bucketValues: Array.from({ length: bucketCount }, () => 0),
  };
  rowsByMuscle.set(event.muscleId, row);
  return row;
}

function buildBuckets(
  range: SetVisualizationRange,
  periodStart: Date,
  periodEnd: Date,
): SetVolumeBucket[] {
  switch (range) {
    case "week":
      return Array.from({ length: 7 }, (_, index) => {
        const start = addDays(periodStart, index);
        const end = addDays(start, 1);
        const label = dayNames.format(start);
        return createBucket(label, label.slice(0, 1), start, end);
      });
    case "month": {
      const buckets: SetVolumeBucket[] = [];
      let start = new Date(periodStart);
      let index = 1;

      while (start < periodEnd) {
        const end = new Date(Math.min(addDays(start, 7).getTime(), periodEnd.getTime()));
        buckets.push(createBucket(`Week ${index}`, `W${index}`, start, end));
        start = end;
        index += 1;
      }

      return buckets;
    }
    case "quarter":
      return Array.from({ length: 3 }, (_, index) => {
        const start = new Date(periodStart.getFullYear(), periodStart.getMonth() + index, 1);
        const end = new Date(periodStart.getFullYear(), periodStart.getMonth() + index + 1, 1);
        return createBucket(shortMonthNames.format(start), shortMonthNames.format(start), start, end);
      });
    case "year":
      return Array.from({ length: 12 }, (_, index) => {
        const start = new Date(periodStart.getFullYear(), index, 1);
        const end = new Date(periodStart.getFullYear(), index + 1, 1);
        return createBucket(shortMonthNames.format(start), shortMonthNames.format(start), start, end);
      });
  }
}

function createBucket(label: string, shortLabel: string, start: Date, end: Date): SetVolumeBucket {
  return {
    key: serializePeriodStart(start),
    label,
    shortLabel,
    startDate: start.toISOString(),
    endDate: end.toISOString(),
    durationWeeks: weeksBetween(start, end),
  };
}

function startOfRange(range: SetVisualizationRange, date: Date): Date {
  switch (range) {
    case "week":
      return startOfWeek(date);
    case "month":
      return new Date(date.getFullYear(), date.getMonth(), 1);
    case "quarter": {
      const quarterMonth = Math.floor(date.getMonth() / 3) * 3;
      return new Date(date.getFullYear(), quarterMonth, 1);
    }
    case "year":
      return new Date(date.getFullYear(), 0, 1);
  }
}

function startOfWeek(date: Date): Date {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const mondayOffset = (start.getDay() + 6) % 7;
  return addDays(start, -mondayOffset);
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * dayMs);
}

function weeksBetween(start: Date, end: Date): number {
  return Math.max((end.getTime() - start.getTime()) / dayMs / 7, 1 / 7);
}

function normalizeCompletedSets(count: number, range: SetVisualizationRange, durationWeeks: number): number {
  if (range === "week") {
    return count;
  }

  return count / durationWeeks;
}

function formatPeriodLabel(range: SetVisualizationRange, start: Date): string {
  switch (range) {
    case "week": {
      const end = addDays(start, 6);
      const startMonth = shortMonthNames.format(start);
      const endMonth = shortMonthNames.format(end);
      const startDay = start.getDate();
      const endDay = end.getDate();

      if (start.getFullYear() === end.getFullYear() && start.getMonth() === end.getMonth()) {
        return `${startMonth} ${startDay}-${endDay}, ${start.getFullYear()}`;
      }

      if (start.getFullYear() === end.getFullYear()) {
        return `${startMonth} ${startDay}-${endMonth} ${endDay}, ${start.getFullYear()}`;
      }

      return `${startMonth} ${startDay}, ${start.getFullYear()}-${endMonth} ${endDay}, ${end.getFullYear()}`;
    }
    case "month":
      return `${monthNames.format(start)} ${start.getFullYear()}`;
    case "quarter":
      return `Q${Math.floor(start.getMonth() / 3) + 1} ${start.getFullYear()}`;
    case "year":
      return `${start.getFullYear()}`;
  }
}

function parseCompletedAt(value: string): Date {
  const normalized = value.includes("T") ? value : `${value.replace(" ", "T")}Z`;
  const parsed = new Date(normalized);

  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid completed set timestamp: ${value}`);
  }

  return parsed;
}

function isWithin(value: Date, start: Date, end: Date): boolean {
  return value >= start && value < end;
}
