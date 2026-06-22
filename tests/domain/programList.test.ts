import { describe, expect, it } from "vitest";
import {
  buildProgramListItems,
  sortProgramListSummaries,
  type ProgramListSummary,
} from "../../src/domain/programs/ProgramList";

describe("program list", () => {
  it("sorts newest first and breaks created_at ties by id", () => {
    expect(
      sortProgramListSummaries([
        program({ id: 1, createdAt: "2026-06-10 10:00:00" }),
        program({ id: 2, createdAt: "2026-06-11 10:00:00" }),
        program({ id: 3, createdAt: "2026-06-11 10:00:00" }),
      ]).map((item) => item.id),
    ).toEqual([3, 2, 1]);
  });

  it("pins the active program to the top when showing all programs", () => {
    const items = buildProgramListItems({
      activeProgramId: 1,
      filter: "all",
      summaries: [
        program({ id: 1, createdAt: "2026-06-10 10:00:00", status: "active" }),
        program({ id: 2, createdAt: "2026-06-11 10:00:00", status: "complete" }),
        program({ id: 3, createdAt: "2026-06-12 10:00:00", status: "halted" }),
      ],
    });

    expect(items.map((item) => item.id)).toEqual([1, 3, 2]);
    expect(items[0]?.isCurrentProgram).toBe(true);
  });

  it("filters complete and halted programs without adding an active filter", () => {
    const summaries = [
      program({ id: 1, status: "active" }),
      program({ id: 2, status: "complete" }),
      program({ id: 3, status: "halted" }),
      program({ id: 4, status: "complete", createdAt: "2026-06-12 10:00:00" }),
    ];

    expect(
      buildProgramListItems({ summaries, activeProgramId: 1, filter: "complete" }).map(
        (item) => item.id,
      ),
    ).toEqual([4, 2]);
    expect(
      buildProgramListItems({ summaries, activeProgramId: 1, filter: "halted" }).map(
        (item) => item.id,
      ),
    ).toEqual([3]);
  });
});

function program(overrides: Partial<ProgramListSummary>): ProgramListSummary {
  return {
    id: 1,
    name: "Back In Action x1",
    status: "active",
    templateName: "Back In Action",
    focusMuscles: [{ id: 1, name: "Back" }],
    progressPercent: 0,
    createdAt: "2026-06-10 10:00:00",
    updatedAt: "2026-06-10 10:00:00",
    ...overrides,
  };
}
