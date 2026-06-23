import { describe, expect, it, vi } from "vitest";
import { AppRuntimeCache } from "../../src/app/AppRuntimeCache";
import type { AppState } from "../../src/domain/app-state/AppState";
import type { AppStateRepository } from "../../src/domain/app-state/AppStateRepository";
import { createIdleRestTimer } from "../../src/domain/app-state/restTimer";
import type { TemplateSummary } from "../../src/domain/templates/Template";
import type { TemplateRepository } from "../../src/domain/templates/TemplateRepository";
import type { ActiveWorkoutView } from "../../src/domain/workouts/Workout";
import type { WorkoutRepository } from "../../src/domain/workouts/WorkoutRepository";

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });

  return { promise, reject, resolve };
}

function createAppState(overrides: Partial<AppState> = {}): AppState {
  return {
    id: 1,
    activeProgramId: null,
    activeWorkoutId: null,
    activeLiftId: null,
    restTimer: createIdleRestTimer(),
    userBodyWeightLb: null,
    userBodyWeightUpdatedLast: null,
    createdAt: "2026-06-18T00:00:00.000Z",
    updatedAt: "2026-06-18T00:00:00.000Z",
    ...overrides,
  };
}

function createTemplateSummary(id: number): TemplateSummary {
  return {
    id,
    name: `Template ${id}`,
    workoutsPerWeek: 3,
    exerciseCount: 6,
    focusMuscles: [],
    usedByActiveProgram: false,
    createdAt: "2026-06-18T00:00:00.000Z",
    updatedAt: "2026-06-18T00:00:00.000Z",
  };
}

function createWorkoutView(workoutId: number, programId = 10): ActiveWorkoutView {
  return {
    program: { id: programId },
    workout: { id: workoutId },
    lifts: [],
  } as unknown as ActiveWorkoutView;
}

function createCache(overrides: {
  appState?: Partial<AppStateRepository>;
  templates?: Partial<TemplateRepository>;
  workouts?: Partial<WorkoutRepository>;
} = {}) {
  const appState = {
    load: vi.fn(() => Promise.resolve(null)),
    ...overrides.appState,
  } as unknown as AppStateRepository;
  const templates = {
    list: vi.fn(() => Promise.resolve([])),
    ...overrides.templates,
  } as unknown as TemplateRepository;
  const workouts = {
    listWorkoutIdsForProgram: vi.fn(() => Promise.resolve([])),
    loadWorkoutView: vi.fn(() => Promise.resolve(null)),
    ...overrides.workouts,
  } as unknown as WorkoutRepository;

  return {
    appState,
    cache: new AppRuntimeCache({ appState, templates, workouts }),
    templates,
    workouts,
  };
}

describe("AppRuntimeCache", () => {
  it("waits for app state and active workout during launch hydration", async () => {
    const appStateDeferred = createDeferred<AppState | null>();
    const workoutDeferred = createDeferred<ActiveWorkoutView | null>();
    const activeState = createAppState({ activeProgramId: 10, activeWorkoutId: 20 });
    const activeWorkout = createWorkoutView(20, 10);
    const { cache } = createCache({
      appState: { load: vi.fn(() => appStateDeferred.promise) },
      workouts: {
        loadWorkoutView: vi.fn(() => workoutDeferred.promise),
      },
    });
    let resolved = false;
    const hydration = cache.hydrateLaunch().then((snapshot) => {
      resolved = true;
      return snapshot;
    });

    appStateDeferred.resolve(activeState);
    await Promise.resolve();

    expect(resolved).toBe(false);

    workoutDeferred.resolve(activeWorkout);

    await expect(hydration).resolves.toEqual({
      appState: activeState,
      activeWorkout,
    });
    expect(cache.getAppStateSnapshot()).toBe(activeState);
    expect(cache.getWorkoutViewSnapshot(20)).toBe(activeWorkout);
  });

  it("warms all other persisted workouts for the active program in the background", async () => {
    const activeState = createAppState({ activeProgramId: 10, activeWorkoutId: 20 });
    const loadWorkoutView = vi.fn((workoutId: number) =>
      Promise.resolve(createWorkoutView(workoutId, 10)),
    );
    const listWorkoutIdsForProgram = vi.fn(() => Promise.resolve([20, 21, 22]));
    const { cache } = createCache({
      appState: { load: vi.fn(() => Promise.resolve(activeState)) },
      workouts: {
        listWorkoutIdsForProgram,
        loadWorkoutView,
      },
    });

    await cache.hydrateLaunch();
    await Promise.resolve();
    await Promise.resolve();

    expect(listWorkoutIdsForProgram).toHaveBeenCalledWith(10);
    expect(loadWorkoutView).toHaveBeenCalledWith(20);
    expect(loadWorkoutView).toHaveBeenCalledWith(21);
    expect(loadWorkoutView).toHaveBeenCalledWith(22);
  });

  it("starts template preload without blocking no-active-program launch hydration", async () => {
    const templatesDeferred = createDeferred<TemplateSummary[]>();
    const templates = { list: vi.fn(() => templatesDeferred.promise) };
    const { cache } = createCache({
      appState: { load: vi.fn(() => Promise.resolve(createAppState())) },
      templates,
    });

    await expect(cache.hydrateLaunch()).resolves.toEqual({
      appState: createAppState(),
      activeWorkout: null,
    });
    expect(templates.list).toHaveBeenCalledTimes(1);
    expect(cache.getTemplatesSnapshot()).toBeUndefined();

    templatesDeferred.resolve([]);
    await templatesDeferred.promise;

    expect(cache.getTemplatesSnapshot()).toEqual([]);
  });

  it("dedupes template loads and treats an empty template list as ready", async () => {
    const templatesDeferred = createDeferred<TemplateSummary[]>();
    const list = vi.fn(() => templatesDeferred.promise);
    const { cache } = createCache({ templates: { list } });
    const firstLoad = cache.loadTemplates();
    const secondLoad = cache.loadTemplates();

    expect(list).toHaveBeenCalledTimes(1);

    templatesDeferred.resolve([]);

    await expect(firstLoad).resolves.toEqual([]);
    await expect(secondLoad).resolves.toEqual([]);
    await expect(cache.loadTemplates()).resolves.toEqual([]);
    expect(list).toHaveBeenCalledTimes(1);
    expect(cache.getTemplatesSnapshot()).toEqual([]);
  });

  it("does not let invalidated in-flight template loads repopulate the snapshot", async () => {
    const staleTemplatesDeferred = createDeferred<TemplateSummary[]>();
    const freshTemplates = [createTemplateSummary(2)];
    const list = vi
      .fn<() => Promise<TemplateSummary[]>>()
      .mockReturnValueOnce(staleTemplatesDeferred.promise)
      .mockResolvedValueOnce(freshTemplates);
    const { cache } = createCache({ templates: { list } });
    const staleLoad = cache.loadTemplates();

    cache.invalidateTemplates();

    await expect(cache.refreshTemplates()).resolves.toEqual(freshTemplates);
    staleTemplatesDeferred.resolve([createTemplateSummary(1)]);
    await staleLoad;

    expect(cache.getTemplatesSnapshot()).toEqual(freshTemplates);
    expect(list).toHaveBeenCalledTimes(2);
  });

  it("clears snapshots and prevents old in-flight loads from repopulating the cache", async () => {
    const templatesDeferred = createDeferred<TemplateSummary[]>();
    const { cache } = createCache({
      templates: { list: vi.fn(() => templatesDeferred.promise) },
    });
    cache.setWorkoutView(createWorkoutView(20, 10));
    const templateLoad = cache.loadTemplates();

    cache.clear();
    templatesDeferred.resolve([createTemplateSummary(1)]);
    await templateLoad;

    expect(cache.getTemplatesSnapshot()).toBeUndefined();
    expect(cache.getWorkoutViewSnapshot(20)).toBeNull();
  });
});
