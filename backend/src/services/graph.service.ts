import neo4j, { type Driver, type Session, type ManagedTransaction } from 'neo4j-driver';
import { serializeValue, toNumber } from '../lib/neo4j-serialize.js';

// MARK: - Cypher Templates
//
// Graph model: Member → events (CheckIn, Symptom, MoodEntry, SleepEntry, MedicationDose)
// Temporal backbone: Day nodes linked by NEXT_DAY
// All events anchor to Day nodes via ON_DAY
// Entity nodes (MetricType) are MERGE targets for CORRELATES_WITH edges
// Event nodes are CREATE (unique per occurrence)

const MERGE_DAY = `
  MERGE (d:Day {date: date($date), userId: $userId})
  ON CREATE SET d.dayOfWeek = date($date).dayOfWeek
  RETURN d
`;

const MERGE_NEXT_DAY = `
  MATCH (yesterday:Day {date: date($yesterday), userId: $userId})
  MATCH (today:Day {date: date($today), userId: $userId})
  MERGE (yesterday)-[:NEXT_DAY]->(today)
`;

const MERGE_CHECKIN = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (c:CheckIn {
    id: $checkInId,
    type: $type,
    completedAt: datetime($completedAt),
    completionStatus: $completionStatus,
    duration: $duration
  })
  MERGE (m)-[:COMPLETED_CHECKIN]->(c)
  MERGE (c)-[:ON_DAY]->(d)
`;

const MERGE_SYMPTOM = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (s:Symptom {
    id: $symptomId,
    type: $type,
    severity: $severity,
    location: $location,
    duration: $duration,
    recordedAt: datetime($recordedAt),
    timeOfDay: $timeOfDay
  })
  MERGE (m)-[:HAS_SYMPTOM]->(s)
  MERGE (s)-[:ON_DAY]->(d)
`;

const MERGE_MOOD = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (me:MoodEntry {
    id: $moodId,
    score: $score,
    description: $description,
    recordedAt: datetime($recordedAt)
  })
  MERGE (m)-[:HAS_MOOD]->(me)
  MERGE (me)-[:ON_DAY]->(d)
`;

const MERGE_SLEEP = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (s:SleepEntry {
    id: $sleepId,
    hours: $hours,
    quality: $quality,
    interruptions: $interruptions,
    recordedAt: datetime($recordedAt)
  })
  MERGE (m)-[:HAS_SLEEP]->(s)
  MERGE (s)-[:ON_DAY]->(d)
`;

const MERGE_MED_DOSE = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (md:MedicationDose {
    id: $doseId,
    medicationName: $medicationName,
    status: $status,
    scheduledTime: $scheduledTime,
    takenAt: $takenAt,
    delayMinutes: $delayMinutes
  })
  MERGE (m)-[:TAKES_MEDICATION]->(md)
  MERGE (md)-[:ON_DAY]->(d)
`;

const MERGE_TRIGGER = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (t:Trigger {
    id: $triggerId,
    name: $name,
    type: $type,
    recordedAt: datetime($recordedAt)
  })
  MERGE (m)-[:HAS_TRIGGER]->(t)
  MERGE (t)-[:TRIGGERED_ON]->(d)
`;

const MERGE_ACTIVITY = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (a:Activity {
    id: $activityId,
    name: $name,
    duration: $duration,
    intensity: $intensity,
    recordedAt: datetime($recordedAt)
  })
  MERGE (m)-[:DID_ACTIVITY]->(a)
  MERGE (a)-[:ON_DAY]->(d)
`;

const MERGE_CONCERN = `
  MATCH (d:Day {date: date($date), userId: $userId})
  MERGE (m:Member {userId: $userId})
  CREATE (c:Concern {
    id: $concernId,
    text: $text,
    theme: $theme,
    urgency: $urgency,
    recordedAt: datetime($recordedAt)
  })
  MERGE (m)-[:HAS_CONCERN]->(c)
  MERGE (c)-[:ON_DAY]->(d)
`;

const MERGE_INGEST_RECEIPT = `
  MERGE (r:IngestReceipt {userId: $userId, eventId: $eventId})
  ON CREATE SET
    r.processCount = 1,
    r.firstProcessedAt = datetime(),
    r.lastProcessedAt = datetime()
  ON MATCH SET
    r.processCount = coalesce(r.processCount, 0) + 1,
    r.lastProcessedAt = datetime()
  RETURN r.processCount AS processCount
`;

const QUERY_DAY_AGGREGATES = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  OPTIONAL MATCH (me:MoodEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sl:SleepEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sy:Symptom)-[:ON_DAY]->(d)
  OPTIONAL MATCH (md:MedicationDose)-[:ON_DAY]->(d)
  WITH d,
    avg(me.score) AS avgMood,
    avg(sl.hours) AS avgSleep,
    avg(sl.quality) AS avgSleepQuality,
    collect(DISTINCT {type: sy.type, severity: sy.severity}) AS symptoms,
    count(DISTINCT CASE WHEN md.status = 'taken' THEN md END) AS medsTaken,
    count(DISTINCT md) AS medsTotal
  RETURN d.date AS date,
    d.overallScore AS overallScore,
    avgMood, avgSleep, avgSleepQuality,
    symptoms, medsTaken, medsTotal
  ORDER BY d.date
`;

// Extracts daily time series vectors for correlation computation.
// Returns one row with collected arrays — nulls included for days without data.
const EXTRACT_TIME_SERIES = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  OPTIONAL MATCH (me:MoodEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sl:SleepEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (md:MedicationDose)-[:ON_DAY]->(d)
  WITH d,
    avg(me.score) AS mood,
    avg(sl.hours) AS sleepHours,
    avg(sl.quality) AS sleepQuality,
    CASE WHEN count(md) > 0
      THEN toFloat(count(CASE WHEN md.status = 'taken' THEN 1 END)) / count(md)
      ELSE null END AS medAdherence
  ORDER BY d.date
  RETURN collect(toString(d.date)) AS dates,
    collect(mood) AS moodSeries,
    collect(sleepHours) AS sleepHoursSeries,
    collect(sleepQuality) AS sleepQualitySeries,
    collect(medAdherence) AS medAdherenceSeries
`;

// Per-symptom-type daily severity for correlation.
const EXTRACT_SYMPTOM_SERIES = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  OPTIONAL MATCH (sy:Symptom {type: $symptomType})-[:ON_DAY]->(d)
  WITH d, avg(sy.severity) AS severity
  ORDER BY d.date
  RETURN collect(severity) AS series
`;

// Distinct symptom types in a date range.
const QUERY_SYMPTOM_TYPES = `
  MATCH (sy:Symptom)-[:ON_DAY]->(d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  RETURN DISTINCT sy.type AS type
  ORDER BY type
`;

// Trigger frequency with avg symptom severity on trigger days.
const QUERY_TRIGGER_FREQUENCY = `
  MATCH (t:Trigger)-[:TRIGGERED_ON]->(d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  OPTIONAL MATCH (sy:Symptom)-[:ON_DAY]->(d)
  WITH t.name AS triggerName, count(DISTINCT d) AS dayCount, avg(sy.severity) AS avgSeverity
  RETURN triggerName, dayCount, avgSeverity
  ORDER BY dayCount DESC
  LIMIT 10
`;

// Reads correlation edges stored on MetricType entity nodes.
const QUERY_CORRELATIONS = `
  MATCH (a:MetricType {userId: $userId})-[r:CORRELATES_WITH]->(b:MetricType {userId: $userId})
  RETURN a.name AS sourceLabel,
    b.name AS targetLabel,
    r.correlation AS correlation,
    r.lag AS lag,
    r.pValue AS pValue,
    r.sampleSize AS sampleSize,
    r.method AS method
  ORDER BY abs(r.correlation) DESC
  LIMIT 20
`;

// Writes a correlation result between two MetricType entity nodes.
const STORE_CORRELATION = `
  MERGE (a:MetricType {name: $nameA, userId: $userId})
  MERGE (b:MetricType {name: $nameB, userId: $userId})
  MERGE (a)-[r:CORRELATES_WITH]->(b)
  SET r.correlation = $correlation,
      r.pValue = $pValue,
      r.sampleSize = $sampleSize,
      r.lag = $lag,
      r.method = $method,
      r.computedAt = datetime(),
      r.windowStart = date($windowStart),
      r.windowEnd = date($windowEnd)
`;

// Full graph for dashboard: Day nodes + connected events + causal/correlation edges.
const QUERY_FULL_GRAPH = `
  MATCH (d:Day {userId: $userId})
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  OPTIONAL MATCH (me:MoodEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sl:SleepEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sy:Symptom)-[:ON_DAY]->(d)
  OPTIONAL MATCH (md:MedicationDose)-[:ON_DAY]->(d)
  OPTIONAL MATCH (t:Trigger)-[:TRIGGERED_ON]->(d)
  OPTIONAL MATCH (a:Activity)-[:ON_DAY]->(d)
  RETURN d, collect(DISTINCT me) AS moods, collect(DISTINCT sl) AS sleeps,
    collect(DISTINCT sy) AS symptoms, collect(DISTINCT md) AS meds,
    collect(DISTINCT t) AS triggers, collect(DISTINCT a) AS activities
  ORDER BY d.date
`;

const QUERY_CAUSAL_EDGES = `
  MATCH (m:Member {userId: $userId})-[:HAS_SYMPTOM]->(sy:Symptom)-[r:LIKELY_CAUSED_BY|WORSENED_BY]->(cause)
  MATCH (sy)-[:ON_DAY]->(d:Day)
  WHERE d.date >= date($startDate) AND d.date <= date($endDate)
  RETURN elementId(sy) AS sourceId, labels(sy)[0] AS sourceType, sy.type AS sourceLabel, sy.severity AS sourceSeverity,
    elementId(cause) AS targetId, labels(cause)[0] AS targetType,
    CASE WHEN cause:SleepEntry THEN 'Sleep ' + cause.hours + 'h'
         WHEN cause:MedicationDose THEN cause.medicationName + ' (' + cause.status + ')'
         WHEN cause:Trigger THEN cause.name
         ELSE '' END AS targetLabel,
    type(r) AS edgeType, r.confidence AS confidence, r.reason AS reason, r.detail AS detail
`;

const UPDATE_DAY_COMPOSITE = `
  MATCH (d:Day {date: date($date), userId: $userId})
  OPTIONAL MATCH (me:MoodEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sl:SleepEntry)-[:ON_DAY]->(d)
  OPTIONAL MATCH (sy:Symptom)-[:ON_DAY]->(d)
  WITH d,
    avg(me.score) AS moodAvg,
    avg(sl.quality) AS sleepQualityAvg,
    avg(sy.severity) AS symptomAvg
  SET d.overallScore = CASE
    WHEN moodAvg IS NOT NULL AND sleepQualityAvg IS NOT NULL AND symptomAvg IS NOT NULL
    THEN 0.3 * moodAvg + 0.3 * sleepQualityAvg + 0.4 * (5 - symptomAvg)
    WHEN moodAvg IS NOT NULL AND sleepQualityAvg IS NOT NULL
    THEN 0.5 * moodAvg + 0.5 * sleepQualityAvg
    WHEN moodAvg IS NOT NULL
    THEN moodAvg
    ELSE null
  END
  RETURN d.overallScore AS overallScore
`;

// MARK: - Types

export interface CheckInInput {
  id: string;
  userId: string;
  type: string;
  completedAt: string;  // ISO datetime
  localDate?: string;   // YYYY-MM-DD in user's local timezone
  completionStatus: string;
  durationSeconds?: number;
  mood?: { score: number; description?: string };
  sleep?: { hours: number; quality?: number; interruptions?: number };
  symptoms?: Array<{
    type: string;
    severity?: number;
    location?: string;
    duration?: string;
  }>;
  medicationAdherence?: Array<{
    medicationName: string;
    status: string;
    scheduledTime?: string;
    takenAt?: string;
    delayMinutes?: number;
  }>;
  triggers?: Array<{
    name: string;
    type?: string;
  }>;
  activities?: Array<{
    name: string;
    duration?: string;
    intensity?: string;
  }>;
  concerns?: Array<{
    text: string;
    theme?: string;
    urgency?: string;
  }>;
}

export interface DayAggregate {
  date: string;
  overallScore: number | null;
  avgMood: number | null;
  avgSleep: number | null;
  avgSleepQuality: number | null;
  symptoms: Array<{ type: string; severity: number | null }>;
  medsTaken: number;
  medsTotal: number;
}

export interface CorrelationEdge {
  sourceLabel: string;
  targetLabel: string;
  correlation: number;
  lag: number;
  pValue: number;
  sampleSize: number;
  method: string;
}

export interface TimeSeriesData {
  dates: string[];
  moodSeries: (number | null)[];
  sleepHoursSeries: (number | null)[];
  sleepQualitySeries: (number | null)[];
  medAdherenceSeries: (number | null)[];
}

export interface CorrelationResult {
  nameA: string;
  nameB: string;
  correlation: number;
  pValue: number;
  sampleSize: number;
  lag: number;
  method: string;
}

export interface DashboardNode {
  id: string;
  type: string;
  label: string;
  data: Record<string, unknown>;
}

export interface DashboardEdge {
  source: string;
  target: string;
  type: string;
  data: Record<string, unknown>;
}

export interface DashboardGraph {
  nodes: DashboardNode[];
  edges: DashboardEdge[];
  causalExplanations: Array<{
    symptom: string;
    severity: number;
    causes: string[];
  }>;
}

export interface TriggerFrequency {
  trigger: string;
  count: number;
  avgSeverity: number | null;
}

export interface IngestCheckInResult {
  duplicate: boolean;
}

// MARK: - GraphService

export class GraphService {
  private driver: Driver | null = null;

  async connect(): Promise<void> {
    const uri = process.env.NEO4J_URI;
    const user = process.env.NEO4J_USER;
    const password = process.env.NEO4J_PASSWORD;

    if (!uri || !user || !password) {
      throw new Error('Missing NEO4J_URI, NEO4J_USER, or NEO4J_PASSWORD env vars');
    }

    this.driver = neo4j.driver(uri, neo4j.auth.basic(user, password), {
      maxConnectionLifetime: 3 * 60 * 60 * 1000,  // 3 hours
      maxConnectionPoolSize: 50,
      connectionAcquisitionTimeout: 10 * 1000,     // 10s timeout
    });
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

  // MARK: - Day Node Management

  async ensureDayNode(userId: string, date: string): Promise<void> {
    const session = this.getSession();
    try {
      await session.executeWrite(async (tx: ManagedTransaction) => {
        await tx.run(MERGE_DAY, { date, userId });
        const yesterday = subtractDay(date);
        await tx.run(MERGE_NEXT_DAY, { yesterday, today: date, userId });
      });
    } finally {
      await session.close();
    }
  }

  // MARK: - Check-in Ingestion

  async ingestCheckIn(userId: string, checkIn: CheckInInput): Promise<IngestCheckInResult>;
  async ingestCheckIn(userId: string, eventId: string, checkIn: CheckInInput): Promise<IngestCheckInResult>;
  async ingestCheckIn(
    userId: string,
    eventIdOrCheckIn: string | CheckInInput,
    maybeCheckIn?: CheckInInput
  ): Promise<IngestCheckInResult> {
    const checkIn = typeof eventIdOrCheckIn === 'string' ? maybeCheckIn : eventIdOrCheckIn;
    const eventId = typeof eventIdOrCheckIn === 'string'
      ? eventIdOrCheckIn
      : `${eventIdOrCheckIn.id}_graph_sync`;

    if (!checkIn) {
      throw new Error('Missing check-in payload for graph ingestion');
    }

    const date = checkIn.localDate ?? checkIn.completedAt.split('T')[0];
    const session = this.getSession();

    try {
      return await session.executeWrite(async (tx: ManagedTransaction) => {
        const receiptResult = await tx.run(MERGE_INGEST_RECEIPT, { userId, eventId });
        const processCount = toNumber(receiptResult.records[0]?.get('processCount')) ?? 0;
        if (processCount > 1) {
          return { duplicate: true };
        }

        // 1. Day node + NEXT_DAY link
        await tx.run(MERGE_DAY, { date, userId });
        const yesterday = subtractDay(date);
        await tx.run(MERGE_NEXT_DAY, { yesterday, today: date, userId });

        // 2. CheckIn event node
        await tx.run(MERGE_CHECKIN, {
          date, userId,
          checkInId: checkIn.id,
          type: checkIn.type,
          completedAt: checkIn.completedAt,
          completionStatus: checkIn.completionStatus,
          duration: neo4j.int(checkIn.durationSeconds ?? 0),
        });

        // 3. Symptom event nodes
        if (checkIn.symptoms) {
          for (const symptom of checkIn.symptoms) {
            await tx.run(MERGE_SYMPTOM, {
              date, userId,
              symptomId: `${checkIn.id}-sym-${symptom.type}`,
              type: symptom.type,
              severity: neo4j.int(symptom.severity ?? 0),
              location: symptom.location ?? '',
              duration: symptom.duration ?? '',
              recordedAt: checkIn.completedAt,
              timeOfDay: getTimeOfDay(checkIn.completedAt),
            });
          }
        }

        // 4. Mood event node
        if (checkIn.mood) {
          await tx.run(MERGE_MOOD, {
            date, userId,
            moodId: `${checkIn.id}-mood`,
            score: neo4j.int(checkIn.mood.score),
            description: checkIn.mood.description ?? '',
            recordedAt: checkIn.completedAt,
          });
        }

        // 5. Sleep event node
        if (checkIn.sleep) {
          await tx.run(MERGE_SLEEP, {
            date, userId,
            sleepId: `${checkIn.id}-sleep`,
            hours: checkIn.sleep.hours,
            quality: neo4j.int(checkIn.sleep.quality ?? 0),
            interruptions: neo4j.int(checkIn.sleep.interruptions ?? 0),
            recordedAt: checkIn.completedAt,
          });
        }

        // 6. Medication dose event nodes
        if (checkIn.medicationAdherence) {
          for (const med of checkIn.medicationAdherence) {
            await tx.run(MERGE_MED_DOSE, {
              date, userId,
              doseId: `${checkIn.id}-med-${med.medicationName}`,
              medicationName: med.medicationName,
              status: med.status,
              scheduledTime: med.scheduledTime ?? '',
              takenAt: med.takenAt ?? '',
              delayMinutes: neo4j.int(med.delayMinutes ?? 0),
            });
          }
        }

        // 7. Trigger event nodes
        if (checkIn.triggers) {
          for (let i = 0; i < checkIn.triggers.length; i++) {
            const trigger = checkIn.triggers[i];
            await tx.run(MERGE_TRIGGER, {
              date, userId,
              triggerId: `${checkIn.id}-trigger-${i}`,
              name: trigger.name,
              type: trigger.type ?? '',
              recordedAt: checkIn.completedAt,
            });
          }
        }

        // 8. Activity event nodes
        if (checkIn.activities) {
          for (let i = 0; i < checkIn.activities.length; i++) {
            const activity = checkIn.activities[i];
            await tx.run(MERGE_ACTIVITY, {
              date, userId,
              activityId: `${checkIn.id}-activity-${i}`,
              name: activity.name,
              duration: activity.duration ?? '',
              intensity: activity.intensity ?? '',
              recordedAt: checkIn.completedAt,
            });
          }
        }

        // 9. Concern event nodes
        if (checkIn.concerns) {
          for (let i = 0; i < checkIn.concerns.length; i++) {
            const concern = checkIn.concerns[i];
            await tx.run(MERGE_CONCERN, {
              date, userId,
              concernId: `${checkIn.id}-concern-${i}`,
              text: concern.text,
              theme: concern.theme ?? '',
              urgency: concern.urgency ?? '',
              recordedAt: checkIn.completedAt,
            });
          }
        }

        return { duplicate: false };
      });
    } finally {
      await session.close();
    }
  }

  // MARK: - Composite Score

  async updateDayComposite(userId: string, date: string): Promise<number | null> {
    const session = this.getSession();
    try {
      const result = await session.executeWrite(async (tx: ManagedTransaction) => {
        return tx.run(UPDATE_DAY_COMPOSITE, { date, userId });
      });
      const record = result.records[0];
      return record ? toNumber(record.get('overallScore')) : null;
    } finally {
      await session.close();
    }
  }

  // MARK: - Time Series Extraction (for correlation engine)

  async extractTimeSeries(
    userId: string,
    startDate: string,
    endDate: string
  ): Promise<TimeSeriesData> {
    const session = this.getSession();
    try {
      const result = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(EXTRACT_TIME_SERIES, { userId, startDate, endDate });
      });

      const record = result.records[0];
      if (!record) {
        return { dates: [], moodSeries: [], sleepHoursSeries: [], sleepQualitySeries: [], medAdherenceSeries: [] };
      }

      return {
        dates: record.get('dates') as string[],
        moodSeries: (record.get('moodSeries') as unknown[]).map(toNumber),
        sleepHoursSeries: (record.get('sleepHoursSeries') as unknown[]).map(toNumber),
        sleepQualitySeries: (record.get('sleepQualitySeries') as unknown[]).map(toNumber),
        medAdherenceSeries: (record.get('medAdherenceSeries') as unknown[]).map(toNumber),
      };
    } finally {
      await session.close();
    }
  }

  async extractSymptomSeries(
    userId: string,
    symptomType: string,
    startDate: string,
    endDate: string
  ): Promise<(number | null)[]> {
    const session = this.getSession();
    try {
      const result = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(EXTRACT_SYMPTOM_SERIES, { userId, symptomType, startDate, endDate });
      });
      const record = result.records[0];
      if (!record) return [];
      return (record.get('series') as unknown[]).map(toNumber);
    } finally {
      await session.close();
    }
  }

  // MARK: - Correlation Storage

  async storeCorrelation(
    userId: string,
    result: CorrelationResult,
    windowStart: string,
    windowEnd: string
  ): Promise<void> {
    const session = this.getSession();
    try {
      await session.executeWrite(async (tx: ManagedTransaction) => {
        await tx.run(STORE_CORRELATION, {
          userId,
          nameA: result.nameA,
          nameB: result.nameB,
          correlation: result.correlation,
          pValue: result.pValue,
          sampleSize: neo4j.int(result.sampleSize),
          lag: neo4j.int(result.lag),
          method: result.method,
          windowStart,
          windowEnd,
        });
      });
    } finally {
      await session.close();
    }
  }

  // MARK: - Query Methods

  async getGraphData(userId: string, startDate: string, endDate: string): Promise<DayAggregate[]> {
    const session = this.getSession();
    try {
      const result = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(QUERY_DAY_AGGREGATES, { userId, startDate, endDate });
      });

      return result.records.map((record) => ({
        date: serializeValue(record.get('date')) as string,
        overallScore: toNumber(record.get('overallScore')),
        avgMood: toNumber(record.get('avgMood')),
        avgSleep: toNumber(record.get('avgSleep')),
        avgSleepQuality: toNumber(record.get('avgSleepQuality')),
        symptoms: (serializeValue(record.get('symptoms')) as Array<{ type: string; severity: unknown }>)
          .filter((s) => s.type != null)
          .map((s) => ({ type: s.type, severity: toNumber(s.severity) })),
        medsTaken: toNumber(record.get('medsTaken')) ?? 0,
        medsTotal: toNumber(record.get('medsTotal')) ?? 0,
      }));
    } finally {
      await session.close();
    }
  }

  // MARK: - Dashboard Graph

  async getFullGraph(userId: string, startDate: string, endDate: string): Promise<DashboardGraph> {
    const session = this.getSession();
    try {
      const nodes: DashboardNode[] = [];
      const edges: DashboardEdge[] = [];
      const nodeIds = new Set<string>();
      const elementIdToNodeId = new Map<string, string>();
      const dayOrder: Array<{ id: string; date: string }> = [];

      const addNode = (id: string, type: string, label: string, data: Record<string, unknown>) => {
        if (nodeIds.has(id)) return;
        nodeIds.add(id);
        nodes.push({ id, type, label, data });
      };

      const registerNode = (
        prefix: string,
        entity: { elementId?: string; properties?: Record<string, unknown> } | null | undefined,
        fallbackId: string,
        type: string,
        label: string,
        data: Record<string, unknown>
      ) => {
        if (!entity?.properties) return null;
        const rawElementId = typeof entity.elementId === 'string' ? entity.elementId : null;
        const id = rawElementId ? `${prefix}-${sanitizeGraphId(rawElementId)}` : `${prefix}-${fallbackId}`;
        if (rawElementId) {
          elementIdToNodeId.set(rawElementId, id);
        }
        addNode(id, type, label, data);
        return id;
      };

      // 1. Day nodes + connected events
      const graphResult = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(QUERY_FULL_GRAPH, { userId, startDate, endDate });
      });

      for (const record of graphResult.records) {
        const day = record.get('d');
        const dayDate = serializeValue(day.properties.date) as string;
        const dayId = `day-${dayDate}`;
        const dayLabel = formatCalendarDate(dayDate);
        addNode(dayId, 'Day', dayLabel, {
          date: dayDate,
          overallScore: toNumber(day.properties.overallScore),
        });
        dayOrder.push({ id: dayId, date: dayDate });

        const moods = record.get('moods') as any[];
        for (const m of moods) {
          const id = registerNode('mood', m, String(m?.properties?.id ?? dayDate), 'MoodEntry', `Mood ${toNumber(m?.properties?.score)}/5`, {
            score: toNumber(m.properties.score),
            description: m.properties.description ?? '',
          });
          if (!id) continue;
          edges.push({ source: id, target: dayId, type: 'ON_DAY', data: {} });
        }

        const sleeps = record.get('sleeps') as any[];
        for (const s of sleeps) {
          const id = registerNode('sleep', s, String(s?.properties?.id ?? dayDate), 'SleepEntry', `Sleep ${toNumber(s?.properties?.hours)}h`, {
            hours: toNumber(s.properties.hours),
            quality: toNumber(s.properties.quality),
          });
          if (!id) continue;
          edges.push({ source: id, target: dayId, type: 'ON_DAY', data: {} });
        }

        const symptoms = record.get('symptoms') as any[];
        for (const sy of symptoms) {
          const id = registerNode('symptom', sy, String(sy?.properties?.id ?? dayDate), 'Symptom', sy?.properties?.type ?? 'Symptom', {
            severity: toNumber(sy.properties.severity),
            type: sy.properties.type,
          });
          if (!id) continue;
          edges.push({ source: id, target: dayId, type: 'ON_DAY', data: {} });
        }

        const meds = record.get('meds') as any[];
        for (const md of meds) {
          const id = registerNode('medication', md, String(md?.properties?.id ?? dayDate), 'MedicationDose', String(md?.properties?.medicationName ?? 'Medication'), {
            status: md.properties.status,
            medicationName: md.properties.medicationName,
          });
          if (!id) continue;
          edges.push({ source: id, target: dayId, type: 'ON_DAY', data: {} });
        }

        const triggers = record.get('triggers') as any[];
        for (const t of triggers) {
          const id = registerNode('trigger', t, String(t?.properties?.id ?? dayDate), 'Trigger', String(t?.properties?.name ?? 'Trigger'), {
            name: t.properties.name,
            type: t.properties.type ?? '',
          });
          if (!id) continue;
          edges.push({ source: id, target: dayId, type: 'TRIGGERED_ON', data: {} });
        }

        const activities = record.get('activities') as any[];
        for (const a of activities) {
          const id = registerNode('activity', a, String(a?.properties?.id ?? dayDate), 'Activity', String(a?.properties?.name ?? 'Activity'), {
            name: a.properties.name,
            duration: a.properties.duration ?? '',
            intensity: a.properties.intensity ?? '',
          });
          if (!id) continue;
          edges.push({ source: id, target: dayId, type: 'ON_DAY', data: {} });
        }
      }

      const orderedDays = dayOrder.sort((a, b) => a.date.localeCompare(b.date));
      for (let i = 0; i < orderedDays.length - 1; i++) {
        edges.push({
          source: orderedDays[i].id,
          target: orderedDays[i + 1].id,
          type: 'NEXT_DAY',
          data: {},
        });
      }

      // 2. Causal edges
      const causalResult = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(QUERY_CAUSAL_EDGES, { userId, startDate, endDate });
      });

      const causalMap = new Map<string, { symptom: string; severity: number; causes: string[] }>();

      for (const record of causalResult.records) {
        const sourceId = record.get('sourceId') as string;
        const targetId = record.get('targetId') as string;
        const edgeType = record.get('edgeType') as string;
        const confidence = toNumber(record.get('confidence')) ?? 0;
        const reason = record.get('reason') as string ?? '';
        const detail = record.get('detail') as string ?? '';
        const sourceLabel = record.get('sourceLabel') as string ?? '';
        const sourceSeverity = toNumber(record.get('sourceSeverity')) ?? 0;
        const targetLabel = record.get('targetLabel') as string ?? '';
        const mappedSourceId = elementIdToNodeId.get(sourceId);
        const mappedTargetId = elementIdToNodeId.get(targetId);

        if (!mappedSourceId || !mappedTargetId) {
          continue;
        }

        edges.push({
          source: mappedSourceId,
          target: mappedTargetId,
          type: edgeType,
          data: { confidence, reason, detail },
        });

        if (!causalMap.has(mappedSourceId)) {
          causalMap.set(mappedSourceId, { symptom: sourceLabel, severity: sourceSeverity, causes: [] });
        }
        causalMap.get(mappedSourceId)!.causes.push(
          detail || `${targetLabel} (${reason})`
        );
      }

      // 3. Correlation edges
      const correlations = await this.getCorrelations(userId);
      for (const c of correlations) {
        const sourceMetricId = `metric-${sanitizeGraphId(c.sourceLabel)}`;
        const targetMetricId = `metric-${sanitizeGraphId(c.targetLabel)}`;
        addNode(sourceMetricId, 'PatternMetric', c.sourceLabel, {
          metricName: c.sourceLabel,
        });
        addNode(targetMetricId, 'PatternMetric', c.targetLabel, {
          metricName: c.targetLabel,
        });
        edges.push({
          source: sourceMetricId,
          target: targetMetricId,
          type: 'CORRELATES_WITH',
          data: { correlation: c.correlation, lag: c.lag, pValue: c.pValue, sampleSize: c.sampleSize },
        });
      }

      return {
        nodes,
        edges,
        causalExplanations: Array.from(causalMap.values()),
      };
    } finally {
      await session.close();
    }
  }

  async deleteOldGraphData(cutoffDate: string): Promise<number> {
    const session = this.getSession();
    try {
      const result = await session.executeWrite(async (tx: ManagedTransaction) => {
        return tx.run(
          `MATCH (d:Day) WHERE d.date < date($cutoffDate)
           OPTIONAL MATCH (d)<-[:ON_DAY|TRIGGERED_ON]-(e)
           DETACH DELETE e, d
           RETURN count(d) AS deletedDays`,
          { cutoffDate }
        );
      });
      const record = result.records[0];
      return record ? (record.get('deletedDays') as number) : 0;
    } finally {
      await session.close();
    }
  }

  async deleteUserData(userId: string): Promise<void> {
    const session = this.getSession();
    try {
      await session.executeWrite(async (tx: ManagedTransaction) => {
        await tx.run('MATCH (n {userId: $userId}) DETACH DELETE n', { userId });
      });
    } finally {
      await session.close();
    }
  }

  async getSymptomTypes(userId: string, startDate: string, endDate: string): Promise<string[]> {
    const session = this.getSession();
    try {
      const result = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(QUERY_SYMPTOM_TYPES, { userId, startDate, endDate });
      });
      return result.records.map((record) => record.get('type') as string);
    } finally {
      await session.close();
    }
  }

  async getTriggerFrequency(
    userId: string,
    startDate: string,
    endDate: string
  ): Promise<TriggerFrequency[]> {
    const session = this.getSession();
    try {
      const result = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(QUERY_TRIGGER_FREQUENCY, { userId, startDate, endDate });
      });
      return result.records.map((record) => ({
        trigger: record.get('triggerName') as string,
        count: toNumber(record.get('dayCount')) ?? 0,
        avgSeverity: toNumber(record.get('avgSeverity')),
      }));
    } finally {
      await session.close();
    }
  }

  async getCorrelations(userId: string): Promise<CorrelationEdge[]> {
    const session = this.getSession();
    try {
      const result = await session.executeRead(async (tx: ManagedTransaction) => {
        return tx.run(QUERY_CORRELATIONS, { userId });
      });

      return result.records.map((record) => ({
        sourceLabel: record.get('sourceLabel'),
        targetLabel: record.get('targetLabel'),
        correlation: toNumber(record.get('correlation')) ?? 0,
        lag: toNumber(record.get('lag')) ?? 0,
        pValue: toNumber(record.get('pValue')) ?? 1,
        sampleSize: toNumber(record.get('sampleSize')) ?? 0,
        method: record.get('method') ?? '',
      }));
    } finally {
      await session.close();
    }
  }
}

// MARK: - Helpers

function subtractDay(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().split('T')[0];
}

function getTimeOfDay(isoDatetime: string): string {
  const hour = new Date(isoDatetime).getUTCHours();
  if (hour < 12) return 'morning';
  if (hour < 17) return 'afternoon';
  return 'evening';
}

function sanitizeGraphId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function formatCalendarDate(dateStr: string): string {
  const [year, month, day] = dateStr.split('-').map(Number);
  if (!year || !month || !day) return dateStr;
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(year, month - 1, day, 12, 0, 0)));
}

// toNumber is imported from ../lib/neo4j-serialize.js

export const graphService = new GraphService();
