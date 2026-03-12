import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../lib/auth.js';
import { requireWellnessAccess } from '../lib/caregiver-auth.js';
import { graphService } from '../services/graph.service.js';
import { getDb } from '../services/firebase.js';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DashboardQuery = z.object({
  userId: z.string().min(1),
  start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  end: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(__dirname, '..', '..', 'public');

function parseDashboardQuery(query: unknown) {
  const parsed = DashboardQuery.safeParse(query);
  if (!parsed.success) return null;
  const end = parsed.data.end ?? new Date().toISOString().split('T')[0];
  const start = parsed.data.start ?? subtractDays(end, 30);
  return { userId: parsed.data.userId, start, end };
}

export async function dashboardRoutes(fastify: FastifyInstance): Promise<void> {
  // Serve the dashboard HTML — inject Firebase web config from env vars
  fastify.get('/dashboard', async (_request, reply) => {
    let html = await readFile(path.join(publicDir, 'dashboard.html'), 'utf-8');

    const fbConfig = buildFirebaseWebConfig();
    if (fbConfig) {
      const injection = `<script>window.__NOONGIL_FIREBASE_CONFIG__=${JSON.stringify(fbConfig)};</script>`;
      html = html.replace('</head>', `${injection}\n</head>`);
    }

    return reply.type('text/html').send(html);
  });

  // List members this caregiver can view (for the member picker)
  fastify.get('/api/dashboard/me', { preHandler: [requireAuth] }, async (request, _reply) => {
    const caregiverId = request.userId!;
    const db = getDb();

    const snap = await db.collection('caregiver_member_links')
      .where('caregiverId', '==', caregiverId)
      .get();

    const members = snap.docs
      .filter((doc) => {
        if (doc.data().status !== 'active') return false;
        const perms = (doc.data().permissions as string[] | undefined) ?? [];
        return perms.includes('wellness');
      })
      .map((doc) => {
        const data = doc.data();
        return {
          memberId: data.memberId as string,
          memberName: data.memberName as string | undefined,
          permissions: (data.permissions as string[] | undefined) ?? [],
        };
      });

    return { members, selfId: members.length > 0 ? null : caregiverId };
  });

  // All data endpoints require auth + wellness access check
  fastify.get('/api/dashboard/graph', { preHandler: [requireAuth] }, async (request, reply) => {
    const q = parseDashboardQuery(request.query);
    if (!q) return reply.status(400).send({ error: 'userId and valid date range required' });

    const permissions = await requireWellnessAccess(request, reply, q.userId);
    if (!permissions) return;

    return graphService.getFullGraph(q.userId, q.start, q.end);
  });

  fastify.get('/api/dashboard/time-series', { preHandler: [requireAuth] }, async (request, reply) => {
    const q = parseDashboardQuery(request.query);
    if (!q) return reply.status(400).send({ error: 'userId and valid date range required' });

    const permissions = await requireWellnessAccess(request, reply, q.userId);
    if (!permissions) return;

    const timeSeries = await graphService.extractTimeSeries(q.userId, q.start, q.end);
    const symptomTypes = await graphService.getSymptomTypes(q.userId, q.start, q.end);
    const symptomSeries: Record<string, (number | null)[]> = {};
    for (const type of symptomTypes) {
      symptomSeries[type] = await graphService.extractSymptomSeries(q.userId, type, q.start, q.end);
    }

    const result: Record<string, unknown> = { ...timeSeries, symptomSeries };

    // Strip medication data if caregiver lacks medications permission
    if (!permissions.includes('medications')) {
      delete result.medAdherenceSeries;
    }

    return result;
  });

  fastify.get('/api/dashboard/correlations', { preHandler: [requireAuth] }, async (request, reply) => {
    const q = parseDashboardQuery(request.query);
    if (!q) return reply.status(400).send({ error: 'userId required' });

    const permissions = await requireWellnessAccess(request, reply, q.userId);
    if (!permissions) return;

    return graphService.getCorrelations(q.userId);
  });

  fastify.get('/api/dashboard/triggers', { preHandler: [requireAuth] }, async (request, reply) => {
    const q = parseDashboardQuery(request.query);
    if (!q) return reply.status(400).send({ error: 'userId and valid date range required' });

    const permissions = await requireWellnessAccess(request, reply, q.userId);
    if (!permissions) return;

    return graphService.getTriggerFrequency(q.userId, q.start, q.end);
  });

  fastify.get('/api/dashboard/causal', { preHandler: [requireAuth] }, async (request, reply) => {
    const q = parseDashboardQuery(request.query);
    if (!q) return reply.status(400).send({ error: 'userId and valid date range required' });

    const permissions = await requireWellnessAccess(request, reply, q.userId);
    if (!permissions) return;

    const graph = await graphService.getFullGraph(q.userId, q.start, q.end);
    return graph.causalExplanations;
  });
}

function buildFirebaseWebConfig(): Record<string, string> | null {
  const apiKey = process.env.FIREBASE_WEB_API_KEY;
  const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GCP_PROJECT_ID;
  if (!apiKey || !projectId) return null;
  return {
    apiKey,
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.firebasestorage.app`,
    appId: process.env.FIREBASE_WEB_APP_ID || '',
    messagingSenderId: process.env.FIREBASE_MESSAGING_SENDER_ID || '',
    measurementId: process.env.FIREBASE_MEASUREMENT_ID || '',
  };
}

function subtractDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().split('T')[0];
}
