import { describe, expect, it, vi } from "vitest";
import { SQLiteConnection } from "@capacitor-community/sqlite";
import {
  CapacitorDatabaseClient,
  openPowerJackDatabase,
} from "../../src/infrastructure/database/openDatabase";

vi.mock("@capacitor/core", () => ({
  Capacitor: {
    getPlatform: () => "ios",
  },
}));

vi.mock("@capacitor-community/sqlite", () => ({
  CapacitorSQLite: {},
  SQLiteConnection: vi.fn(),
}));

vi.mock("jeep-sqlite/loader", () => ({
  defineCustomElements: vi.fn(),
}));

type ClientConstructorArgs = ConstructorParameters<typeof CapacitorDatabaseClient>;

function createHarness(usesWebStore = false) {
  const statements: string[] = [];
  const db = {
    execute: vi.fn((sql: string) => {
      statements.push(sql);
      return Promise.resolve();
    }),
    query: vi.fn(() => Promise.resolve({ values: [] })),
    run: vi.fn((sql: string) => {
      statements.push(sql);
      return Promise.resolve();
    }),
    beginTransaction: vi.fn(() => Promise.resolve({ changes: { changes: 0 } })),
    commitTransaction: vi.fn(() => Promise.resolve({ changes: { changes: 0 } })),
    rollbackTransaction: vi.fn(() => Promise.resolve({ changes: { changes: 0 } })),
  };
  const sqlite = {
    saveToStore: vi.fn(() => Promise.resolve()),
  };
  const client = new CapacitorDatabaseClient(
    db as unknown as ClientConstructorArgs[0],
    sqlite as unknown as ClientConstructorArgs[1],
    "powerjack",
    usesWebStore,
  );

  return { client, db, sqlite, statements };
}

describe("CapacitorDatabaseClient", () => {
  it("enables foreign keys after opening the database connection", async () => {
    const db = {
      open: vi.fn(() => Promise.resolve()),
      execute: vi.fn(() => Promise.resolve()),
    };
    const sqlite = {
      isConnection: vi.fn(() => Promise.resolve({ result: false })),
      createConnection: vi.fn(() => Promise.resolve(db)),
      retrieveConnection: vi.fn(() => Promise.resolve(db)),
    };
    vi.mocked(SQLiteConnection).mockImplementation(function createSQLiteConnectionMock() {
      return sqlite as never;
    });

    await expect(openPowerJackDatabase()).resolves.toBeInstanceOf(CapacitorDatabaseClient);

    expect(sqlite.createConnection).toHaveBeenCalledWith("powerjack", false, "no-encryption", 1, false);
    expect(db.open).toHaveBeenCalledTimes(1);
    expect(db.execute).toHaveBeenCalledWith("PRAGMA foreign_keys = ON");

    const openCallOrder = db.open.mock.invocationCallOrder[0];
    const executeCallOrder = db.execute.mock.invocationCallOrder[0];

    if (openCallOrder === undefined || executeCallOrder === undefined) {
      throw new Error("Expected open and PRAGMA calls to be recorded.");
    }

    expect(openCallOrder).toBeLessThan(executeCallOrder);
  });

  it("uses native plugin transaction APIs on non-web success", async () => {
    const { client, db, statements } = createHarness(false);

    await client.transaction(async (transactionClient) => {
      await transactionClient.run("INSERT INTO templates (name) VALUES (?)", ["Push"]);
    });

    expect(db.beginTransaction).toHaveBeenCalledTimes(1);
    expect(db.commitTransaction).toHaveBeenCalledTimes(1);
    expect(db.rollbackTransaction).not.toHaveBeenCalled();
    expect(statements).toEqual(["INSERT INTO templates (name) VALUES (?)"]);
    expect(statements).not.toContain("BEGIN TRANSACTION");
    expect(statements).not.toContain("COMMIT");
    expect(statements).not.toContain("ROLLBACK");
  });

  it("rolls back native plugin transactions and preserves the operation error", async () => {
    const { client, db } = createHarness(false);
    const operationError = new Error("save failed");

    await expect(
      client.transaction(async (transactionClient) => {
        await transactionClient.run("INSERT INTO templates (name) VALUES (?)", ["Pull"]);
        throw operationError;
      }),
    ).rejects.toBe(operationError);

    expect(db.beginTransaction).toHaveBeenCalledTimes(1);
    expect(db.commitTransaction).not.toHaveBeenCalled();
    expect(db.rollbackTransaction).toHaveBeenCalledTimes(1);
  });

  it("defers web store saves until the outermost web transaction completes", async () => {
    const { client, sqlite } = createHarness(true);

    await client.transaction(async (outerClient) => {
      await outerClient.run("INSERT INTO templates (name) VALUES (?)", ["Legs"]);
      await outerClient.transaction(async (innerClient) => {
        await innerClient.run("INSERT INTO workout_templates (template_id) VALUES (?)", [1]);
      });

      expect(sqlite.saveToStore).not.toHaveBeenCalled();
    });

    expect(sqlite.saveToStore).toHaveBeenCalledTimes(1);
    expect(sqlite.saveToStore).toHaveBeenCalledWith("powerjack");
  });

  it("clears pending web store saves when a web transaction fails", async () => {
    const { client, sqlite } = createHarness(true);

    await expect(
      client.transaction(async (transactionClient) => {
        await transactionClient.run("INSERT INTO templates (name) VALUES (?)", ["Core"]);
        throw new Error("web save failed");
      }),
    ).rejects.toThrow("web save failed");

    await client.flushPendingWrites();

    expect(sqlite.saveToStore).not.toHaveBeenCalled();
  });
});
