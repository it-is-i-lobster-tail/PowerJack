import type { AppState } from "../domain/app-state/AppState";
import type { AppStateRepository } from "../domain/app-state/AppStateRepository";
import type { EntityId } from "../domain/ids";
import type { TemplateSummary } from "../domain/templates/Template";
import type { TemplateRepository } from "../domain/templates/TemplateRepository";
import type { ActiveWorkoutView } from "../domain/workouts/Workout";
import type { WorkoutRepository } from "../domain/workouts/WorkoutRepository";

export interface LaunchHydrationSnapshot {
  appState: AppState | null;
  activeWorkout: ActiveWorkoutView | null;
}

interface AppRuntimeCacheDependencies {
  appState: AppStateRepository;
  templates: TemplateRepository;
  workouts: WorkoutRepository;
}

export class AppRuntimeCache {
  private appStatePromise: Promise<AppState | null> | null = null;
  private appStateSnapshot: AppState | null | undefined;
  private readonly backgroundProgramPreloads = new Map<EntityId, Promise<void>>();
  private generation = 0;
  private templatesGeneration = 0;
  private templatesPromise: Promise<TemplateSummary[]> | null = null;
  private templatesSnapshot: TemplateSummary[] | undefined;
  private readonly workoutPromises = new Map<EntityId, Promise<ActiveWorkoutView | null>>();
  private readonly workoutSnapshots = new Map<EntityId, ActiveWorkoutView>();

  constructor(private readonly dependencies: AppRuntimeCacheDependencies) {}

  async hydrateLaunch(): Promise<LaunchHydrationSnapshot> {
    const appState = await this.refreshAppState();
    let activeWorkout: ActiveWorkoutView | null = null;

    if (appState?.activeWorkoutId) {
      activeWorkout = await this.loadWorkoutView(appState.activeWorkoutId);
    }

    if (appState?.activeProgramId) {
      this.preloadActiveProgramWorkouts(appState.activeProgramId, appState.activeWorkoutId);
    } else {
      void this.loadTemplates().catch(() => undefined);
    }

    return { appState, activeWorkout };
  }

  getAppStateSnapshot(): AppState | null | undefined {
    return this.appStateSnapshot;
  }

  refreshAppState(): Promise<AppState | null> {
    if (this.appStatePromise) {
      return this.appStatePromise;
    }

    const generation = this.generation;
    const promise = this.dependencies.appState
      .load()
      .then((appState) => {
        if (this.generation === generation) {
          this.appStateSnapshot = appState;
        }

        return appState;
      })
      .finally(() => {
        if (this.appStatePromise === promise) {
          this.appStatePromise = null;
        }
      });

    this.appStatePromise = promise;
    return promise;
  }

  getWorkoutViewSnapshot(id: EntityId): ActiveWorkoutView | null {
    return this.workoutSnapshots.get(id) ?? null;
  }

  loadWorkoutView(id: EntityId): Promise<ActiveWorkoutView | null> {
    const existingPromise = this.workoutPromises.get(id);

    if (existingPromise) {
      return existingPromise;
    }

    const generation = this.generation;
    const promise = this.dependencies.workouts
      .loadWorkoutView(id)
      .then((view) => {
        if (this.generation !== generation) {
          return view;
        }

        if (view) {
          this.setWorkoutView(view);
        } else {
          this.workoutSnapshots.delete(id);
        }

        return view;
      })
      .finally(() => {
        if (this.workoutPromises.get(id) === promise) {
          this.workoutPromises.delete(id);
        }
      });

    this.workoutPromises.set(id, promise);
    return promise;
  }

  setWorkoutView(view: ActiveWorkoutView): void {
    this.workoutSnapshots.set(view.workout.id, view);
  }

  invalidateActiveProgramWorkouts(): void {
    const activeProgramId = this.appStateSnapshot?.activeProgramId;

    if (!activeProgramId) {
      this.workoutSnapshots.clear();
      return;
    }

    for (const [workoutId, view] of this.workoutSnapshots.entries()) {
      if (view.program.id === activeProgramId) {
        this.workoutSnapshots.delete(workoutId);
      }
    }
  }

  getTemplatesSnapshot(): TemplateSummary[] | undefined {
    return this.templatesSnapshot;
  }

  loadTemplates(): Promise<TemplateSummary[]> {
    if (this.templatesSnapshot !== undefined) {
      return Promise.resolve(this.templatesSnapshot);
    }

    if (this.templatesPromise) {
      return this.templatesPromise;
    }

    return this.refreshTemplates();
  }

  refreshTemplates(): Promise<TemplateSummary[]> {
    if (this.templatesPromise) {
      return this.templatesPromise;
    }

    const generation = this.generation;
    const templatesGeneration = this.templatesGeneration;
    const promise = this.dependencies.templates
      .list()
      .then((templates) => {
        if (this.generation === generation && this.templatesGeneration === templatesGeneration) {
          this.templatesSnapshot = templates;
        }

        return templates;
      })
      .finally(() => {
        if (this.templatesPromise === promise) {
          this.templatesPromise = null;
        }
      });

    this.templatesPromise = promise;
    return promise;
  }

  invalidateTemplates(): void {
    this.templatesGeneration += 1;
    this.templatesPromise = null;
    this.templatesSnapshot = undefined;
  }

  clear(): void {
    this.generation += 1;
    this.appStatePromise = null;
    this.appStateSnapshot = undefined;
    this.backgroundProgramPreloads.clear();
    this.templatesGeneration += 1;
    this.templatesPromise = null;
    this.templatesSnapshot = undefined;
    this.workoutPromises.clear();
    this.workoutSnapshots.clear();
  }

  private preloadActiveProgramWorkouts(
    programId: EntityId,
    currentWorkoutId: EntityId | null,
  ): void {
    if (this.backgroundProgramPreloads.has(programId)) {
      return;
    }

    const preload = this.dependencies.workouts
      .listWorkoutIdsForProgram(programId)
      .then(async (workoutIds) => {
        await Promise.all(
          workoutIds
            .filter((workoutId) => workoutId !== currentWorkoutId)
            .map(async (workoutId) => {
              try {
                await this.loadWorkoutView(workoutId);
              } catch {
                // Background cache warming must never block or expose workout data.
              }
            }),
        );
      })
      .catch(() => undefined)
      .finally(() => {
        if (this.backgroundProgramPreloads.get(programId) === preload) {
          this.backgroundProgramPreloads.delete(programId);
        }
      });

    this.backgroundProgramPreloads.set(programId, preload);
  }
}
