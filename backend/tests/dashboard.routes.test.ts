import { describe, it, expect, vi, beforeAll, afterAll, beforeEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

// Mock firebase
const { mockCollectionGroupGet } = vi.hoisted(() => ({
  mockCollectionGroupGet: vi.fn(),
}));

vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(() => ({
    collection: vi.fn((name: string) => {
      if (name === 'caregiver_member_links') {
        return {
          where: vi.fn(() => ({
            get: mockCollectionGroupGet,
          })),
        };
      }

      return {
        where: vi.fn(() => ({
          get: vi.fn(),
        })),
      };
    }),
    collectionGroup: vi.fn(() => ({
      where: vi.fn(() => ({
        get: mockCollectionGroupGet,
      })),
    })),
  })),
}));

// Mock auth — supports a custom header to set userId for test flexibility
vi.mock('../src/lib/auth.js', () => ({
  requireAuth: vi.fn(async (request: any, _reply: any) => {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return _reply.status(401).send({ error: 'Missing or malformed Authorization header' });
    }
    request.userId = request.headers['x-test-user-id'] ?? 'auth-user';
  }),
}));

// Mock caregiver-auth — default: allow access with all permissions
const { mockRequireWellnessAccess } = vi.hoisted(() => ({
  mockRequireWellnessAccess: vi.fn().mockResolvedValue(['medications', 'reminders', 'schedule', 'wellness']),
}));

vi.mock('../src/lib/caregiver-auth.js', () => ({
  requireWellnessAccess: mockRequireWellnessAccess,
  getRelationship: vi.fn(),
  ALL_PERMISSIONS: ['medications', 'reminders', 'schedule', 'wellness'],
}));

// Mock graph service
const {
  mockGetFullGraph,
  mockExtractTimeSeries,
  mockGetSymptomTypes,
  mockExtractSymptomSeries,
  mockGetCorrelations,
  mockGetTriggerFrequency,
} = vi.hoisted(() => ({
  mockGetFullGraph: vi.fn().mockResolvedValue({
    nodes: [],
    edges: [],
    causalExplanations: [],
  }),
  mockExtractTimeSeries: vi.fn().mockResolvedValue({
    dates: [],
    moodSeries: [],
    sleepHoursSeries: [],
    sleepQualitySeries: [],
    medAdherenceSeries: [],
  }),
  mockGetSymptomTypes: vi.fn().mockResolvedValue([]),
  mockExtractSymptomSeries: vi.fn().mockResolvedValue([]),
  mockGetCorrelations: vi.fn().mockResolvedValue([]),
  mockGetTriggerFrequency: vi.fn().mockResolvedValue([]),
}));

vi.mock('../src/services/graph.service.js', () => ({
  graphService: {
    getFullGraph: mockGetFullGraph,
    extractTimeSeries: mockExtractTimeSeries,
    getSymptomTypes: mockGetSymptomTypes,
    extractSymptomSeries: mockExtractSymptomSeries,
    getCorrelations: mockGetCorrelations,
    getTriggerFrequency: mockGetTriggerFrequency,
  },
}));

import { dashboardRoutes } from '../src/routes/dashboard.routes.js';

const authHeaders = { authorization: 'Bearer valid-token' };

describe('Dashboard Routes', () => {
  let fastify: FastifyInstance;

  beforeAll(async () => {
    fastify = Fastify();
    await fastify.register(dashboardRoutes);
    await fastify.ready();
  });

  afterAll(async () => {
    await fastify.close();
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // Default: allow access with all permissions
    mockRequireWellnessAccess.mockResolvedValue(['medications', 'reminders', 'schedule', 'wellness']);
    mockCollectionGroupGet.mockReset();
    mockCollectionGroupGet.mockResolvedValue({ docs: [] });
  });

  describe('GET /dashboard (HTML)', () => {
    it('serves dashboard HTML without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/dashboard',
      });
      expect(response.statusCode).not.toBe(401);
    });
  });

  describe('Authorization', () => {
    it('lists only active wellness-enabled members on /api/dashboard/me', async () => {
      mockCollectionGroupGet.mockResolvedValueOnce({
        docs: [
          {
            data: () => ({
              memberId: 'member-active',
              memberName: 'Active Member',
              permissions: ['wellness', 'reminders'],
              status: 'active',
            }),
          },
          {
            data: () => ({
              memberId: 'member-inactive',
              memberName: 'Inactive Member',
              permissions: ['wellness'],
              status: 'revoked',
            }),
          },
          {
            data: () => ({
              memberId: 'member-no-wellness',
              memberName: 'No Wellness',
              permissions: ['reminders'],
              status: 'active',
            }),
          },
        ],
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/me',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.members).toEqual([
        {
          memberId: 'member-active',
          memberName: 'Active Member',
          permissions: ['wellness', 'reminders'],
        },
      ]);
      expect(body.selfId).toBeNull();
    });

    it('exposes selfId only when no shared members are available', async () => {
      mockCollectionGroupGet.mockResolvedValueOnce({ docs: [] });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/me',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.members).toEqual([]);
      expect(body.selfId).toBe('auth-user');
    });

    it('returns 403 if no relationship and not self-access', async () => {
      mockRequireWellnessAccess.mockImplementationOnce(async (_req: any, reply: any, _memberId: string) => {
        reply.status(403).send({ error: 'No active caregiver relationship' });
        return null;
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph?userId=other-user',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(403);
    });

    it('returns 403 if caregiver lacks wellness permission', async () => {
      mockRequireWellnessAccess.mockImplementationOnce(async (_req: any, reply: any, _memberId: string) => {
        reply.status(403).send({ error: 'Missing wellness permission' });
        return null;
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/time-series?userId=other-user',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(403);
    });

    it('allows self-access (userId matches auth user)', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph?userId=auth-user',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      expect(mockRequireWellnessAccess).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        'auth-user'
      );
    });

    it('allows caregiver with wellness permission', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/correlations?userId=member1',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      expect(mockRequireWellnessAccess).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        'member1'
      );
    });
  });

  describe('Permission-scoped data filtering', () => {
    it('strips medAdherenceSeries when caregiver lacks medications permission', async () => {
      mockRequireWellnessAccess.mockResolvedValueOnce(['wellness', 'schedule']);
      mockExtractTimeSeries.mockResolvedValueOnce({
        dates: ['2026-03-08'],
        moodSeries: [3],
        sleepHoursSeries: [7],
        sleepQualitySeries: [3],
        medAdherenceSeries: [1.0],
      });
      mockGetSymptomTypes.mockResolvedValueOnce([]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/time-series?userId=member1',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.medAdherenceSeries).toBeUndefined();
      expect(body.moodSeries).toEqual([3]);
    });

    it('includes medAdherenceSeries when caregiver has medications permission', async () => {
      mockRequireWellnessAccess.mockResolvedValueOnce(['wellness', 'medications']);
      mockExtractTimeSeries.mockResolvedValueOnce({
        dates: ['2026-03-08'],
        moodSeries: [3],
        sleepHoursSeries: [7],
        sleepQualitySeries: [3],
        medAdherenceSeries: [1.0],
      });
      mockGetSymptomTypes.mockResolvedValueOnce([]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/time-series?userId=member1',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.medAdherenceSeries).toEqual([1.0]);
    });

    it('includes all data for self-access', async () => {
      mockRequireWellnessAccess.mockResolvedValueOnce(['medications', 'reminders', 'schedule', 'wellness']);
      mockExtractTimeSeries.mockResolvedValueOnce({
        dates: ['2026-03-08'],
        moodSeries: [3],
        sleepHoursSeries: [7],
        sleepQualitySeries: [3],
        medAdherenceSeries: [1.0],
      });
      mockGetSymptomTypes.mockResolvedValueOnce([]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/time-series?userId=auth-user',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.medAdherenceSeries).toEqual([1.0]);
      expect(body.moodSeries).toEqual([3]);
    });
  });

  describe('GET /api/dashboard/graph', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph?userId=user1',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns 400 without userId', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph',
        headers: authHeaders,
      });
      expect(response.statusCode).toBe(400);
    });

    it('returns nodes and edges for given userId', async () => {
      mockGetFullGraph.mockResolvedValueOnce({
        nodes: [
          { id: 'day-2026-03-09', type: 'Day', label: 'Mar 9', data: { overallScore: 3.8 } },
          { id: 'sym-tremor-1', type: 'Symptom', label: 'tremor', data: { severity: 4 } },
        ],
        edges: [
          { source: 'sym-tremor-1', target: 'day-2026-03-09', type: 'ON_DAY', data: {} },
        ],
        causalExplanations: [
          { symptom: 'tremor', severity: 4, causes: ['missed levodopa'] },
        ],
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph?userId=user1&start=2026-03-01&end=2026-03-09',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.nodes).toHaveLength(2);
      expect(body.edges).toHaveLength(1);
      expect(mockGetFullGraph).toHaveBeenCalledWith('user1', '2026-03-01', '2026-03-09');
    });

    it('defaults date range to last 30 days', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph?userId=user1',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      expect(mockGetFullGraph).toHaveBeenCalledWith(
        'user1',
        expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
        expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/)
      );
    });

    it('returns 400 on invalid date format', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/graph?userId=user1&start=March-01',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(400);
    });
  });

  describe('GET /api/dashboard/time-series', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/time-series?userId=user1',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns time series with symptom breakdowns', async () => {
      mockExtractTimeSeries.mockResolvedValueOnce({
        dates: ['2026-03-08', '2026-03-09'],
        moodSeries: [3, 4],
        sleepHoursSeries: [7, 6.5],
        sleepQualitySeries: [3, 4],
        medAdherenceSeries: [1.0, 0.5],
      });
      mockGetSymptomTypes.mockResolvedValueOnce(['tremor', 'fatigue']);
      mockExtractSymptomSeries
        .mockResolvedValueOnce([3, 4])
        .mockResolvedValueOnce([2, null]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/time-series?userId=user1&start=2026-03-08&end=2026-03-09',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.dates).toEqual(['2026-03-08', '2026-03-09']);
      expect(body.moodSeries).toEqual([3, 4]);
      expect(body.symptomSeries.tremor).toEqual([3, 4]);
      expect(body.symptomSeries.fatigue).toEqual([2, null]);
      expect(mockExtractTimeSeries).toHaveBeenCalledWith('user1', '2026-03-08', '2026-03-09');
    });
  });

  describe('GET /api/dashboard/correlations', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/correlations?userId=user1',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns correlation edges', async () => {
      mockGetCorrelations.mockResolvedValueOnce([
        {
          sourceLabel: 'sleepHours',
          targetLabel: 'tremor',
          correlation: -0.65,
          lag: 1,
          pValue: 0.003,
          sampleSize: 25,
          method: 'pearson',
        },
      ]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/correlations?userId=user1',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body).toHaveLength(1);
      expect(body[0].correlation).toBe(-0.65);
      expect(mockGetCorrelations).toHaveBeenCalledWith('user1');
    });
  });

  describe('GET /api/dashboard/triggers', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/triggers?userId=user1',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns trigger frequency with avg severity', async () => {
      mockGetTriggerFrequency.mockResolvedValueOnce([
        { trigger: 'stress', count: 8, avgSeverity: 3.5 },
        { trigger: 'weather', count: 4, avgSeverity: 2.0 },
      ]);

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/triggers?userId=user1&start=2026-03-01&end=2026-03-09',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body).toHaveLength(2);
      expect(body[0].trigger).toBe('stress');
      expect(mockGetTriggerFrequency).toHaveBeenCalledWith('user1', '2026-03-01', '2026-03-09');
    });
  });

  describe('GET /api/dashboard/causal', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/causal?userId=user1',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns causal explanations', async () => {
      mockGetFullGraph.mockResolvedValueOnce({
        nodes: [],
        edges: [],
        causalExplanations: [
          { symptom: 'tremor', severity: 4, causes: ['missed levodopa', '3.5h sleep'] },
          { symptom: 'fatigue', severity: 3, causes: ['low mood'] },
        ],
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/dashboard/causal?userId=user1&start=2026-03-01&end=2026-03-09',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body).toHaveLength(2);
      expect(body[0].symptom).toBe('tremor');
    });
  });
});
