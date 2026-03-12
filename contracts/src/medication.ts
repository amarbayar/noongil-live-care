import { z } from 'zod';

export const Medication = z.object({
  id: z.string().uuid(),
  userId: z.string(),
  name: z.string(),
  dosage: z.string().optional(),
  schedule: z.array(z.string()).default([]),
  active: z.boolean().default(true),
  createdAt: z.string().datetime(),
});

export const MedicationLog = z.object({
  id: z.string().uuid(),
  medicationId: z.string(),
  userId: z.string(),
  taken: z.boolean(),
  timestamp: z.string().datetime(),
  method: z.enum(['voice', 'manual', 'notification']).default('manual'),
});

export type Medication = z.infer<typeof Medication>;
export type MedicationLog = z.infer<typeof MedicationLog>;
