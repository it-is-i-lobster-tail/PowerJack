import { Capacitor } from "@capacitor/core";
import { CapacitorSQLite, SQLiteConnection, type SQLiteDBConnection } from "@capacitor-community/sqlite";
import { defineCustomElements } from "jeep-sqlite/loader";
import type { DatabaseClient } from "./DatabaseClient";

export class CapacitorDatabaseClient implements DatabaseClient {
  private hasPendingWebStoreSave = false;
  private nativeTransactionDepth = 0;
  private webPersistenceSuspendDepth = 0;
  private webTransactionDepth = 0;

  constructor(
    private readonly db: SQLiteDBConnection,
    private readonly sqlite: SQLiteConnection,
    private readonly databaseName: string,
    private readonly usesWebStore: boolean,
  ) {}

  async execute(sql: string): Promise<void> {
    if (this.nativeTransactionDepth > 0) {
      await this.db.execute(sql, false);
    } else {
      await this.db.execute(sql);
    }

    await this.queueWebStoreSave();
  }

  async query<TRecord extends Record<string, unknown>>(sql: string, values: unknown[] = []): Promise<TRecord[]> {
    const result = await this.db.query(sql, values);
    return (result.values ?? []) as TRecord[];
  }

  async run(sql: string, values: unknown[] = []): Promise<void> {
    if (this.nativeTransactionDepth > 0) {
      await this.db.run(sql, values, false);
    } else {
      await this.db.run(sql, values);
    }

    await this.queueWebStoreSave();
  }

  async transaction<TResult>(operation: (client: DatabaseClient) => Promise<TResult>): Promise<TResult> {
    if (this.usesWebStore) {
      this.webTransactionDepth += 1;

      try {
        const result = await operation(this);
        this.webTransactionDepth -= 1;

        if (this.webTransactionDepth === 0) {
          await this.flushWebStoreSave();
        }

        return result;
      } catch (error) {
        this.webTransactionDepth -= 1;

        if (this.webTransactionDepth === 0) {
          this.hasPendingWebStoreSave = false;
        }

        throw error;
      }
    }

    if (this.nativeTransactionDepth > 0) {
      this.nativeTransactionDepth += 1;

      try {
        return await operation(this);
      } finally {
        this.nativeTransactionDepth -= 1;
      }
    }

    await this.db.beginTransaction();
    this.nativeTransactionDepth = 1;

    try {
      const result = await operation(this);
      await this.db.commitTransaction();
      return result;
    } catch (error) {
      try {
        await this.db.rollbackTransaction();
      } catch (rollbackError) {
        console.error("Failed to rollback SQLite transaction", rollbackError);
      }

      throw error;
    } finally {
      this.nativeTransactionDepth = 0;
    }
  }

  async suspendPersistence<TResult>(operation: () => Promise<TResult>): Promise<TResult> {
    this.webPersistenceSuspendDepth += 1;

    try {
      return await operation();
    } finally {
      this.webPersistenceSuspendDepth -= 1;
    }
  }

  async flushPendingWrites(): Promise<void> {
    if (this.webTransactionDepth > 0) {
      return;
    }

    await this.flushWebStoreSave();
  }

  private async queueWebStoreSave(): Promise<void> {
    if (!this.usesWebStore) {
      return;
    }

    if (this.webPersistenceSuspendDepth > 0) {
      return;
    }

    this.hasPendingWebStoreSave = true;

    if (this.webTransactionDepth > 0) {
      return;
    }

    await this.flushWebStoreSave();
  }

  private async flushWebStoreSave(): Promise<void> {
    if (!this.usesWebStore || !this.hasPendingWebStoreSave) {
      return;
    }

    await this.sqlite.saveToStore(this.databaseName);
    this.hasPendingWebStoreSave = false;
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
  await db.execute("PRAGMA foreign_keys = ON");

  return new CapacitorDatabaseClient(db, sqlite, databaseName, usesWebStore);
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
