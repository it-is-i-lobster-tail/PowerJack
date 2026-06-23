import { cleanup, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

async function loadBootstrapWithMockedServices(createAppServices: () => Promise<unknown>) {
  vi.resetModules();
  vi.doMock("../../src/app/createAppServices", () => ({
    createAppServices: vi.fn(createAppServices),
  }));

  return import("../../src/app/bootstrap");
}

async function loadBootstrapWithStorageFailure() {
  return loadBootstrapWithMockedServices(() => Promise.reject(new Error("storage failed")));
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

  it("keeps the launch splash visible while launch hydration initializes", async () => {
    document.body.innerHTML = `
      <div id="powerjack-launch" data-agent-id="app-launch-splash"></div>
      <div id="root"></div>
    `;
    const { bootstrap } = await loadBootstrapWithMockedServices(() =>
      Promise.resolve({
        cache: {
          hydrateLaunch: () => new Promise<never>(() => undefined),
        },
      }),
    );

    void bootstrap();
    await Promise.resolve();
    await Promise.resolve();

    expect(document.querySelector('[data-agent-id="app-launch-splash"]')).toBeInTheDocument();
    expect(document.getElementById("root")).toBeEmptyDOMElement();
  });
});
