import { z } from 'zod';

export const SymptomEntry = z.object({
  name: z.string(),
  severity: z.number().min(1).max(5),
  notes: z.string().optional(),
});

export const MoodEntry = z.object({
  score: z.number().min(1).max(5),
  label: z.string().optional(),
});

export const SleepEntry = z.object({
  hoursSlept: z.number().min(0).max(24),
  quality: z.number().min(1).max(5).optional(),
});

export const CheckIn = z.object({
  id: z.string().uuid(),
  userId: z.string(),
  timestamp: z.string().datetime(),
  symptoms: z.array(SymptomEntry).default([]),
  mood: MoodEntry.optional(),
  sleep: SleepEntry.optional(),
  transcript: z.string().optional(),
  aiSummary: z.string().optional(),
  createdAt: z.string().datetime(),
});

export type CheckIn = z.infer<typeof CheckIn>;
export type SymptomEntry = z.infer<typeof SymptomEntry>;
export type MoodEntry = z.infer<typeof MoodEntry>;
export type SleepEntry = z.infer<typeof SleepEntry>;
