import type { EntityId } from "../../ids";

export interface WeightPropagationSet {
  id: EntityId;
  order: number;
}

export interface FindFollowingWeightSetIdsInput {
  sets: readonly WeightPropagationSet[];
  editedSetId: EntityId;
  nextWeight: string;
}

export function findFollowingWeightSetIds(input: FindFollowingWeightSetIdsInput): EntityId[] {
  if (!isValidWeightForPropagation(input.nextWeight)) {
    return [];
  }

  const editedSet = input.sets.find((set) => set.id === input.editedSetId);

  if (!editedSet) {
    return [];
  }

  return input.sets
    .filter((set) => set.order > editedSet.order)
    .sort((left, right) => left.order - right.order)
    .map((set) => set.id);
}

function isValidWeightForPropagation(value: string): boolean {
  return /^[1-9]\d*$/.test(value);
}
