import type { AppState } from "../../../domain/app-state/AppState";
import type { AppStateRepository } from "../../../domain/app-state/AppStateRepository";
import type { DatabaseClient } from "../DatabaseClient";
import { mapAppStateRow, type AppStateRow } from "../mappers/appStateMapper";

export class SqliteAppStateRepository implements AppStateRepository {
  constructor(private readonly db: DatabaseClient) {}

  async load(): Promise<AppState | null> {
    const rows = await this.db.query<AppStateRow>("SELECT * FROM app_state WHERE id = 1");
    return rows[0] ? mapAppStateRow(rows[0]) : null;
  }

  async resetForAgent(): Promise<void> {
    await this.db.run(
      `
        UPDATE app_state
        SET
          active_program_id = NULL,
          active_workout_id = NULL,
          active_lift_id = NULL,
          user_body_weight_lb = NULL,
          user_body_weight_updated_last = NULL,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = 1
      `,
    );
  }
}
