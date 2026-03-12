import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import crypto from 'node:crypto';
import { AlertService, type CheckInMetricsInput } from '../src/services/alert.service.js';

describe('AlertService', () => {
  let service: AlertService;
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      status: 202,
      json: () => Promise.resolve({ errors: [] }),
    });
    vi.stubGlobal('fetch', fetchSpy);

    service = new AlertService({
      apiKey: 'test-api-key',
      site: 'datadoghq.com',
      host: 'test-host',
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  const baseCheckIn: CheckInMetricsInput = {
    type: 'morning',
    completedAt: '2026-03-09T08:30:00Z',
    completionStatus: 'completed',
    durationSeconds: 180,
  };

  it('sends checkin.completed count on every check-in', async () => {
    await service.emitCheckInMetrics('user1', baseCheckIn);

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const completed = body.series.find((s: any) => s.metric === 'noongil.checkin.completed');
    expect(completed).toBeDefined();
    expect(completed.type).toBe(1); // count
    expect(completed.points[0].value).toBe(1);
    // Verify userId is hashed, not raw
    const expectedHash = crypto.createHash('sha256').update('user1').digest('hex').slice(0, 16);
    expect(completed.tags).toContain(`user:${expectedHash}`);
    expect(completed.tags).not.toContain('user:user1');
    expect(completed.tags).toContain('type:morning');
  });

  it('sends duration_seconds gauge when present', async () => {
    await service.emitCheckInMetrics('user1', baseCheckIn);

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const duration = body.series.find((s: any) => s.metric === 'noongil.checkin.duration_seconds');
    expect(duration).toBeDefined();
    expect(duration.type).toBe(3); // gauge
    expect(duration.points[0].value).toBe(180);
  });

  it('sends mood_score gauge when mood present', async () => {
    await service.emitCheckInMetrics('user1', {
      ...baseCheckIn,
      mood: { score: 4 },
    });

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const mood = body.series.find((s: any) => s.metric === 'noongil.checkin.mood_score');
    expect(mood).toBeDefined();
    expect(mood.type).toBe(3);
    expect(mood.points[0].value).toBe(4);
  });

  it('sends sleep_hours gauge when sleep present', async () => {
    await service.emitCheckInMetrics('user1', {
      ...baseCheckIn,
      sleep: { hours: 7.5 },
    });

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const sleep = body.series.find((s: any) => s.metric === 'noongil.checkin.sleep_hours');
    expect(sleep).toBeDefined();
    expect(sleep.points[0].value).toBe(7.5);
  });

  it('sends symptom_count and max_symptom_severity when symptoms present', async () => {
    await service.emitCheckInMetrics('user1', {
      ...baseCheckIn,
      symptoms: [
        { type: 'tremor', severity: 4 },
        { type: 'rigidity', severity: 2 },
      ],
    });

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const count = body.series.find((s: any) => s.metric === 'noongil.checkin.symptom_count');
    expect(count).toBeDefined();
    expect(count.points[0].value).toBe(2);

    const maxSev = body.series.find((s: any) => s.metric === 'noongil.checkin.max_symptom_severity');
    expect(maxSev).toBeDefined();
    expect(maxSev.points[0].value).toBe(4);
    expect(maxSev.tags).toContain('symptom_type:tremor');
  });

  it('sends med_adherence_ratio and meds_missed when medication present', async () => {
    await service.emitCheckInMetrics('user1', {
      ...baseCheckIn,
      medicationAdherence: [
        { medicationName: 'levodopa', status: 'taken' },
        { medicationName: 'amantadine', status: 'missed' },
        { medicationName: 'selegiline', status: 'taken' },
      ],
    });

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const ratio = body.series.find((s: any) => s.metric === 'noongil.checkin.med_adherence_ratio');
    expect(ratio).toBeDefined();
    expect(ratio.points[0].value).toBeCloseTo(2 / 3);

    const missed = body.series.find((s: any) => s.metric === 'noongil.checkin.meds_missed');
    expect(missed).toBeDefined();
    expect(missed.type).toBe(1); // count
    expect(missed.points[0].value).toBe(1);
  });

  it('skips metrics for missing fields', async () => {
    await service.emitCheckInMetrics('user1', baseCheckIn);

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const metricNames = body.series.map((s: any) => s.metric);
    expect(metricNames).not.toContain('noongil.checkin.mood_score');
    expect(metricNames).not.toContain('noongil.checkin.sleep_hours');
    expect(metricNames).not.toContain('noongil.checkin.symptom_count');
    expect(metricNames).not.toContain('noongil.checkin.med_adherence_ratio');
  });

  it('handles Datadog API errors gracefully', async () => {
    fetchSpy.mockResolvedValueOnce({
      ok: false,
      status: 403,
      json: () => Promise.resolve({ errors: ['Forbidden'] }),
    });

    // Should not throw
    await expect(
      service.emitCheckInMetrics('user1', baseCheckIn)
    ).resolves.not.toThrow();
  });

  it('handles fetch network errors gracefully', async () => {
    fetchSpy.mockRejectedValueOnce(new Error('Network error'));

    await expect(
      service.emitCheckInMetrics('user1', baseCheckIn)
    ).resolves.not.toThrow();
  });

  it('does not call fetch when apiKey is missing', async () => {
    const noKeyService = new AlertService({ apiKey: '', site: 'datadoghq.com', host: 'test' });
    await noKeyService.emitCheckInMetrics('user1', baseCheckIn);

    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('uses correct Datadog API URL and headers', async () => {
    await service.emitCheckInMetrics('user1', baseCheckIn);

    expect(fetchSpy).toHaveBeenCalledWith(
      'https://api.datadoghq.com/api/v2/series',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'DD-API-KEY': 'test-api-key',
          'Content-Type': 'application/json',
        }),
      })
    );
  });

  it('sets resources with host on each metric', async () => {
    await service.emitCheckInMetrics('user1', baseCheckIn);

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    for (const metric of body.series) {
      expect(metric.resources).toEqual([{ name: 'test-host', type: 'host' }]);
    }
  });
});
