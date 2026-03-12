import { describe, it, expect, vi, beforeAll, afterAll, beforeEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

// Mock firebase before importing routes
vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(() => ({ collection: vi.fn() })),
}));

// Mock auth — let requests through with a userId
vi.mock('../src/lib/auth.js', () => ({
  requireAuth: vi.fn(async (request: any, _reply: any) => {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return _reply.status(401).send({ error: 'Missing or malformed Authorization header' });
    }
    request.userId = 'user1';
  }),
}));

// Mock graph service — use vi.hoisted to avoid reference-before-init
const { mockIngestCheckIn, mockUpdateDayComposite, mockGetGraphData, mockGetCorrelations } =
  vi.hoisted(() => ({
    mockIngestCheckIn: vi.fn().mockResolvedValue({ duplicate: false }),
    mockUpdateDayComposite: vi.fn().mockResolvedValue(3.5),
    mockGetGraphData: vi.fn().mockResolvedValue([]),
    mockGetCorrelations: vi.fn().mockResolvedValue([]),
  }));

vi.mock('../src/services/graph.service.js', () => ({
  graphService: {
    ingestCheckIn: mockIngestCheckIn,
    updateDayComposite: mockUpdateDayComposite,
    getGraphData: mockGetGraphData,
    getCorrelations: mockGetCorrelations,
  },
}));

// Mock causal service
const { mockBuildCausalEdges } = vi.hoisted(() => ({
  mockBuildCausalEdges: vi.fn().mockResolvedValue({ created: 0, spikesFound: 0 }),
}));

vi.mock('../src/services/causal.service.js', () => ({
  causalService: {
    buildCausalEdges: mockBuildCausalEdges,
  },
}));

// Mock correlation service
const { mockComputeForUser } = vi.hoisted(() => ({
  mockComputeForUser: vi.fn().mockResolvedValue([]),
}));

vi.mock('../src/services/correlation.service.js', () => ({
  correlationService: {
    computeForUser: mockComputeForUser,
  },
}));

// Mock alert service
vi.mock('../src/services/alert.service.js', () => ({
  alertService: {
    emitCheckInMetrics: vi.fn().mockResolvedValue(undefined),
  },
}));

// Mock report service
const { mockGenerateReport } = vi.hoisted(() => ({
  mockGenerateReport: vi.fn().mockResolvedValue({
    userId: 'user1',
    startDate: '2026-02-01',
    endDate: '2026-02-28',
    checkInCount: 10,
    executiveSummary: 'Test summary',
    moodTimeSeries: [],
    sleepTimeSeries: [],
    symptomTimeSeries: {},
    overallAdherencePercent: 90,
    perMedicationAdherence: [],
    correlations: [],
    concerns: [],
  }),
}));

vi.mock('../src/services/report.service.js', () => ({
  reportService: {
    generateReport: mockGenerateReport,
  },
}));

import { graphRoutes } from '../src/routes/graph.routes.js';
import { reportRoutes } from '../src/routes/report.routes.js';

const authHeaders = { authorization: 'Bearer valid-token' };

describe('API Routes', () => {
  let fastify: FastifyInstance;

  beforeAll(async () => {
    fastify = Fastify();
    await fastify.register(graphRoutes);
    await fastify.register(reportRoutes);
    await fastify.ready();
  });

  afterAll(async () => {
    await fastify.close();
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  // MARK: - Auth

  describe('Authentication', () => {
    it('returns 401 on missing Authorization header', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        payload: {},
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns 401 on GET /api/graph/data without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/graph/data?start=2026-02-01&end=2026-02-28',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns 401 on GET /api/graph/correlations without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/graph/correlations',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns 401 on POST /api/reports/generate without auth', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/reports/generate',
        payload: { startDate: '2026-02-01', endDate: '2026-02-28' },
      });
      expect(response.statusCode).toBe(401);
    });
  });

  // MARK: - Ownership

  describe('Ownership check', () => {
    it('returns 403 when ingest userId does not match authenticated user', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: {
          eventId: 'ci-001_graph_sync',
          userId: 'other-user',
          checkIn: {
            id: 'ci-001',
            userId: 'other-user',
            type: 'morning',
            completedAt: '2026-02-15T08:30:00Z',
            completionStatus: 'completed',
            mood: { score: 4 },
          },
        },
      });
      expect(response.statusCode).toBe(403);
    });
  });

  // MARK: - Graph Ingest

  describe('POST /api/graph/ingest', () => {
    const validBody = {
      eventId: 'ci-001_graph_sync',
      userId: 'user1',
      checkIn: {
        id: 'ci-001',
        userId: 'user1',
        type: 'morning',
        completedAt: '2026-02-15T08:30:00Z',
        completionStatus: 'completed',
        mood: { score: 4 },
      },
    };

    it('should return 200 on valid ingest', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: validBody,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.status).toBe('ok');
      expect(body.eventId).toBe('ci-001_graph_sync');
      expect(body.checkInId).toBe('ci-001');
      expect(body.duplicate).toBe(false);
      expect(mockIngestCheckIn).toHaveBeenCalledWith('user1', 'ci-001_graph_sync', validBody.checkIn);
    });

    it('should return 400 on missing userId', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: { checkIn: validBody.checkIn },
      });

      expect(response.statusCode).toBe(400);
    });

    it('should accept extended payload with triggers, activities, concerns', async () => {
      const extendedBody = {
        eventId: 'ci-003_graph_sync',
        userId: 'user1',
        checkIn: {
          id: 'ci-003',
          userId: 'user1',
          type: 'evening',
          completedAt: '2026-02-15T18:00:00Z',
          completionStatus: 'completed',
          mood: { score: 3 },
          triggers: [{ name: 'plumber noise', type: 'environmental' }],
          activities: [{ name: 'walking', duration: '30 minutes', intensity: 'moderate' }],
          concerns: [{ text: 'worried about falling', theme: 'mobility', urgency: 'medium' }],
        },
      };

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: extendedBody,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.status).toBe('ok');
      expect(body.eventId).toBe('ci-003_graph_sync');
      expect(body.checkInId).toBe('ci-003');
      expect(mockIngestCheckIn).toHaveBeenCalledWith('user1', 'ci-003_graph_sync', extendedBody.checkIn);
    });

    it('should run correlation after non-duplicate ingest', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: validBody,
      });

      expect(response.statusCode).toBe(200);
      // Give background tasks a tick to fire
      await new Promise((r) => setTimeout(r, 10));
      expect(mockComputeForUser).toHaveBeenCalledWith('user1');
    });

    it('should not run correlation on duplicate ingest', async () => {
      mockIngestCheckIn.mockResolvedValueOnce({ duplicate: true });

      await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: validBody,
      });

      await new Promise((r) => setTimeout(r, 10));
      expect(mockComputeForUser).not.toHaveBeenCalled();
    });

    it('should return duplicate response without recomputing day aggregates', async () => {
      mockIngestCheckIn.mockResolvedValueOnce({ duplicate: true });

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: validBody,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.duplicate).toBe(true);
      expect(mockUpdateDayComposite).not.toHaveBeenCalled();
    });

    it('should return 400 on invalid checkIn', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/graph/ingest',
        headers: authHeaders,
        payload: { userId: 'user1', checkIn: { id: '' } },
      });

      expect(response.statusCode).toBe(400);
    });
  });

  // MARK: - Graph Data

  describe('GET /api/graph/data', () => {
    it('should return 200 with valid query params', async () => {
      mockGetGraphData.mockResolvedValueOnce([
        { date: '2026-02-15', avgMood: 4, avgSleep: 7 },
      ]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/graph/data?start=2026-02-01&end=2026-02-28',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.data).toBeDefined();
      // Verify it uses authenticated userId
      expect(mockGetGraphData).toHaveBeenCalledWith('user1', '2026-02-01', '2026-02-28');
    });

    it('should return 400 on invalid date format', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/graph/data?start=Feb-01&end=2026-02-28',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(400);
    });
  });

  // MARK: - Correlations

  describe('GET /api/graph/correlations', () => {
    it('should return 200 with correlations', async () => {
      mockGetCorrelations.mockResolvedValueOnce([
        { sourceLabel: 'sleepHours', targetLabel: 'tremor', correlation: -0.6, lag: 0, pValue: 0.03, sampleSize: 28, method: 'pearson' },
      ]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/graph/correlations',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.correlations).toBeDefined();
      expect(mockGetCorrelations).toHaveBeenCalledWith('user1');
    });
  });

  // MARK: - Report Generation

  describe('POST /api/reports/generate', () => {
    it('should return 200 with report', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/reports/generate',
        headers: authHeaders,
        payload: {
          startDate: '2026-02-01',
          endDate: '2026-02-28',
        },
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.userId).toBe('user1');
      expect(body.executiveSummary).toBeDefined();
      // Verify it uses authenticated userId
      expect(mockGenerateReport).toHaveBeenCalledWith('user1', '2026-02-01', '2026-02-28');
    });

    it('should return 400 on invalid date', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/reports/generate',
        headers: authHeaders,
        payload: {
          startDate: 'not-a-date',
          endDate: '2026-02-28',
        },
      });

      expect(response.statusCode).toBe(400);
    });
  });
});
