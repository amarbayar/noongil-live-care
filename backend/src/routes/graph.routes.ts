import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../lib/auth.js';
import { graphService } from '../services/graph.service.js';
import { causalService } from '../services/causal.service.js';
import { correlationService } from '../services/correlation.service.js';
import { alertService } from '../services/alert.service.js';

const IngestBody = z.object({
  eventId: z.string().min(1),
  userId: z.string().min(1),
  checkIn: z.object({
    id: z.string().min(1),
    userId: z.string().min(1),
    type: z.string(),
    completedAt: z.string().datetime(),
    completionStatus: z.string(),
    durationSeconds: z.number().optional(),
    mood: z.object({
      score: z.number().min(1).max(5),
      description: z.string().optional(),
    }).optional(),
    sleep: z.object({
      hours: z.number().min(0).max(24),
      quality: z.number().min(1).max(5).optional(),
      interruptions: z.number().optional(),
    }).optional(),
    symptoms: z.array(z.object({
      type: z.string(),
      severity: z.number().min(1).max(5).optional(),
      location: z.string().optional(),
      duration: z.string().optional(),
    })).optional(),
    medicationAdherence: z.array(z.object({
      medicationName: z.string(),
      status: z.string(),
      scheduledTime: z.string().optional(),
      takenAt: z.string().optional(),
      delayMinutes: z.number().optional(),
    })).optional(),
    triggers: z.array(z.object({
      name: z.string(),
      type: z.string().optional(),
    })).optional(),
    activities: z.array(z.object({
      name: z.string(),
      duration: z.string().optional(),
      intensity: z.string().optional(),
    })).optional(),
    concerns: z.array(z.object({
      text: z.string(),
      theme: z.string().optional(),
      urgency: z.string().optional(),
    })).optional(),
  }),
});

const GraphDataQuery = z.object({
  start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  end: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

export async function graphRoutes(fastify: FastifyInstance): Promise<void> {
  // All graph routes require authentication
  fastify.addHook('preHandler', requireAuth);

  fastify.post('/api/graph/ingest', async (request, reply) => {
    const parsed = IngestBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: parsed.error.flatten() });
    }

    const { eventId, userId, checkIn } = parsed.data;

    // Verify the authenticated user owns this data
    if (request.userId !== userId) {
      return reply.status(403).send({ error: 'Cannot ingest data for another user' });
    }

    const ingestResult = await graphService.ingestCheckIn(userId, eventId, checkIn);

    if (!ingestResult.duplicate) {
      const date = checkIn.completedAt.split('T')[0];
      await graphService.updateDayComposite(userId, date);

      // Build causal edges in background — don't block the response
      causalService.buildCausalEdges(userId).catch((err) => {
        fastify.log.error({ err, userId }, 'Causal edge build failed');
      });

      // Run correlation analysis in background
      correlationService.computeForUser(userId).catch((err) => {
        fastify.log.error({ err, userId }, 'Correlation computation failed');
      });

      // Emit health metrics to Datadog
      alertService.emitCheckInMetrics(userId, checkIn).catch((err) => {
        fastify.log.error({ err, userId }, 'Datadog metric emission failed');
      });
    }

    return {
      status: 'ok',
      eventId,
      checkInId: checkIn.id,
      duplicate: ingestResult.duplicate,
    };
  });

  fastify.get('/api/graph/data', async (request, reply) => {
    const parsed = GraphDataQuery.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({ error: parsed.error.flatten() });
    }

    const { start, end } = parsed.data;
    // Use authenticated userId — ignore query param
    const data = await graphService.getGraphData(request.userId!, start, end);
    return { data };
  });

  fastify.get('/api/graph/correlations', async (_request, reply) => {
    // Use authenticated userId — no query param needed
    const correlations = await graphService.getCorrelations(_request.userId!);
    return { correlations };
  });
}
