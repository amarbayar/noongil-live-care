import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../lib/auth.js';
import { reportService } from '../services/report.service.js';

const GenerateBody = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

export async function reportRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('preHandler', requireAuth);

  fastify.post('/api/reports/generate', async (request, reply) => {
    const parsed = GenerateBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: parsed.error.flatten() });
    }

    const { startDate, endDate } = parsed.data;
    // Use authenticated userId
    const report = await reportService.generateReport(request.userId!, startDate, endDate);
    return report;
  });
}
