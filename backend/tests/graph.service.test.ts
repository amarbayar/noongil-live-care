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

import { GraphService, type CheckInInput } from '../src/services/graph.service.js';

describe('GraphService', () => {
  let service: GraphService;

  beforeEach(() => {
    service = new GraphService();
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

  // MARK: - Connect

  describe('connect', () => {
    it('should call driver.verifyConnectivity', async () => {
      await service.connect();
      expect(mockDriver.verifyConnectivity).toHaveBeenCalledOnce();
    });

    it('should throw when env vars are missing', async () => {
      delete process.env.NEO4J_URI;
      await expect(service.connect()).rejects.toThrow('Missing NEO4J_URI');
    });
  });

  // MARK: - ensureDayNode

  describe('ensureDayNode', () => {
    it('should run MERGE query for day node', async () => {
      await service.connect();
      await service.ensureDayNode('user1', '2026-02-15');

      // Should have called run with MERGE Day query
      const calls = mockRun.mock.calls;
      const dayMergeCall = calls.find(
        (c) => c[0].includes('MERGE') && c[0].includes('Day') && c[1]?.date === '2026-02-15'
      );
      expect(dayMergeCall).toBeDefined();
    });

    it('should link to yesterday with NEXT_DAY edge', async () => {
      await service.connect();
      await service.ensureDayNode('user1', '2026-02-15');

      const calls = mockRun.mock.calls;
      const nextDayCall = calls.find(
        (c) => c[0].includes('NEXT_DAY') && c[1]?.yesterday === '2026-02-14'
      );
      expect(nextDayCall).toBeDefined();
    });
  });

  // MARK: - ingestCheckIn

  describe('ingestCheckIn', () => {
    const fullCheckIn: CheckInInput = {
      id: 'ci-001',
      userId: 'user1',
      type: 'morning',
      completedAt: '2026-02-15T08:30:00Z',
      completionStatus: 'completed',
      durationSeconds: 120,
      mood: { score: 4, description: 'feeling good' },
      sleep: { hours: 7.5, quality: 4, interruptions: 1 },
      symptoms: [
        { type: 'tremor', severity: 2, location: 'left hand', duration: '30 min' },
        { type: 'fatigue', severity: 3 },
      ],
      medicationAdherence: [
        { medicationName: 'Levodopa', status: 'taken', scheduledTime: '08:00', takenAt: '2026-02-15T08:10:00Z' },
      ],
    };

    it('should create all nodes for a full check-in', async () => {
      await service.connect();
      await service.ingestCheckIn('user1', fullCheckIn);

      const queries = mockRun.mock.calls.map((c) => c[0]);

      // Day node
      expect(queries.some((q: string) => q.includes('MERGE') && q.includes(':Day'))).toBe(true);
      // CheckIn node
      expect(queries.some((q: string) => q.includes(':CheckIn'))).toBe(true);
      // Symptom nodes (2)
      const symptomQueries = queries.filter((q: string) => q.includes(':Symptom'));
      expect(symptomQueries.length).toBe(2);
      // Mood node
      expect(queries.some((q: string) => q.includes(':MoodEntry'))).toBe(true);
      // Sleep node
      expect(queries.some((q: string) => q.includes(':SleepEntry'))).toBe(true);
      // Medication dose
      expect(queries.some((q: string) => q.includes(':MedicationDose'))).toBe(true);
    });

    it('should create trigger, activity, and concern nodes', async () => {
      const extendedCheckIn: CheckInInput = {
        ...fullCheckIn,
        triggers: [{ name: 'plumber noise', type: 'environmental' }],
        activities: [{ name: 'walking', duration: '30 minutes', intensity: 'moderate' }],
        concerns: [{ text: 'worried about falling', theme: 'mobility', urgency: 'medium' }],
      };

      await service.connect();
      await service.ingestCheckIn('user1', extendedCheckIn);

      const queries = mockRun.mock.calls.map((c) => c[0]);

      // Trigger node
      expect(queries.some((q: string) => q.includes(':Trigger'))).toBe(true);
      // Activity node
      expect(queries.some((q: string) => q.includes(':Activity'))).toBe(true);
      // Concern node
      expect(queries.some((q: string) => q.includes(':Concern'))).toBe(true);
    });

    it('should handle partial data (mood only, no symptoms)', async () => {
      const partialCheckIn: CheckInInput = {
        id: 'ci-002',
        userId: 'user1',
        type: 'morning',
        completedAt: '2026-02-15T08:30:00Z',
        completionStatus: 'completed',
        mood: { score: 3 },
      };

      await service.connect();
      await service.ingestCheckIn('user1', partialCheckIn);

      const queries = mockRun.mock.calls.map((c) => c[0]);

      expect(queries.some((q: string) => q.includes(':MoodEntry'))).toBe(true);
      // No symptom, sleep, or med queries
      expect(queries.some((q: string) => q.includes(':Symptom'))).toBe(false);
      expect(queries.some((q: string) => q.includes(':SleepEntry'))).toBe(false);
      expect(queries.some((q: string) => q.includes(':MedicationDose'))).toBe(false);
    });

    it('should return duplicate on repeated eventId and skip second graph mutation', async () => {
      let receiptProcessCount = 0;
      mockRun.mockImplementation((query: string) => {
        if (query.includes('IngestReceipt')) {
          receiptProcessCount += 1;
          return Promise.resolve({
            records: [{
              get: (key: string) => key === 'processCount'
                ? { low: receiptProcessCount, high: 0, toNumber: () => receiptProcessCount }
                : null,
            }],
          });
        }
        return Promise.resolve({ records: [] });
      });

      await service.connect();
      const first = await service.ingestCheckIn('user1', 'ci-001_graph_sync', fullCheckIn);
      const firstMutationCount = mockRun.mock.calls.filter((c) => !c[0].includes('IngestReceipt')).length;

      const second = await service.ingestCheckIn('user1', 'ci-001_graph_sync', fullCheckIn);
      const secondMutationCount = mockRun.mock.calls.filter((c) => !c[0].includes('IngestReceipt')).length;

      expect(first.duplicate).toBe(false);
      expect(second.duplicate).toBe(true);
      expect(secondMutationCount).toBe(firstMutationCount);
    });
  });

  // MARK: - updateDayComposite

  describe('updateDayComposite', () => {
    it('should compute and return overall score', async () => {
      mockRun.mockResolvedValueOnce({
        records: [{ get: (key: string) => (key === 'overallScore' ? 3.5 : null) }],
      });

      await service.connect();
      const score = await service.updateDayComposite('user1', '2026-02-15');

      expect(score).toBe(3.5);
      const calls = mockRun.mock.calls;
      expect(calls.some((c) => c[0].includes('overallScore'))).toBe(true);
    });
  });

  // MARK: - getGraphData

  describe('getGraphData', () => {
    it('should return day aggregates', async () => {
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                // Simulate real Neo4j Date object with Integer-wrapped components
                date: { year: { low: 2026, high: 0 }, month: { low: 2, high: 0 }, day: { low: 15, high: 0 } },
                overallScore: 3.5,
                avgMood: 4.0,
                avgSleep: 7.5,
                avgSleepQuality: 4,
                symptoms: [{ type: 'tremor', severity: 2 }],
                medsTaken: 2,
                medsTotal: 3,
              };
              return data[key];
            },
          },
        ],
      });

      await service.connect();
      const data = await service.getGraphData('user1', '2026-02-01', '2026-02-28');

      expect(data).toHaveLength(1);
      expect(data[0].date).toBe('2026-02-15');
      expect(data[0].avgMood).toBe(4.0);
      expect(data[0].avgSleep).toBe(7.5);
    });
  });

  describe('getFullGraph', () => {
    it('builds connected trace nodes, causal edges, and metric nodes with coherent IDs', async () => {
      mockRun
        .mockResolvedValueOnce({
          records: [
            {
              get: (key: string) => {
                const values: Record<string, unknown> = {
                  d: {
                    properties: {
                      date: { year: { low: 2026, high: 0 }, month: { low: 3, high: 0 }, day: { low: 10, high: 0 } },
                      overallScore: 3.9,
                    },
                    elementId: 'day:10',
                  },
                  moods: [],
                  sleeps: [
                    {
                      elementId: 'sleep:1',
                      properties: { id: 'sleep-1', hours: 5.5, quality: 2 },
                    },
                  ],
                  symptoms: [
                    {
                      elementId: 'sym:1',
                      properties: { id: 'sym-1', type: 'tremor', severity: 4 },
                    },
                  ],
                  meds: [
                    {
                      elementId: 'med:1',
                      properties: { id: 'med-1', medicationName: 'Levodopa', status: 'missed' },
                    },
                  ],
                  triggers: [],
                  activities: [],
                };
                return values[key];
              },
            },
            {
              get: (key: string) => {
                const values: Record<string, unknown> = {
                  d: {
                    properties: {
                      date: { year: { low: 2026, high: 0 }, month: { low: 3, high: 0 }, day: { low: 11, high: 0 } },
                      overallScore: 4.2,
                    },
                    elementId: 'day:11',
                  },
                  moods: [],
                  sleeps: [],
                  symptoms: [],
                  meds: [],
                  triggers: [],
                  activities: [],
                };
                return values[key];
              },
            },
          ],
        })
        .mockResolvedValueOnce({
          records: [
            {
              get: (key: string) => {
                const values: Record<string, unknown> = {
                  sourceId: 'sym:1',
                  targetId: 'sleep:1',
                  edgeType: 'LIKELY_CAUSED_BY',
                  confidence: 0.8,
                  reason: 'poor_sleep',
                  detail: 'Sleep 5.5h before tremor spike',
                  sourceLabel: 'tremor',
                  sourceSeverity: 4,
                  targetLabel: 'Sleep 5.5h',
                };
                return values[key];
              },
            },
          ],
        })
        .mockResolvedValueOnce({
          records: [
            {
              get: (key: string) => {
                const values: Record<string, unknown> = {
                  sourceLabel: 'sleepHours',
                  targetLabel: 'tremor',
                  correlation: -0.72,
                  lag: 1,
                  pValue: 0.01,
                  sampleSize: 12,
                  method: 'pearson',
                };
                return values[key];
              },
            },
          ],
        });

      await service.connect();
      const graph = await service.getFullGraph('user1', '2026-03-10', '2026-03-11');

      expect(graph.nodes.some((node) => node.id === 'symptom-sym_1')).toBe(true);
      expect(graph.nodes.some((node) => node.id === 'sleep-sleep_1')).toBe(true);
      expect(graph.nodes.some((node) => node.id === 'metric-sleepHours')).toBe(true);
      expect(graph.nodes.some((node) => node.id === 'metric-tremor')).toBe(true);

      expect(graph.edges).toContainEqual(expect.objectContaining({
        source: 'symptom-sym_1',
        target: 'sleep-sleep_1',
        type: 'LIKELY_CAUSED_BY',
      }));
      expect(graph.edges).toContainEqual(expect.objectContaining({
        source: 'day-2026-03-10',
        target: 'day-2026-03-11',
        type: 'NEXT_DAY',
      }));
      expect(graph.edges).toContainEqual(expect.objectContaining({
        source: 'metric-sleepHours',
        target: 'metric-tremor',
        type: 'CORRELATES_WITH',
      }));
      expect(graph.causalExplanations).toEqual([
        {
          symptom: 'tremor',
          severity: 4,
          causes: ['Sleep 5.5h before tremor spike'],
        },
      ]);
    });
  });

  // MARK: - getCorrelations

  describe('getCorrelations', () => {
    it('should return correlation edges from MetricType nodes', async () => {
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                sourceLabel: 'sleepHours',
                targetLabel: 'tremor',
                correlation: -0.67,
                lag: 0,
                pValue: 0.02,
                sampleSize: 30,
                method: 'pearson',
              };
              return data[key];
            },
          },
        ],
      });

      await service.connect();
      const correlations = await service.getCorrelations('user1');

      expect(correlations).toHaveLength(1);
      expect(correlations[0].sourceLabel).toBe('sleepHours');
      expect(correlations[0].targetLabel).toBe('tremor');
      expect(correlations[0].correlation).toBe(-0.67);
      expect(correlations[0].lag).toBe(0);
      expect(correlations[0].pValue).toBe(0.02);
      expect(correlations[0].sampleSize).toBe(30);
      expect(correlations[0].method).toBe('pearson');
    });
  });

  // MARK: - extractTimeSeries

  describe('extractTimeSeries', () => {
    it('should return time series vectors for correlation', async () => {
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              const data: Record<string, unknown> = {
                dates: ['2026-02-13', '2026-02-14', '2026-02-15'],
                moodSeries: [3, 4, 5],
                sleepHoursSeries: [7, 8, 6.5],
                sleepQualitySeries: [3, 4, 3],
                medAdherenceSeries: [1.0, 0.5, null],
              };
              return data[key];
            },
          },
        ],
      });

      await service.connect();
      const ts = await service.extractTimeSeries('user1', '2026-02-13', '2026-02-15');

      expect(ts.dates).toEqual(['2026-02-13', '2026-02-14', '2026-02-15']);
      expect(ts.moodSeries).toEqual([3, 4, 5]);
      expect(ts.sleepHoursSeries).toEqual([7, 8, 6.5]);
      expect(ts.medAdherenceSeries).toEqual([1.0, 0.5, null]);
    });

    it('should return empty arrays when no data', async () => {
      mockRun.mockResolvedValueOnce({ records: [] });

      await service.connect();
      const ts = await service.extractTimeSeries('user1', '2026-02-13', '2026-02-15');

      expect(ts.dates).toEqual([]);
      expect(ts.moodSeries).toEqual([]);
    });
  });

  // MARK: - extractSymptomSeries

  describe('extractSymptomSeries', () => {
    it('should return severity series for a symptom type', async () => {
      mockRun.mockResolvedValueOnce({
        records: [
          {
            get: (key: string) => {
              if (key === 'series') return [2, 3, null, 1];
              return null;
            },
          },
        ],
      });

      await service.connect();
      const series = await service.extractSymptomSeries('user1', 'tremor', '2026-02-12', '2026-02-15');

      expect(series).toEqual([2, 3, null, 1]);
    });

    it('should return empty array when no data', async () => {
      mockRun.mockResolvedValueOnce({ records: [] });

      await service.connect();
      const series = await service.extractSymptomSeries('user1', 'tremor', '2026-02-12', '2026-02-15');

      expect(series).toEqual([]);
    });
  });

  // MARK: - storeCorrelation

  describe('storeCorrelation', () => {
    it('should write correlation to MetricType nodes', async () => {
      await service.connect();
      await service.storeCorrelation(
        'user1',
        {
          nameA: 'sleepHours',
          nameB: 'tremor',
          correlation: -0.67,
          pValue: 0.02,
          sampleSize: 30,
          lag: 0,
          method: 'pearson',
        },
        '2026-01-15',
        '2026-02-15'
      );

      const calls = mockRun.mock.calls;
      const storeCall = calls.find(
        (c) => c[0].includes('CORRELATES_WITH') && c[0].includes('MetricType')
      );
      expect(storeCall).toBeDefined();
      expect(storeCall![1].nameA).toBe('sleepHours');
      expect(storeCall![1].nameB).toBe('tremor');
      expect(storeCall![1].correlation).toBe(-0.67);
      expect(storeCall![1].windowStart).toBe('2026-01-15');
      expect(storeCall![1].windowEnd).toBe('2026-02-15');
    });
  });
});
