declare module "sql.js" {
  export interface Database {
    prepare(sql: string): Statement;
    run(sql: string, params?: SqlValue[]): void;
  }

  export interface SqlJsStatic {
    Database: new () => Database;
  }

  export interface Statement {
    bind(values: SqlValue[]): void;
    free(): void;
    getAsObject(): Record<string, unknown>;
    step(): boolean;
  }

  export type SqlValue = string | number | Uint8Array | null;

  export default function initSqlJs(): Promise<SqlJsStatic>;
}
