import { describe, expect, it } from "vitest";
import { validateProgramLengthWeeks } from "../../src/domain/programs/rules/validateProgramLengthWeeks";

describe("validateProgramLengthWeeks", () => {
  it("requires a selection", () => {
    expect(validateProgramLengthWeeks(null)).toEqual({
      ok: false,
      message: "Choose a program length.",
    });
  });

  it("accepts supported program lengths", () => {
    expect(validateProgramLengthWeeks(8)).toEqual({ ok: true });
  });

  it("rejects unsupported program lengths", () => {
    expect(validateProgramLengthWeeks(7)).toEqual({
      ok: false,
      message: "Program length must be 4, 6, 8, 10, or 12 weeks.",
    });
  });
});
