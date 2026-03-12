import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Mock neo4j-driver
const mockRun = vi.fn().mockResolvedValue({ records: [] });
const mockTx = { run: mockRun };
const mockSession = {
  executeWrite: vi.fn((fn: (tx: typeof mockTx) => Promise<unknown>) => fn(mockTx)),
  executeRead: vi.fn((fn: (tx: typeof mockTx) => Promise<unknown>) => fn(mockTx)),
  close: vi.fn().mockResolvedValue(undefined),
};
const mockDriver = {
  verifyConnectivity: vi.fn().mockResolvedValue(undefined),
  session: vi.fn(() => mockSession),
  close: vi.fn().mockResolvedValue(undefined),
};

vi.mock('neo4j-driver', () => ({
  default: {
    driver: vi.fn(() => mockDriver),
    auth: { basic: vi.fn((u: string, p: string) => ({ principal: u, credentials: p })) },
    int: vi.fn((v: number) => ({ low: v, high: 0, toNumber: () => v })),
  },
}));

import { CausalService } from '../src/services/causal.service.js';

describe('CausalService', () => {
  let service: CausalService;

  beforeEach(() => {
    service = new CausalService();
    vi.clearAllMocks();

    // Set required env vars
    process.env.NEO4J_URI = 'bolt://localhost:7687';
    process.env.NEO4J_USER = 'neo4j';
    process.env.NEO4J_PASSWORD = 'test';
  });

  afterEach(() => {
    delete process.env.NEO4J_URI;
    delete process.env.NEO4J_USER;
    delete process.env.NEO4J_PASSWORD;
  });

  // MARK: - buildCausalEdges

  describe('buildCausalEdges', () => {
    it('should return zero when no spikes exist', async () => {
      // Baselines query returns one symptom type
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                type: 'tremor',
                avgSeverity: 2.0,
                stdSeverity: 0.5,
                eventCount: 4,
              };
              return data[key];
            },
          },
        ],
      });

      // Sleep baseline query
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                avgHours: 7.5,
                stdHours: 1.0,
                avgQuality: 3.5,
                stdQuality: 0.8,
              };
              return data[key];
            },
          },
        ],
      });

      // Symptom spikes query — no spikes (all below threshold)
      mockRun.mockResolvedValueOnce({ records: [] });

      await service.connect();
      const result = await service.buildCausalEdges('user1');

      expect(result.created).toBe(0);
      expect(result.spikesFound).toBe(0);
    });

    it('should create LIKELY_CAUSED_BY edges for poor sleep', async () => {
      // Baselines query
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                type: 'tremor',
                avgSeverity: 2.0,
                stdSeverity: 0.5,
                eventCount: 4,
              };
              return data[key];
            },
          },
        ],
      });

      // Sleep baseline query
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                avgHours: 7.0,
                stdHours: 1.0,
                avgQuality: 3.5,
                stdQuality: 0.8,
              };
              return data[key];
            },
          },
        ],
      });

      // Symptom spikes query — one spike above threshold (severity 4 > avg 2.0 + std 0.5)
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                syId: 'sy-001',
                date: '2026-02-15',
                type: 'tremor',
                severity: 4,
              };
              return data[key];
            },
          },
        ],
      });

      // Cleanup causal edges (CLEANUP_CAUSAL_EDGES)
      mockRun.mockResolvedValueOnce({ records: [] });

      // Poor sleep query — returns one poor sleep record
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                slId: 'sl-001',
                date: '2026-02-14',
                hours: 4.5,
                quality: 2,
              };
              return data[key];
            },
          },
        ],
      });

      // CREATE_LIKELY_CAUSED_BY for poor sleep
      mockRun.mockResolvedValueOnce({ records: [] });

      // Missed meds query — none
      mockRun.mockResolvedValueOnce({ records: [] });

      // Triggers query — none
      mockRun.mockResolvedValueOnce({ records: [] });

      await service.connect();
      const result = await service.buildCausalEdges('user1');

      expect(result.spikesFound).toBe(1);
      expect(result.created).toBe(1);

      // Verify LIKELY_CAUSED_BY was created with poor_sleep reason
      const calls = mockRun.mock.calls;
      const causalCall = calls.find(
        (c) => c[0].includes('LIKELY_CAUSED_BY') && c[1]?.reason === 'poor_sleep'
      );
      expect(causalCall).toBeDefined();
      expect(causalCall![1].syId).toBe('sy-001');
      expect(causalCall![1].causeId).toBe('sl-001');
      expect(causalCall![1].confidence).toBe(0.75);
    });

    it('should create WORSENED_BY edges for triggers', async () => {
      // Baselines query
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                type: 'tremor',
                avgSeverity: 2.0,
                stdSeverity: 0.5,
                eventCount: 4,
              };
              return data[key];
            },
          },
        ],
      });

      // Sleep baseline query
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                avgHours: 7.0,
                stdHours: 1.0,
                avgQuality: 3.5,
                stdQuality: 0.8,
              };
              return data[key];
            },
          },
        ],
      });

      // Symptom spikes query — one spike
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                syId: 'sy-002',
                date: '2026-02-16',
                type: 'tremor',
                severity: 5,
              };
              return data[key];
            },
          },
        ],
      });

      // Cleanup causal edges
      mockRun.mockResolvedValueOnce({ records: [] });

      // Poor sleep query — none
      mockRun.mockResolvedValueOnce({ records: [] });

      // Missed meds query — none
      mockRun.mockResolvedValueOnce({ records: [] });

      // Triggers query — one trigger found
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                tId: 't-001',
                date: '2026-02-15',
                name: 'loud construction',
                type: 'environmental',
              };
              return data[key];
            },
          },
        ],
      });

      // CREATE_WORSENED_BY for trigger
      mockRun.mockResolvedValueOnce({ records: [] });

      await service.connect();
      const result = await service.buildCausalEdges('user1');

      expect(result.spikesFound).toBe(1);
      expect(result.created).toBe(1);

      // Verify WORSENED_BY was created with stress_trigger reason
      const calls = mockRun.mock.calls;
      const worsenedCall = calls.find(
        (c) => c[0].includes('WORSENED_BY') && c[1]?.reason === 'stress_trigger'
      );
      expect(worsenedCall).toBeDefined();
      expect(worsenedCall![1].syId).toBe('sy-002');
      expect(worsenedCall![1].causeId).toBe('t-001');
      expect(worsenedCall![1].confidence).toBe(0.5);
    });

    it('treats severity 4 symptoms as attention-worthy even when they only meet baseline threshold', async () => {
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                type: 'stiffness',
                avgSeverity: 3.0,
                stdSeverity: 1.0,
                eventCount: 3,
              };
              return data[key];
            },
          },
        ],
      });

      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                avgHours: 7.0,
                stdHours: 1.0,
                avgQuality: 3.0,
                stdQuality: 1.0,
              };
              return data[key];
            },
          },
        ],
      });

      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                syId: 'sy-stiff-001',
                date: '2026-03-06',
                type: 'stiffness',
                severity: 4,
              };
              return data[key];
            },
          },
        ],
      });

      mockRun.mockResolvedValueOnce({ records: [] });
      mockRun.mockResolvedValueOnce({ records: [] });

      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                mdId: 'md-001',
                date: '2026-03-06',
                name: 'Levodopa',
                status: 'missed',
                delay: 0,
              };
              return data[key];
            },
          },
        ],
      });

      mockRun.mockResolvedValueOnce({ records: [] });
      mockRun.mockResolvedValueOnce({ records: [] });

      await service.connect();
      const result = await service.buildCausalEdges('user1');

      expect(result.spikesFound).toBe(1);
      expect(result.created).toBe(1);

      const calls = mockRun.mock.calls;
      const causalCall = calls.find(
        (c) => c[0].includes('LIKELY_CAUSED_BY') && c[1]?.reason === 'missed_medication'
      );
      expect(causalCall).toBeDefined();
      expect(causalCall![1].syId).toBe('sy-stiff-001');
      expect(causalCall![1].causeId).toBe('md-001');
    });

    it('does not treat low-history moderate symptoms as spikes without severe intensity', async () => {
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                type: 'fatigue',
                avgSeverity: 3.0,
                stdSeverity: 0.0,
                eventCount: 1,
              };
              return data[key];
            },
          },
        ],
      });

      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: () => null,
          },
        ],
      });

      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                syId: 'sy-fatigue-001',
                date: '2026-03-06',
                type: 'fatigue',
                severity: 3,
              };
              return data[key];
            },
          },
        ],
      });

      await service.connect();
      const result = await service.buildCausalEdges('user1');

      expect(result.spikesFound).toBe(0);
      expect(result.created).toBe(0);
    });
  });
});
