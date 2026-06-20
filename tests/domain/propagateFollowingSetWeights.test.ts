import { describe, expect, it } from "vitest";
import { findFollowingWeightSetIds } from "../../src/domain/workouts/rules/propagateFollowingSetWeights";

describe("findFollowingWeightSetIds", () => {
  it("targets all higher-order sets after set 1 receives a valid weight", () => {
    expect(
      findFollowingWeightSetIds({
        sets: [setDraft(1, 1), setDraft(2, 2), setDraft(3, 3), setDraft(4, 4)],
        editedSetId: 1,
        nextWeight: "100",
      }),
    ).toEqual([2, 3, 4]);
  });

  it("targets only sets after the edited set", () => {
    expect(
      findFollowingWeightSetIds({
        sets: [setDraft(1, 1), setDraft(2, 2), setDraft(3, 3), setDraft(4, 4)],
        editedSetId: 2,
        nextWeight: "200",
      }),
    ).toEqual([3, 4]);
  });

  it("includes following sets even when they already have weights", () => {
    expect(
      findFollowingWeightSetIds({
        sets: [setDraft(1, 1), setDraft(2, 2), setDraft(3, 3)],
        editedSetId: 1,
        nextWeight: "185",
      }),
    ).toEqual([2, 3]);
  });

  it("never targets earlier sets", () => {
    expect(
      findFollowingWeightSetIds({
        sets: [setDraft(1, 1), setDraft(2, 2), setDraft(3, 3)],
        editedSetId: 2,
        nextWeight: "200",
      }),
    ).toEqual([3]);
  });

  it("only targets sets from the same lift passed to the rule", () => {
    const benchSets = [setDraft(1, 1), setDraft(2, 2), setDraft(3, 3)];
    const squatSets = [setDraft(4, 1), setDraft(5, 2)];

    expect(
      findFollowingWeightSetIds({
        sets: benchSets,
        editedSetId: 1,
        nextWeight: "185",
      }),
    ).toEqual([2, 3]);
    expect(squatSets.map((set) => set.id)).toEqual([4, 5]);
  });

  it("does not propagate invalid, zero, or empty weight values", () => {
    for (const nextWeight of ["", "0", "03", "abc"]) {
      expect(
        findFollowingWeightSetIds({
          sets: [setDraft(1, 1), setDraft(2, 2)],
          editedSetId: 1,
          nextWeight,
        }),
      ).toEqual([]);
    }
  });

  it("does not propagate when reps change because no weight value is passed", () => {
    expect(
      findFollowingWeightSetIds({
        sets: [setDraft(1, 1), setDraft(2, 2)],
        editedSetId: 1,
        nextWeight: "",
      }),
    ).toEqual([]);
  });
});

function setDraft(id: number, order: number) {
  return { id, order };
}
