/**
 * END-TO-END SPIKE: Real Neo4j Aura instance.
 *
 * Tests the full pipeline:
 *   1. Connect to Neo4j Aura
 *   2. Clean up any prior spike data
 *   3. Ingest 14 days of check-ins via GraphService
 *   4. Query day aggregates back and inspect raw response shapes
 *   5. Query correlations
 *   6. Run CorrelationService.computeForUser end-to-end
 *   7. Read back stored CORRELATES_WITH edges
 *   8. Print everything for manual inspection
 *   9. Clean up spike data
 *
 * Run: npx tsx tests/spike-neo4j-e2e.ts
 */

import neo4j from 'neo4j-driver';
import { GraphService, type CheckInInput } from '../src/services/graph.service.js';
import { CorrelationService } from '../src/services/correlation.service.js';

const NEO4J_URI = process.env.NEO4J_URI;
const NEO4J_USER = process.env.NEO4J_USER;
const NEO4J_PASSWORD = process.env.NEO4J_PASSWORD;

const SPIKE_USER_ID = 'spike-test-user-001';

// ─── Helpers ──────────────────────────────────────────────────

function log(section: string, data: unknown) {
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`  ${section}`);
  console.log('═'.repeat(60));
  console.log(JSON.stringify(data, null, 2));
}

function generateCheckIns(days: number): CheckInInput[] {
  const checkIns: CheckInInput[] = [];
  const baseDate = new Date('2026-02-01T00:00:00Z');

  for (let i = 0; i < days; i++) {
    const date = new Date(baseDate);
    date.setUTCDate(date.getUTCDate() + i);
    const dateStr = date.toISOString().split('T')[0];

    // Simulate realistic patterns:
    // - Mood improves with better sleep (correlated)
    // - Tremor worsens with poor sleep (inverse correlation)
    // - Medication adherence is mostly consistent
    const sleepHours = 5.5 + Math.sin(i * 0.4) * 2; // oscillates 3.5 - 7.5
    const sleepQuality = Math.round(Math.min(5, Math.max(1, sleepHours - 2)));
    const moodScore = Math.round(Math.min(5, Math.max(1, sleepHours * 0.5 + Math.random() * 0.5)));
    const tremorSeverity = Math.round(Math.min(5, Math.max(1, 7 - sleepHours + Math.random())));
    const tookMeds = Math.random() > 0.15; // 85% adherence

    checkIns.push({
      id: `spike-ci-${dateStr}`,
      userId: SPIKE_USER_ID,
      type: i % 2 === 0 ? 'morning' : 'evening',
      completedAt: `${dateStr}T${i % 2 === 0 ? '08' : '20'}:30:00Z`,
      completionStatus: 'completed',
      durationSeconds: 90 + Math.floor(Math.random() * 60),
      mood: { score: moodScore, description: moodScore >= 4 ? 'good day' : 'struggling' },
      sleep: {
        hours: Math.round(sleepHours * 10) / 10,
        quality: sleepQuality,
        interruptions: sleepQuality <= 2 ? 3 : sleepQuality <= 3 ? 1 : 0,
      },
      symptoms: [
        { type: 'tremor', severity: tremorSeverity, location: 'left hand', duration: '30 min' },
        ...(i % 3 === 0 ? [{ type: 'fatigue', severity: Math.min(5, tremorSeverity + 1) }] : []),
      ],
      medicationAdherence: [
        {
          medicationName: 'Levodopa',
          status: tookMeds ? 'taken' : 'missed',
          scheduledTime: '08:00',
          ...(tookMeds ? { takenAt: `${dateStr}T08:${10 + Math.floor(Math.random() * 20)}:00Z` } : {}),
          delayMinutes: tookMeds ? Math.floor(Math.random() * 30) : 0,
        },
        {
          medicationName: 'Pramipexole',
          status: Math.random() > 0.1 ? 'taken' : 'missed',
          scheduledTime: '20:00',
        },
      ],
    });
  }

  return checkIns;
}

// ─── Step 1: Raw driver test ─────────────────────────────────

async function step1_rawDriverTest() {
  console.log('\n🔌 Step 1: Raw driver connection test...');

  if (!NEO4J_URI || !NEO4J_USER || !NEO4J_PASSWORD) {
    throw new Error('Set NEO4J_URI, NEO4J_USER, and NEO4J_PASSWORD before running this spike script.');
  }

  const driver = neo4j.driver(NEO4J_URI, neo4j.auth.basic(NEO4J_USER, NEO4J_PASSWORD));

  try {
    await driver.verifyConnectivity();
    console.log('  ✅ Connected to Neo4j Aura');

    const session = driver.session();
    try {
      // Simple query to see what we get back
      const result = await session.run(
        'RETURN date("2026-02-15") AS d, datetime("2026-02-15T08:30:00Z") AS dt, 42 AS num'
      );
      const record = result.records[0];

      log('RAW Neo4j response types', {
        dateValue: record.get('d'),
        dateType: typeof record.get('d'),
        dateConstructor: record.get('d')?.constructor?.name,
        dateKeys: record.get('d') ? Object.keys(record.get('d')) : 'null',
        dateYear: record.get('d')?.year,
        dateYearType: typeof record.get('d')?.year,
        dateYearKeys: record.get('d')?.year ? Object.keys(record.get('d')?.year) : 'null',

        datetimeValue: record.get('dt'),
        datetimeKeys: record.get('dt') ? Object.keys(record.get('dt')) : 'null',

        numValue: record.get('num'),
        numType: typeof record.get('num'),
        numKeys: typeof record.get('num') === 'object' ? Object.keys(record.get('num')) : 'primitive',
      });

      // Test MERGE + date() function — does our Cypher syntax work?
      console.log('\n  Testing MERGE Day syntax...');
      const mergeResult = await session.executeWrite(async (tx) => {
        return tx.run(
          `MERGE (d:Day {date: date($date), userId: $userId})
           ON CREATE SET d.dayOfWeek = date($date).dayOfWeek
           RETURN d`,
          { date: '2026-02-15', userId: SPIKE_USER_ID }
        );
      });

      const dayNode = mergeResult.records[0]?.get('d');
      log('MERGE Day node result', {
        rawNode: dayNode,
        nodeKeys: dayNode ? Object.keys(dayNode) : 'null',
        properties: dayNode?.properties,
        labels: dayNode?.labels,
      });
    } finally {
      await session.close();
    }
  } finally {
    await driver.close();
  }
}

// ─── Step 2: GraphService ingest ─────────────────────────────

async function step2_ingest() {
  console.log('\n📥 Step 2: Ingesting 14 days of check-ins via GraphService...');

  // Set env vars for GraphService
  process.env.NEO4J_URI = NEO4J_URI;
  process.env.NEO4J_USER = NEO4J_USER;
  process.env.NEO4J_PASSWORD = NEO4J_PASSWORD;

  const graphService = new GraphService();
  await graphService.connect();

  const checkIns = generateCheckIns(14);
  console.log(`  Generated ${checkIns.length} check-ins`);

  for (const checkIn of checkIns) {
    const date = checkIn.completedAt.split('T')[0];
    try {
      await graphService.ingestCheckIn(SPIKE_USER_ID, checkIn);
      await graphService.updateDayComposite(SPIKE_USER_ID, date);
      process.stdout.write('  .');
    } catch (err) {
      console.error(`\n  ❌ Failed on ${date}:`, err);
      throw err;
    }
  }
  console.log('\n  ✅ All check-ins ingested');

  await graphService.disconnect();
}

// ─── Step 3: Query back and inspect ──────────────────────────

async function step3_queryAndInspect() {
  console.log('\n🔍 Step 3: Querying graph data back...');

  process.env.NEO4J_URI = NEO4J_URI;
  process.env.NEO4J_USER = NEO4J_USER;
  process.env.NEO4J_PASSWORD = NEO4J_PASSWORD;

  const graphService = new GraphService();
  await graphService.connect();

  try {
    // Day aggregates
    const graphData = await graphService.getGraphData(SPIKE_USER_ID, '2026-02-01', '2026-02-14');
    log('Day Aggregates (getGraphData)', {
      count: graphData.length,
      first: graphData[0],
      last: graphData[graphData.length - 1],
      sample: graphData.slice(0, 3),
    });

    // Time series
    const timeSeries = await graphService.extractTimeSeries(SPIKE_USER_ID, '2026-02-01', '2026-02-14');
    log('Time Series (extractTimeSeries)', {
      dateCount: timeSeries.dates.length,
      dates: timeSeries.dates,
      moodSeries: timeSeries.moodSeries,
      sleepHoursSeries: timeSeries.sleepHoursSeries,
      medAdherenceSeries: timeSeries.medAdherenceSeries,
    });

    // Symptom series
    const tremorSeries = await graphService.extractSymptomSeries(
      SPIKE_USER_ID, 'tremor', '2026-02-01', '2026-02-14'
    );
    log('Tremor Series (extractSymptomSeries)', tremorSeries);

    // Correlations (should be empty before computation)
    const correlationsBefore = await graphService.getCorrelations(SPIKE_USER_ID);
    log('Correlations BEFORE computation', correlationsBefore);
  } finally {
    await graphService.disconnect();
  }
}

// ─── Step 4: Correlation engine end-to-end ───────────────────

async function step4_correlationEngine() {
  console.log('\n📊 Step 4: Running correlation engine...');

  process.env.NEO4J_URI = NEO4J_URI;
  process.env.NEO4J_USER = NEO4J_USER;
  process.env.NEO4J_PASSWORD = NEO4J_PASSWORD;

  // Need a fresh GraphService for the singleton used by correlation service
  // Since correlation.service imports graphService singleton, set env vars and reconnect
  const { graphService } = await import('../src/services/graph.service.js');
  await graphService.connect();

  try {
    const correlationService = new CorrelationService();
    const results = await correlationService.computeForUser(SPIKE_USER_ID);

    log('Correlation Results', {
      count: results.length,
      results,
    });

    // Now read them back from the graph
    const storedCorrelations = await graphService.getCorrelations(SPIKE_USER_ID);
    log('Stored Correlations (read from Neo4j)', storedCorrelations);
  } finally {
    await graphService.disconnect();
  }
}

// ─── Step 5: Cleanup ─────────────────────────────────────────

async function step5_cleanup() {
  console.log('\n🧹 Step 5: Cleaning up spike data...');

  const driver = neo4j.driver(NEO4J_URI, neo4j.auth.basic(NEO4J_USER, NEO4J_PASSWORD));
  const session = driver.session();

  try {
    // Delete all nodes/edges for the spike user
    const result = await session.executeWrite(async (tx) => {
      // First delete relationships, then nodes
      return tx.run(
        `MATCH (n {userId: $userId})
         DETACH DELETE n`,
        { userId: SPIKE_USER_ID }
      );
    });

    // Also clean up MetricType nodes
    await session.executeWrite(async (tx) => {
      return tx.run(
        `MATCH (n:MetricType {userId: $userId})
         DETACH DELETE n`,
        { userId: SPIKE_USER_ID }
      );
    });

    console.log('  ✅ Spike data cleaned up');
  } finally {
    await session.close();
    await driver.close();
  }
}

// ─── Main ────────────────────────────────────────────────────

async function main() {
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║  Neo4j End-to-End Spike                                ║');
  console.log('║  Testing: connect → ingest → query → correlate → read  ║');
  console.log('╚══════════════════════════════════════════════════════════╝');

  try {
    await step1_rawDriverTest();
    await step2_ingest();
    await step3_queryAndInspect();
    await step4_correlationEngine();
    await step5_cleanup();

    console.log('\n✅ SPIKE COMPLETE — all steps passed');
  } catch (err) {
    console.error('\n❌ SPIKE FAILED:', err);
    // Still try to clean up
    try { await step5_cleanup(); } catch { /* ignore */ }
    process.exit(1);
  }
}

main();
