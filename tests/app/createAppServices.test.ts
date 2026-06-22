import { afterEach, describe, expect, it, vi } from "vitest";

const inMemoryServices = { mode: "memory" };

async function loadCreateAppServices(platform: string) {
  vi.resetModules();
  vi.doMock("@capacitor/core", () => ({
    Capacitor: {
      getPlatform: () => platform,
    },
  }));
  vi.doMock("../../src/infrastructure/database/createDatabaseBackedServices", () => ({
    createDatabaseBackedServices: vi.fn(() => Promise.reject(new Error("sqlite unavailable"))),
  }));
  vi.doMock("../../src/infrastructure/database/repositories/InMemoryRepositories", () => ({
    createInMemoryAppServices: vi.fn(() => inMemoryServices),
  }));

  return import("../../src/app/createAppServices");
}

describe("createAppServices", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.resetModules();
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("../../src/infrastructure/database/createDatabaseBackedServices");
    vi.doUnmock("../../src/infrastructure/database/repositories/InMemoryRepositories");
  });

  it("keeps the in-memory fallback for web startup failures", async () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const { createAppServices } = await loadCreateAppServices("web");

    await expect(createAppServices()).resolves.toBe(inMemoryServices);

    expect(warnSpy).toHaveBeenCalledWith(
      "SQLite unavailable, using deterministic in-memory services.",
      expect.any(Error),
    );
  });

  it("does not fall back to in-memory services for native startup failures", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const { createAppServices } = await loadCreateAppServices("ios");

    await expect(createAppServices()).rejects.toThrow("sqlite unavailable");

    expect(errorSpy).toHaveBeenCalledWith("SQLite unavailable on native platform.", expect.any(Error));
  });
});
