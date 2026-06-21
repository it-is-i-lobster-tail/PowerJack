import type { EntityId } from "../ids";
import type { PowerJackStatus } from "../status";

export const programListFilters = ["all", "complete", "halted"] as const;

export type ProgramListFilter = (typeof programListFilters)[number];

export interface ProgramListFocusMuscle {
  id: EntityId;
  name: string;
}

export interface ProgramListSummary {
  id: EntityId;
  name: string;
  status: PowerJackStatus;
  templateName: string;
  focusMuscles: ProgramListFocusMuscle[];
  progressPercent: number;
  createdAt: string;
  updatedAt: string;
}

export interface ProgramListItem extends ProgramListSummary {
  isCurrentProgram: boolean;
}

export function buildProgramListItems(input: {
  summaries: ProgramListSummary[];
  activeProgramId: EntityId | null;
  filter: ProgramListFilter;
}): ProgramListItem[] {
  const filteredSummaries = sortProgramListSummaries(input.summaries).filter(
    (summary) => input.filter === "all" || summary.status === input.filter,
  );
  const items = filteredSummaries.map((summary) => ({
    ...summary,
    isCurrentProgram: summary.id === input.activeProgramId,
  }));

  if (input.filter !== "all") {
    return items;
  }

  const currentItems = items.filter((item) => item.isCurrentProgram);
  const otherItems = items.filter((item) => !item.isCurrentProgram);
  return [...currentItems, ...otherItems];
}

export function sortProgramListSummaries(summaries: ProgramListSummary[]): ProgramListSummary[] {
  return [...summaries].sort((left, right) => {
    const rightCreatedAt = timestampSortKey(right.createdAt);
    const leftCreatedAt = timestampSortKey(left.createdAt);

    if (rightCreatedAt !== leftCreatedAt) {
      return rightCreatedAt.localeCompare(leftCreatedAt);
    }

    return right.id - left.id;
  });
}

function timestampSortKey(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?)?/.exec(
    value,
  );

  if (!match) {
    return value;
  }

  const [, year, month, day, hour = "00", minute = "00", second = "00", millisecond = "000"] = match;
  return `${year}${month}${day}${hour}${minute}${second}${millisecond.padEnd(3, "0")}`;
}
