import initSqlJs from "sql.js";
import type { DatabaseClient } from "../../src/infrastructure/database/DatabaseClient";

type SqlValue = string | number | Uint8Array | null;

interface SqlJsStatement {
  bind(values: SqlValue[]): void;
  free(): void;
  getAsObject(): Record<string, unknown>;
  step(): boolean;
}

interface SqlJsDatabase {
  prepare(sql: string): SqlJsStatement;
  run(sql: string, values?: SqlValue[]): void;
}

export class SqlJsTestDatabaseClient implements DatabaseClient {
  constructor(private readonly db: SqlJsDatabase) {}

  execute(sql: string): Promise<void> {
    try {
      this.db.run(sql);
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(toError(error));
    }
  }

  query<TRecord extends Record<string, unknown>>(
    sql: string,
    values: unknown[] = [],
  ): Promise<TRecord[]> {
    let statement: SqlJsStatement;

    try {
      statement = this.db.prepare(sql);
    } catch (error) {
      return Promise.reject(toError(error));
    }

    const rows: TRecord[] = [];

    try {
      statement.bind(values as SqlValue[]);

      while (statement.step()) {
        rows.push(statement.getAsObject() as TRecord);
      }
    } finally {
      statement.free();
    }

    return Promise.resolve(rows);
  }

  run(sql: string, values: unknown[] = []): Promise<void> {
    try {
      this.db.run(sql, values as SqlValue[]);
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(toError(error));
    }
  }

  async transaction<TResult>(operation: (client: DatabaseClient) => Promise<TResult>): Promise<TResult> {
    return operation(this);
  }
}

export async function createSqlJsTestDatabaseClient(): Promise<SqlJsTestDatabaseClient> {
  const SQL = await initSqlJs();
  const client = new SqlJsTestDatabaseClient(new SQL.Database());

  await client.execute("PRAGMA foreign_keys = ON");

  return client;
}

function toError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}
