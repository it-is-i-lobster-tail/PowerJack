import { create } from "zustand";

interface StartProgramState {
  selectedTemplateId: number | null;
  programLengthWeeks: number | null;
  setSelectedTemplateId: (value: number) => void;
  setProgramLengthWeeks: (value: number) => void;
  reset: () => void;
}

export const useStartProgramStore = create<StartProgramState>((set) => ({
  selectedTemplateId: null,
  programLengthWeeks: null,
  setSelectedTemplateId: (selectedTemplateId) => set({ selectedTemplateId }),
  setProgramLengthWeeks: (programLengthWeeks) => set({ programLengthWeeks }),
  reset: () => set({ selectedTemplateId: null, programLengthWeeks: null }),
}));
