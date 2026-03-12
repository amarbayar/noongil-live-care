import neo4j, { type Driver, type Session, type ManagedTransaction } from 'neo4j-driver';
import { toNumber } from '../lib/neo4j-serialize.js';

// MARK: - Cypher Queries

const QUERY_SYMPTOM_BASELINES = `
  MATCH (sy:Symptom)-[:ON_DAY]->(d:Day {userId: $userId})
  WITH sy.type AS type, avg(sy.severity) AS avgSeverity, stDev(sy.severity) AS stdSeverity, count(*) AS eventCount
  RETURN type, avgSeverity, stdSeverity, eventCount
`;

const QUERY_SLEEP_BASELINE = `
  MATCH (sl:SleepEntry)-[:ON_DAY]->(d:Day {userId: $userId})
  RETURN avg(sl.hours) AS avgHours, stDev(sl.hours) AS stdHours,
         avg(sl.quality) AS avgQuality, stDev(sl.quality) AS stdQuality
`;

const QUERY_SYMPTOM_SPIKES = `
  MATCH (sy:Symptom)-[:ON_DAY]->(d:Day {userId: $userId})
  RETURN elementId(sy) AS syId, d.date AS date, sy.type AS type, sy.severity AS severity
  ORDER BY d.date
`;

const QUERY_POOR_SLEEP = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date < date($spikeDate)
  MATCH (sl:SleepEntry)-[:ON_DAY]->(d)
  WHERE sl.hours < $sleepThreshold OR sl.quality < $qualityThreshold
  RETURN elementId(sl) AS slId, d.date AS date, sl.hours AS hours, sl.quality AS quality
`;

const QUERY_MISSED_MEDS = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($spikeDate)
  MATCH (md:MedicationDose)-[:ON_DAY]->(d)
  WHERE md.status = 'missed' OR md.delayMinutes > 30
  RETURN elementId(md) AS mdId, d.date AS date, md.medicationName AS name,
         md.status AS status, md.delayMinutes AS delay
`;

const QUERY_TRIGGERS = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($spikeDate)
  MATCH (t:Trigger)-[:TRIGGERED_ON]->(d)
  RETURN elementId(t) AS tId, d.date AS date, t.name AS name, t.type AS type
`;

const CREATE_LIKELY_CAUSED_BY = `
  MATCH (sy) WHERE elementId(sy) = $syId
  MATCH (cause) WHERE elementId(cause) = $causeId
  CREATE (sy)-[:LIKELY_CAUSED_BY {
    reason: $reason,
    confidence: $confidence,
    daysBefore: $daysBefore,
    detail: $detail
  }]->(cause)
`;

const CREATE_WORSENED_BY = `
  MATCH (sy) WHERE elementId(sy) = $syId
  MATCH (cause) WHERE elementId(cause) = $causeId
  CREATE (sy)-[:WORSENED_BY {
    reason: $reason,
    confidence: $confidence,
    daysBefore: $daysBefore,
    detail: $detail
  }]->(cause)
`;

const CLEANUP_CAUSAL_EDGES = `
  MATCH (m:Member {userId: $userId})-[:HAS_SYMPTOM]->(sy:Symptom)
  OPTIONAL MATCH (sy)-[r:LIKELY_CAUSED_BY|WORSENED_BY]->()
  DELETE r
`;

// MARK: - Types

interface Baseline {
  avg: number;
  std: number;
  count: number;
}

interface SpikeEvent {
  syId: string;
  date: string;
  type: string;
  severity: number;
}

export interface CausalBuildResult {
  created: number;
  spikesFound: number;
}

// MARK: - CausalService

export class CausalService {
  private driver: Driver | null = null;

  async connect(): Promise<void> {
    const uri = process.env.NEO4J_URI;
    const user = process.env.NEO4J_USER;
    const password = process.env.NEO4J_PASSWORD;

    if (!uri || !user || !password) {
      throw new Error('Missing NEO4J_URI, NEO4J_USER, or NEO4J_PASSWORD env vars');
    }

    this.driver = neo4j.driver(uri, neo4j.auth.basic(user, password));
    await this.driver.verifyConnectivity();
  }

  async disconnect(): Promise<void> {
    if (this.driver) {
      await this.driver.close();
      this.driver = null;
    }
  }

  private getSession(): Session {
    if (!this.driver) {
      throw new Error('Neo4j driver not connected. Call connect() first.');
    }
    return this.driver.session();
  }

  /**
   * Build causal edges for a user's symptom spikes.
   * Finds spikes (severity > baseline + 1 stdev), then looks back 1-2 days
   * for poor sleep, missed/late meds, and triggers.
   */
  async buildCausalEdges(userId: string): Promise<CausalBuildResult> {
    const session = this.getSession();
    let created = 0;

    try {
      // Step 1: Compute symptom baselines
      const baselines = await this.computeSymptomBaselines(session, userId);

      // Step 2: Compute sleep baseline
      const sleepBaseline = await this.computeSleepBaseline(session, userId);

      // Step 3: Find symptom spikes
      const spikes = await this.findSymptomSpikes(session, userId, baselines);

      if (spikes.length === 0) {
        return { created: 0, spikesFound: 0 };
      }

      // Step 4: Clean up previous causal edges for this user
      await session.executeWrite(async (tx: ManagedTransaction) => {
        await tx.run(CLEANUP_CAUSAL_EDGES, { userId });
      });

      // Step 5: For each spike, find candidate causes
      await session.executeWrite(async (tx: ManagedTransaction) => {
        for (const spike of spikes) {
          // a) Poor sleep in prior 1-2 days
          const poorSleep = await tx.run(QUERY_POOR_SLEEP, {
            userId,
            spikeDate: spike.date,
            startDate: subtractDays(spike.date, 2),
            sleepThreshold: sleepBaseline.hours.avg - sleepBaseline.hours.std,
            qualityThreshold: sleepBaseline.quality.avg - sleepBaseline.quality.std,
          });

          for (const rec of poorSleep.records) {
            const hours = toNumber(rec.get('hours')) ?? 0;
            const quality = toNumber(rec.get('quality')) ?? 0;
            const dateStr = formatNeoDate(rec.get('date'));

            await tx.run(CREATE_LIKELY_CAUSED_BY, {
              syId: spike.syId,
              causeId: rec.get('slId'),
              reason: 'poor_sleep',
              confidence: 0.75,
              daysBefore: neo4j.int(daysDiff(dateStr, spike.date)),
              detail: `Sleep ${hours}h (quality ${quality}) → ${spike.type} severity ${spike.severity}`,
            });
            created++;
          }

          // b) Missed or late medications in prior 1-2 days
          const missedMeds = await tx.run(QUERY_MISSED_MEDS, {
            userId,
            spikeDate: spike.date,
            startDate: subtractDays(spike.date, 2),
          });

          for (const rec of missedMeds.records) {
            const name = rec.get('name');
            const status = rec.get('status');
            const delay = toNumber(rec.get('delay')) ?? 0;
            const dateStr = formatNeoDate(rec.get('date'));
            const reason = status === 'missed' ? 'missed_medication' : 'late_medication';
            const detail = status === 'missed'
              ? `Missed ${name} on ${dateStr}`
              : `${name} ${delay}min late on ${dateStr}`;

            await tx.run(CREATE_LIKELY_CAUSED_BY, {
              syId: spike.syId,
              causeId: rec.get('mdId'),
              reason,
              confidence: status === 'missed' ? 0.85 : 0.6,
              daysBefore: neo4j.int(daysDiff(dateStr, spike.date)),
              detail: `${detail} → ${spike.type} severity ${spike.severity}`,
            });
            created++;
          }

          // c) Triggers in prior 1-2 days
          const triggers = await tx.run(QUERY_TRIGGERS, {
            userId,
            spikeDate: spike.date,
            startDate: subtractDays(spike.date, 2),
          });

          for (const rec of triggers.records) {
            const name = rec.get('name');
            const dateStr = formatNeoDate(rec.get('date'));

            await tx.run(CREATE_WORSENED_BY, {
              syId: spike.syId,
              causeId: rec.get('tId'),
              reason: 'stress_trigger',
              confidence: 0.5,
              daysBefore: neo4j.int(daysDiff(dateStr, spike.date)),
              detail: `Trigger "${name}" → ${spike.type} severity ${spike.severity}`,
            });
            created++;
          }
        }
      });

      return { created, spikesFound: spikes.length };
    } finally {
      await session.close();
    }
  }

  // MARK: - Private Helpers

  private async computeSymptomBaselines(
    session: Session,
    userId: string
  ): Promise<Record<string, Baseline>> {
    const result = await session.executeRead(async (tx: ManagedTransaction) => {
      return tx.run(QUERY_SYMPTOM_BASELINES, { userId });
    });

    const baselines: Record<string, Baseline> = {};
    for (const record of result.records) {
      baselines[record.get('type')] = {
        avg: toNumber(record.get('avgSeverity')) ?? 0,
        std: toNumber(record.get('stdSeverity')) ?? 0.5,
        count: toNumber(record.get('eventCount')) ?? 0,
      };
    }
    return baselines;
  }

  private async computeSleepBaseline(
    session: Session,
    userId: string
  ): Promise<{ hours: Baseline; quality: Baseline }> {
    const result = await session.executeRead(async (tx: ManagedTransaction) => {
      return tx.run(QUERY_SLEEP_BASELINE, { userId });
    });

    const rec = result.records[0];
    if (!rec) {
      return {
        hours: { avg: 7, std: 1, count: 0 },
        quality: { avg: 3, std: 1, count: 0 },
      };
    }

    return {
      hours: {
        avg: toNumber(rec.get('avgHours')) ?? 7,
        std: toNumber(rec.get('stdHours')) ?? 1,
        count: 0,
      },
      quality: {
        avg: toNumber(rec.get('avgQuality')) ?? 3,
        std: toNumber(rec.get('stdQuality')) ?? 1,
        count: 0,
      },
    };
  }

  private async findSymptomSpikes(
    session: Session,
    userId: string,
    baselines: Record<string, Baseline>
  ): Promise<SpikeEvent[]> {
    const result = await session.executeRead(async (tx: ManagedTransaction) => {
      return tx.run(QUERY_SYMPTOM_SPIKES, { userId });
    });

    const spikes: SpikeEvent[] = [];
    for (const record of result.records) {
      const type = record.get('type');
      const severity = toNumber(record.get('severity')) ?? 0;
      const baseline = baselines[type];

      if (baseline && isAttentionWorthySymptom(severity, baseline)) {
        spikes.push({
          syId: record.get('syId'),
          date: formatNeoDate(record.get('date')),
          type,
          severity,
        });
      }
    }
    return spikes;
  }
}

// MARK: - Helpers

function subtractDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().split('T')[0];
}

function formatNeoDate(dateObj: unknown): string {
  if (typeof dateObj === 'string') return dateObj;
  const obj = dateObj as Record<string, unknown>;
  const y = extractInt(obj.year);
  const m = String(extractInt(obj.month)).padStart(2, '0');
  const d = String(extractInt(obj.day)).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function extractInt(val: unknown): number {
  if (typeof val === 'number') return val;
  if (typeof val === 'object' && val !== null) {
    const o = val as Record<string, unknown>;
    if ('low' in o) return Number(o.low);
  }
  return 0;
}

function isAttentionWorthySymptom(severity: number, baseline: Baseline): boolean {
  if (severity >= 4) {
    return true;
  }

  if (baseline.count >= 3 && severity >= baseline.avg + baseline.std) {
    return true;
  }

  return false;
}

function daysDiff(dateA: string, dateB: string): number {
  const a = new Date(dateA + 'T00:00:00Z');
  const b = new Date(dateB + 'T00:00:00Z');
  return Math.round((b.getTime() - a.getTime()) / (86400 * 1000));
}

export const causalService = new CausalService();
