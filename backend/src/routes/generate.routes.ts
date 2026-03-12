import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../lib/auth.js';
import { vertexAIService } from '../services/vertex-ai.service.js';

const MusicBody = z.object({
  prompt: z.string().min(1),
  negativePrompt: z.string().optional(),
});

export async function generateRoutes(fastify: FastifyInstance): Promise<void> {
  // Music generation — Lyria-002 requires Vertex AI OAuth, so it goes through the backend.
  // Image and video generation use the Gemini API key and are called directly from iOS.
  fastify.post(
    '/api/generate/music',
    { preHandler: requireAuth },
    async (request, reply) => {
      const parsed = MusicBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: parsed.error.flatten() });
      }

      const result = await vertexAIService.generateMusic(parsed.data);
      return result;
    }
  );
}
