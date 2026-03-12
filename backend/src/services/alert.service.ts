/**
 * Alert service — emits health metrics to Datadog via HTTP API (v2/series).
 * No agent/sidecar required (raw fetch, not DogStatsD).
 * Monitors configured in Datadog trigger PagerDuty → FCM push.
 */

import crypto from 'node:crypto';

// Datadog V2 metric types
const GAUGE = 3 as const;
const COUNT = 1 as const;

export interface CheckInMetricsInput {
  type: string;
  completedAt: string;
  completionStatus: string;
  durationSeconds?: number;
  mood?: { score: number; description?: string };
  sleep?: { hours: number; quality?: number; interruptions?: number };
  symptoms?: Array<{ type: string; severity?: number }>;
  medicationAdherence?: Array<{ medicationName: string; status: string }>;
}

interface MetricEntry {
  metric: string;
  type: typeof GAUGE | typeof COUNT;
  points: Array<{ timestamp: number; value: number }>;
  tags: string[];
  resources: Array<{ name: string; type: string }>;
  interval?: number;
}

interface AlertServiceConfig {
  apiKey: string;
  site: string;
  host: string;
}

export class AlertService {
  private readonly apiKey: string;
  private readonly site: string;
  private readonly host: string;

  constructor(config?: AlertServiceConfig) {
    this.apiKey = config?.apiKey ?? process.env.DD_API_KEY ?? '';
    this.site = config?.site ?? process.env.DD_SITE ?? 'datadoghq.com';
    this.host = config?.host ?? process.env.DD_HOST ?? 'noongil-backend';
  }

  async emitCheckInMetrics(userId: string, checkIn: CheckInMetricsInput): Promise<void> {
    if (!this.apiKey) return;

    const ts = Math.floor(new Date(checkIn.completedAt).getTime() / 1000);
    const hashedId = hashUserId(userId);
    const baseTags = [`user:${hashedId}`, `type:${checkIn.type}`];
    const series: MetricEntry[] = [];

    const addGauge = (metric: string, value: number, extraTags: string[] = []) => {
      series.push({
        metric,
        type: GAUGE,
        points: [{ timestamp: ts, value }],
        tags: [...baseTags, ...extraTags],
        resources: [{ name: this.host, type: 'host' }],
      });
    };

    const addCount = (metric: string, value: number, extraTags: string[] = []) => {
      series.push({
        metric,
        type: COUNT,
        points: [{ timestamp: ts, value }],
        tags: [...baseTags, ...extraTags],
        resources: [{ name: this.host, type: 'host' }],
        interval: 60,
      });
    };

    // Always emit completed count
    addCount('noongil.checkin.completed', 1);

    // Duration
    if (checkIn.durationSeconds != null) {
      addGauge('noongil.checkin.duration_seconds', checkIn.durationSeconds);
    }

    // Mood
    if (checkIn.mood) {
      addGauge('noongil.checkin.mood_score', checkIn.mood.score);
    }

    // Sleep
    if (checkIn.sleep) {
      addGauge('noongil.checkin.sleep_hours', checkIn.sleep.hours);
    }

    // Symptoms
    if (checkIn.symptoms && checkIn.symptoms.length > 0) {
      addGauge('noongil.checkin.symptom_count', checkIn.symptoms.length);

      let maxSeverity = 0;
      let maxType = '';
      for (const s of checkIn.symptoms) {
        const sev = s.severity ?? 0;
        if (sev > maxSeverity) {
          maxSeverity = sev;
          maxType = s.type;
        }
      }
      if (maxSeverity > 0) {
        addGauge('noongil.checkin.max_symptom_severity', maxSeverity, [`symptom_type:${maxType}`]);
      }
    }

    // Medication adherence
    if (checkIn.medicationAdherence && checkIn.medicationAdherence.length > 0) {
      const total = checkIn.medicationAdherence.length;
      const taken = checkIn.medicationAdherence.filter((m) => m.status === 'taken').length;
      const missed = total - taken;

      addGauge('noongil.checkin.med_adherence_ratio', taken / total);
      if (missed > 0) {
        addCount('noongil.checkin.meds_missed', missed);
      }
    }

    await this.flush(series);
  }

  private async flush(series: MetricEntry[]): Promise<void> {
    if (series.length === 0) return;

    try {
      const response = await fetch(`https://api.${this.site}/api/v2/series`, {
        method: 'POST',
        headers: {
          'DD-API-KEY': this.apiKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ series }),
      });

      if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        console.error('[AlertService] Datadog API error:', response.status, err);
      }
    } catch (err) {
      console.error('[AlertService] Failed to send metrics:', err);
    }
  }
}

function hashUserId(userId: string): string {
  return crypto.createHash('sha256').update(userId).digest('hex').slice(0, 16);
}

export const alertService = new AlertService();
