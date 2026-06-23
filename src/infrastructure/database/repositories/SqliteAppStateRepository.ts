import type { AppState, RestTimer } from "../../../domain/app-state/AppState";
import type { AppStateRepository } from "../../../domain/app-state/AppStateRepository";
import type { DatabaseClient } from "../DatabaseClient";
import { mapAppStateRow, type AppStateRow } from "../mappers/appStateMapper";

export class SqliteAppStateRepository implements AppStateRepository {
  constructor(private readonly db: DatabaseClient) {}

  async load(): Promise<AppState | null> {
    const rows = await this.db.query<AppStateRow>("SELECT * FROM app_state WHERE id = 1");
    return rows[0] ? mapAppStateRow(rows[0]) : null;
  }

  async saveRestTimer(timer: RestTimer): Promise<AppState | null> {
    await this.db.run(
      `
        UPDATE app_state
        SET
          rest_timer_state = ?,
          rest_timer_workout_id = ?,
          rest_timer_lift_id = ?,
          rest_timer_next_set_id = ?,
          rest_timer_started_at = ?,
          rest_timer_duration_seconds = ?,
          rest_timer_remaining_seconds = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = 1
      `,
      [
        timer.state,
        timer.workoutId,
        timer.liftId,
        timer.nextSetId,
        timer.startedAt,
        timer.durationSeconds,
        timer.remainingSeconds,
      ],
    );

    return this.load();
  }

  async resetForAgent(): Promise<void> {
    await this.db.run(
      `
        UPDATE app_state
        SET
          active_program_id = NULL,
          active_workout_id = NULL,
          active_lift_id = NULL,
          rest_timer_state = 'idle',
          rest_timer_workout_id = NULL,
          rest_timer_lift_id = NULL,
          rest_timer_next_set_id = NULL,
          rest_timer_started_at = NULL,
          rest_timer_duration_seconds = 120,
          rest_timer_remaining_seconds = 0,
          user_body_weight_lb = NULL,
          user_body_weight_updated_last = NULL,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = 1
      `,
    );
  }
}
