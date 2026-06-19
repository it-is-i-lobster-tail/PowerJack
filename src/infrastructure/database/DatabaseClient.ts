export interface DatabaseClient {
  execute(sql: string): Promise<void>;
  query<TRecord extends Record<string, unknown>>(sql: string, values?: unknown[]): Promise<TRecord[]>;
  run(sql: string, values?: unknown[]): Promise<void>;
  transaction<TResult>(operation: (client: DatabaseClient) => Promise<TResult>): Promise<TResult>;
}
