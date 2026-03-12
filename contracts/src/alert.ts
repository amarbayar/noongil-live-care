import { z } from 'zod';

export const Alert = z.object({
  id: z.string().uuid(),
  userId: z.string(),
  type: z.enum(['missed_checkin', 'symptom_spike', 'medication_missed', 'custom']),
  severity: z.enum(['info', 'warning', 'urgent']),
  message: z.string(),
  acknowledged: z.boolean().default(false),
  createdAt: z.string().datetime(),
});

export type Alert = z.infer<typeof Alert>;
