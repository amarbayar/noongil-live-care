import { z } from 'zod';

export const User = z.object({
  id: z.string(),
  displayName: z.string().optional(),
  companionName: z.string().default('Mira'),
  language: z.enum(['en', 'mn']).default('en'),
  timezone: z.string().default('America/New_York'),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

export type User = z.infer<typeof User>;
