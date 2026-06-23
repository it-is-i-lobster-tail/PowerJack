import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router-dom";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { AppServices } from "../../src/app/AppServices";
import { AppProviders } from "../../src/app/providers";
import { SelectTemplatePage } from "../../src/features/start-program/pages/SelectTemplatePage";
import { useStartProgramStore } from "../../src/features/start-program/state/startProgramStore";

function createServicesWithCachedTemplates() {
  const loadTemplates = vi.fn(() => Promise.resolve([]));

  return {
    loadTemplates,
    services: {
      mode: "memory",
      cache: {
        getTemplatesSnapshot: vi.fn(() => []),
        loadTemplates,
        refreshTemplates: vi.fn(() => Promise.resolve([])),
      },
      templates: {
        isUsedByActiveProgram: vi.fn(() => Promise.resolve(false)),
        loadAggregate: vi.fn(() => Promise.resolve(null)),
        softDelete: vi.fn(() => Promise.resolve()),
      },
    } as unknown as AppServices,
  };
}

function renderSelectTemplatePage(services: AppServices): void {
  const router = createMemoryRouter(
    [
      {
        element: (
          <AppProviders services={services}>
            <SelectTemplatePage />
          </AppProviders>
        ),
        path: "/start/select-template",
      },
    ],
    { initialEntries: ["/start/select-template"] },
  );

  render(<RouterProvider router={router} />);
}

describe("template list management", () => {
  afterEach(() => {
    cleanup();
    useStartProgramStore.getState().reset();
    vi.restoreAllMocks();
  });

  it("renders cached empty templates without a loading state", async () => {
    const { loadTemplates, services } = createServicesWithCachedTemplates();

    renderSelectTemplatePage(services);

    expect(screen.getByRole("heading", { name: "No templates yet." })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Loading templates" })).not.toBeInTheDocument();
    await waitFor(() => expect(loadTemplates).toHaveBeenCalledTimes(1));
  });
});
