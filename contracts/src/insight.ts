import { z } from 'zod';

export const Insight = z.object({
  id: z.string().uuid(),
  userId: z.string(),
  type: z.enum(['correlation', 'trend', 'anomaly']),
  description: z.string(),
  confidence: z.number().min(0).max(1),
  factorA: z.string(),
  factorB: z.string(),
  surfacedAt: z.string().datetime(),
  dismissed: z.boolean().default(false),
});

export type Insight = z.infer<typeof Insight>;
