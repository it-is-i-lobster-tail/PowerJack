import type { DatabaseClient } from "./DatabaseClient";
import { databaseMigrations } from "./migrations";

export async function runMigrations(db: DatabaseClient): Promise<void> {
  await db.execute(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
  `);

  for (const migration of databaseMigrations) {
    const existing = await db.query<{ id: number }>("SELECT id FROM schema_migrations WHERE id = ?", [
      migration.id,
    ]);

    if (existing.length > 0) {
      continue;
    }

    await db.execute(migration.sql);
    await db.run("INSERT INTO schema_migrations (id, name) VALUES (?, ?)", [
      migration.id,
      migration.name,
    ]);
  }
}
