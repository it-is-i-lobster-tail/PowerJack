const allowedProgramLengths = new Set([4, 6, 8, 10, 12]);

export interface ValidationResult {
  ok: boolean;
  message?: string;
}

export function validateProgramLengthWeeks(value: number | null): ValidationResult {
  if (!value) {
    return { ok: false, message: "Choose a program length." };
  }

  if (!allowedProgramLengths.has(value)) {
    return { ok: false, message: "Program length must be 4, 6, 8, 10, or 12 weeks." };
  }

  return { ok: true };
}
