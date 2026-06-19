import { Capacitor } from "@capacitor/core";
import { CapacitorSQLite, SQLiteConnection, type SQLiteDBConnection } from "@capacitor-community/sqlite";
import { defineCustomElements } from "jeep-sqlite/loader";
import type { DatabaseClient } from "./DatabaseClient";

class CapacitorDatabaseClient implements DatabaseClient {
  constructor(
    private readonly db: SQLiteDBConnection,
    private readonly usesWebStore: boolean,
  ) {}

  async execute(sql: string): Promise<void> {
    await this.db.execute(sql);
  }

  async query<TRecord extends Record<string, unknown>>(sql: string, values: unknown[] = []): Promise<TRecord[]> {
    const result = await this.db.query(sql, values);
    return (result.values ?? []) as TRecord[];
  }

  async run(sql: string, values: unknown[] = []): Promise<void> {
    await this.db.run(sql, values);
  }

  async transaction<TResult>(operation: (client: DatabaseClient) => Promise<TResult>): Promise<TResult> {
    if (this.usesWebStore) {
      return operation(this);
    }

    await this.execute("BEGIN TRANSACTION");

    try {
      const result = await operation(this);
      await this.execute("COMMIT");
      return result;
    } catch (error) {
      await this.execute("ROLLBACK");
      throw error;
    }
  }
}

export async function openPowerJackDatabase(): Promise<DatabaseClient> {
  const sqlite = new SQLiteConnection(CapacitorSQLite);
  const usesWebStore = Capacitor.getPlatform() === "web";

  if (usesWebStore) {
    await setupWebSqlite(sqlite);
  }

  const databaseName = "powerjack";
  const existingConnection = await sqlite.isConnection(databaseName, false);
  const db = existingConnection.result
    ? await sqlite.retrieveConnection(databaseName, false)
    : await sqlite.createConnection(databaseName, false, "no-encryption", 1, false);

  await db.open();
  return new CapacitorDatabaseClient(db, usesWebStore);
}

async function setupWebSqlite(sqlite: SQLiteConnection): Promise<void> {
  defineCustomElements(window);

  if (!document.querySelector("jeep-sqlite")) {
    const jeepSqlite = document.createElement("jeep-sqlite");
    jeepSqlite.setAttribute("wasmPath", "/assets");
    document.body.appendChild(jeepSqlite);
    await customElements.whenDefined("jeep-sqlite");
  }

  await sqlite.initWebStore();
}
