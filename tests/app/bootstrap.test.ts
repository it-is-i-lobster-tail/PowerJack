import { cleanup, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

async function loadBootstrapWithStorageFailure() {
  vi.resetModules();
  vi.doMock("../../src/app/createAppServices", () => ({
    createAppServices: vi.fn(() => Promise.reject(new Error("storage failed"))),
  }));

  return import("../../src/app/bootstrap");
}

describe("bootstrap", () => {
  beforeEach(() => {
    document.body.innerHTML = '<div id="root"></div>';
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.resetModules();
    vi.doUnmock("../../src/app/createAppServices");
  });

  it("renders a blocking persistence failure screen when storage startup fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const { bootstrap } = await loadBootstrapWithStorageFailure();

    await bootstrap();

    expect(await screen.findByRole("heading", { name: "Storage unavailable" })).toBeInTheDocument();
    expect(document.querySelector('[data-agent-id="persistence-unavailable"]')).toBeInTheDocument();
  });
});
