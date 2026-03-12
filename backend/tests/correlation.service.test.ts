import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock graph service — use vi.hoisted to avoid reference-before-init
const { mockExtractTimeSeries, mockExtractSymptomSeries, mockGetGraphData, mockStoreCorrelation } =
  vi.hoisted(() => ({
    mockExtractTimeSeries: vi.fn(),
    mockExtractSymptomSeries: vi.fn(),
    mockGetGraphData: vi.fn(),
    mockStoreCorrelation: vi.fn().mockResolvedValue(undefined),
  }));

vi.mock('../src/services/graph.service.js', () => ({
  graphService: {
    extractTimeSeries: mockExtractTimeSeries,
    extractSymptomSeries: mockExtractSymptomSeries,
    getGraphData: mockGetGraphData,
    storeCorrelation: mockStoreCorrelation,
  },
}));

import { pearsonPValue, CorrelationService } from '../src/services/correlation.service.js';

describe('CorrelationService', () => {
  let service: InstanceType<typeof CorrelationService>;

  beforeEach(() => {
    service = new CorrelationService();
    vi.clearAllMocks();
  });

  // MARK: - pearsonPValue (pure math, no mocking needed)

  describe('pearsonPValue', () => {
    it('should return ~0.005 for r=0.5, n=30', () => {
      const p = pearsonPValue(0.5, 30);
      expect(p).toBeGreaterThan(0.003);
      expect(p).toBeLessThan(0.007);
    });

    it('should return ~0.107 for r=0.3, n=30', () => {
      const p = pearsonPValue(0.3, 30);
      expect(p).toBeGreaterThan(0.09);
      expect(p).toBeLessThan(0.12);
    });

    it('should return ~0.024 for r=0.7, n=10', () => {
      const p = pearsonPValue(0.7, 10);
      expect(p).toBeGreaterThan(0.02);
      expect(p).toBeLessThan(0.03);
    });

    it('should return 1 for n <= 2', () => {
      expect(pearsonPValue(0.9, 2)).toBe(1);
      expect(pearsonPValue(0.5, 1)).toBe(1);
    });

    it('should return 0 for |r| = 1', () => {
      expect(pearsonPValue(1.0, 30)).toBe(0);
      expect(pearsonPValue(-1.0, 30)).toBe(0);
    });

    it('should return ~1 for r=0', () => {
      const p = pearsonPValue(0, 30);
      expect(p).toBeGreaterThan(0.99);
    });

    it('should handle negative r same as positive', () => {
      const pPos = pearsonPValue(0.5, 20);
      const pNeg = pearsonPValue(-0.5, 20);
      expect(Math.abs(pPos - pNeg)).toBeLessThan(0.001);
    });
  });

  // MARK: - computeForUser

  describe('computeForUser', () => {
    it('should find strong mood-sleep correlation', async () => {
      // 30 days of data with clear positive mood-sleep correlation
      const dates = Array.from({ length: 30 }, (_, i) => `2026-02-${String(i + 1).padStart(2, '0')}`);
      const mood = dates.map((_, i) => 3 + Math.sin(i * 0.5));  // oscillating 2-4
      const sleep = dates.map((_, i) => 6 + Math.sin(i * 0.5)); // oscillating 5-7 (same phase = correlated)

      mockExtractTimeSeries.mockResolvedValueOnce({
        dates,
        moodSeries: mood,
        sleepHoursSeries: sleep,
        sleepQualitySeries: mood.map(v => v * 0.8), // correlated with mood
        medAdherenceSeries: dates.map(() => null),   // no med data
      });

      mockGetGraphData.mockResolvedValueOnce(
        dates.map(d => ({ date: d, symptoms: [] }))
      );

      const results = await service.computeForUser('user1');

      // Should find mood ↔ sleepHours correlation (they're in phase)
      const moodSleep = results.find(
        r => (r.nameA === 'mood' && r.nameB === 'sleepHours') ||
             (r.nameA === 'sleepHours' && r.nameB === 'mood')
      );
      expect(moodSleep).toBeDefined();
      expect(Math.abs(moodSleep!.correlation)).toBeGreaterThan(0.3);
      expect(moodSleep!.pValue).toBeLessThan(0.05);
    });

    it('should store significant results in graph', async () => {
      const dates = Array.from({ length: 30 }, (_, i) => `2026-02-${String(i + 1).padStart(2, '0')}`);
      // Perfect correlation
      const values = dates.map((_, i) => i);

      mockExtractTimeSeries.mockResolvedValueOnce({
        dates,
        moodSeries: values,
        sleepHoursSeries: values, // perfect correlation with mood
        sleepQualitySeries: values.map(() => null),
        medAdherenceSeries: values.map(() => null),
      });

      mockGetGraphData.mockResolvedValueOnce(
        dates.map(d => ({ date: d, symptoms: [] }))
      );

      await service.computeForUser('user1');

      // Should have called storeCorrelation at least once
      expect(mockStoreCorrelation).toHaveBeenCalled();
      const call = mockStoreCorrelation.mock.calls[0];
      expect(call[0]).toBe('user1'); // userId
      expect(call[1].method).toBe('pearson');
    });

    it('should not store weak correlations', async () => {
      const dates = Array.from({ length: 30 }, (_, i) => `2026-02-${String(i + 1).padStart(2, '0')}`);
      // Random-ish data with no correlation
      const mood = dates.map((_, i) => [3, 4, 2, 5, 3, 4, 2, 5, 3, 4, 2, 5, 3, 4, 2, 5, 3, 4, 2, 5, 3, 4, 2, 5, 3, 4, 2, 5, 3, 4][i]);
      const sleep = dates.map((_, i) => [7, 6, 8, 7, 6, 8, 7, 6, 8, 7, 5, 7, 8, 6, 7, 5, 8, 6, 7, 8, 5, 7, 6, 8, 7, 5, 6, 8, 7, 6][i]);

      mockExtractTimeSeries.mockResolvedValueOnce({
        dates,
        moodSeries: mood,
        sleepHoursSeries: sleep,
        sleepQualitySeries: dates.map(() => null),
        medAdherenceSeries: dates.map(() => null),
      });

      mockGetGraphData.mockResolvedValueOnce(
        dates.map(d => ({ date: d, symptoms: [] }))
      );

      const results = await service.computeForUser('user1');

      // All correlations should be filtered out (weak or not significant)
      for (const r of results) {
        expect(Math.abs(r.correlation)).toBeGreaterThan(0.3);
        expect(r.pValue).toBeLessThan(0.05);
      }
    });

    it('should include symptom correlations when symptoms exist', async () => {
      const dates = Array.from({ length: 30 }, (_, i) => `2026-02-${String(i + 1).padStart(2, '0')}`);
      const mood = dates.map((_, i) => i * 0.1 + 2); // steadily rising
      const tremor = dates.map((_, i) => 5 - i * 0.1); // inversely correlated with mood

      mockExtractTimeSeries.mockResolvedValueOnce({
        dates,
        moodSeries: mood,
        sleepHoursSeries: dates.map(() => 7), // constant = no correlation
        sleepQualitySeries: dates.map(() => null),
        medAdherenceSeries: dates.map(() => null),
      });

      mockGetGraphData.mockResolvedValueOnce(
        dates.map(d => ({ date: d, symptoms: [{ type: 'tremor', severity: 2 }] }))
      );

      mockExtractSymptomSeries.mockResolvedValueOnce(tremor);

      const results = await service.computeForUser('user1');

      const tremorMood = results.find(
        r => (r.nameA === 'tremor' || r.nameB === 'tremor') &&
             (r.nameA === 'mood' || r.nameB === 'mood')
      );
      expect(tremorMood).toBeDefined();
      expect(tremorMood!.correlation).toBeLessThan(-0.3); // negative correlation
    });

    it('should skip when insufficient data', async () => {
      // Only 3 days — below MIN_SAMPLES threshold
      mockExtractTimeSeries.mockResolvedValueOnce({
        dates: ['2026-02-01', '2026-02-02', '2026-02-03'],
        moodSeries: [3, 4, 5],
        sleepHoursSeries: [7, 8, 9],
        sleepQualitySeries: [null, null, null],
        medAdherenceSeries: [null, null, null],
      });

      mockGetGraphData.mockResolvedValueOnce([
        { date: '2026-02-01', symptoms: [] },
        { date: '2026-02-02', symptoms: [] },
        { date: '2026-02-03', symptoms: [] },
      ]);

      const results = await service.computeForUser('user1');
      expect(results).toEqual([]);
      expect(mockStoreCorrelation).not.toHaveBeenCalled();
    });
  });
});
