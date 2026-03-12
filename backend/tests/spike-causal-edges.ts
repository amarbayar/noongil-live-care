/**
 * CAUSAL EDGE BUILDER
 *
 * Adds LIKELY_CAUSED_BY and WORSENED_BY edges between specific event nodes
 * based on temporal proximity + known correlation patterns.
 *
 * Logic:
 *   1. Find symptom spikes (severity > user's baseline for that symptom)
 *   2. Look back 1-3 days for anomalies: poor sleep, missed meds, late meds, triggers
 *   3. Score each candidate cause using the stored CORRELATES_WITH coefficients
 *   4. Create explicit causal hypothesis edges with confidence scores
 *
 * Run: npx tsx tests/spike-causal-edges.ts
 */

import neo4j from 'neo4j-driver';

const NEO4J_URI = process.env.NEO4J_URI;
const NEO4J_USER = process.env.NEO4J_USER;
const NEO4J_PASSWORD = process.env.NEO4J_PASSWORD;

const USER_ID = 'margaret-sim';

async function main() {
  if (!NEO4J_URI || !NEO4J_USER || !NEO4J_PASSWORD) {
    throw new Error('Set NEO4J_URI, NEO4J_USER, and NEO4J_PASSWORD before running this spike script.');
  }

  const driver = neo4j.driver(NEO4J_URI, neo4j.auth.basic(NEO4J_USER, NEO4J_PASSWORD));
  const session = driver.session();

  try {
    console.log('🔗 Building causal edges for Margaret\'s graph...\n');

    // ── Step 1: Compute baselines ──
    // Average severity per symptom type = the user's "normal"
    const baselineResult = await session.executeRead(async (tx) => {
      return tx.run(`
        MATCH (sy:Symptom)-[:ON_DAY]->(d:Day {userId: $userId})
        WITH sy.type AS type, avg(sy.severity) AS avgSeverity, stDev(sy.severity) AS stdSeverity
        RETURN type, avgSeverity, stdSeverity
      `, { userId: USER_ID });
    });

    const baselines: Record<string, { avg: number; std: number }> = {};
    for (const record of baselineResult.records) {
      const type = record.get('type');
      baselines[type] = {
        avg: record.get('avgSeverity'),
        std: record.get('stdSeverity') || 0.5,
      };
    }
    console.log('📊 Baselines:', JSON.stringify(baselines, null, 2));

    // Same for sleep
    const sleepBaseline = await session.executeRead(async (tx) => {
      return tx.run(`
        MATCH (sl:SleepEntry)-[:ON_DAY]->(d:Day {userId: $userId})
        RETURN avg(sl.hours) AS avgHours, stDev(sl.hours) AS stdHours,
               avg(sl.quality) AS avgQuality, stDev(sl.quality) AS stdQuality
      `, { userId: USER_ID });
    });
    const sleepRec = sleepBaseline.records[0];
    const sleepAvg = { hours: sleepRec.get('avgHours'), quality: sleepRec.get('avgQuality') };
    const sleepStd = { hours: sleepRec.get('stdHours') || 0.5, quality: sleepRec.get('stdQuality') || 0.5 };
    console.log('😴 Sleep baseline:', JSON.stringify({ avg: sleepAvg, std: sleepStd }, null, 2));

    // ── Step 2: Find symptom spikes ──
    // A spike = severity > baseline + 1 std deviation
    const spikes = await session.executeRead(async (tx) => {
      return tx.run(`
        MATCH (sy:Symptom)-[:ON_DAY]->(d:Day {userId: $userId})
        RETURN sy, d.date AS date, sy.type AS type, sy.severity AS severity,
               elementId(sy) AS syId
        ORDER BY d.date
      `, { userId: USER_ID });
    });

    const spikeEvents: Array<{ syId: string; date: string; type: string; severity: number }> = [];
    for (const record of spikes.records) {
      const type = record.get('type');
      const severity = typeof record.get('severity') === 'object'
        ? record.get('severity').low : record.get('severity');
      const baseline = baselines[type];
      if (baseline && severity > baseline.avg + baseline.std) {
        const dateObj = record.get('date');
        const y = dateObj.year.low || dateObj.year;
        const m = String(dateObj.month.low || dateObj.month).padStart(2, '0');
        const dd = String(dateObj.day.low || dateObj.day).padStart(2, '0');
        spikeEvents.push({
          syId: record.get('syId'),
          date: `${y}-${m}-${dd}`,
          type,
          severity,
        });
      }
    }
    console.log(`\n🔺 Found ${spikeEvents.length} symptom spikes above baseline:`);
    for (const s of spikeEvents) {
      const b = baselines[s.type];
      console.log(`   ${s.date}: ${s.type} severity ${s.severity} (baseline: ${b.avg.toFixed(1)} ± ${b.std.toFixed(1)})`);
    }

    // ── Step 3: For each spike, find candidate causes in preceding 1-3 days ──
    console.log('\n🔍 Tracing causes for each spike...');

    await session.executeWrite(async (tx) => {
      // First clean up any previous causal edges
      await tx.run(`
        MATCH ()-[r:LIKELY_CAUSED_BY]->() DELETE r
      `);
      await tx.run(`
        MATCH ()-[r:WORSENED_BY]->() DELETE r
      `);

      for (const spike of spikeEvents) {
        console.log(`\n   ── ${spike.date}: ${spike.type} (severity ${spike.severity}) ──`);

        // a) Poor sleep in prior 1-2 days
        const poorSleep = await tx.run(`
          MATCH (d:Day {userId: $userId})
          WHERE d.date >= date($startDate) AND d.date < date($spikeDate)
          MATCH (sl:SleepEntry)-[r:ON_DAY]->(d)
          WHERE sl.hours < $sleepThreshold OR sl.quality < $qualityThreshold
          RETURN sl, d.date AS date, sl.hours AS hours, sl.quality AS quality,
                 elementId(sl) AS slId
        `, {
          userId: USER_ID,
          spikeDate: spike.date,
          startDate: subtractDays(spike.date, 2),
          sleepThreshold: sleepAvg.hours - sleepStd.hours,
          qualityThreshold: sleepAvg.quality - sleepStd.quality,
        });

        for (const rec of poorSleep.records) {
          const hours = typeof rec.get('hours') === 'object' ? rec.get('hours').low : rec.get('hours');
          const quality = typeof rec.get('quality') === 'object' ? rec.get('quality').low : rec.get('quality');
          const dateObj = rec.get('date');
          const dateStr = formatDate(dateObj);
          console.log(`      ← Poor sleep on ${dateStr}: ${hours}h, quality ${quality}`);

          await tx.run(`
            MATCH (sy) WHERE elementId(sy) = $syId
            MATCH (sl) WHERE elementId(sl) = $slId
            CREATE (sy)-[:LIKELY_CAUSED_BY {
              reason: 'poor_sleep',
              confidence: $confidence,
              daysBefore: $daysBefore,
              detail: $detail
            }]->(sl)
          `, {
            syId: spike.syId,
            slId: rec.get('slId'),
            confidence: 0.75,
            daysBefore: daysDiff(dateStr, spike.date),
            detail: `Sleep ${hours}h (quality ${quality}) → ${spike.type} severity ${spike.severity}`,
          });
        }

        // b) Missed or late medications in prior 1-2 days
        const missedMeds = await tx.run(`
          MATCH (d:Day {userId: $userId})
          WHERE d.date >= date($startDate) AND d.date <= date($spikeDate)
          MATCH (md:MedicationDose)-[r:ON_DAY]->(d)
          WHERE md.status = 'missed' OR md.delayMinutes > 30
          RETURN md, d.date AS date, md.medicationName AS name,
                 md.status AS status, md.delayMinutes AS delay,
                 elementId(md) AS mdId
        `, {
          userId: USER_ID,
          spikeDate: spike.date,
          startDate: subtractDays(spike.date, 2),
        });

        for (const rec of missedMeds.records) {
          const name = rec.get('name');
          const status = rec.get('status');
          const delay = typeof rec.get('delay') === 'object' ? rec.get('delay').low : rec.get('delay');
          const dateStr = formatDate(rec.get('date'));
          const reason = status === 'missed' ? `Missed ${name}` : `${name} ${delay}min late`;
          console.log(`      ← ${reason} on ${dateStr}`);

          await tx.run(`
            MATCH (sy) WHERE elementId(sy) = $syId
            MATCH (md) WHERE elementId(md) = $mdId
            CREATE (sy)-[:LIKELY_CAUSED_BY {
              reason: $reason,
              confidence: $confidence,
              daysBefore: $daysBefore,
              detail: $detail
            }]->(md)
          `, {
            syId: spike.syId,
            mdId: rec.get('mdId'),
            reason: status === 'missed' ? 'missed_medication' : 'late_medication',
            confidence: status === 'missed' ? 0.85 : 0.6,
            daysBefore: daysDiff(dateStr, spike.date),
            detail: `${reason} on ${dateStr} → ${spike.type} severity ${spike.severity}`,
          });
        }

        // c) Stress triggers in prior 1-2 days
        const triggers = await tx.run(`
          MATCH (d:Day {userId: $userId})
          WHERE d.date >= date($startDate) AND d.date <= date($spikeDate)
          MATCH (t:Trigger)-[r:TRIGGERED_ON]->(d)
          RETURN t, d.date AS date, t.name AS name, t.type AS type,
                 elementId(t) AS tId
        `, {
          userId: USER_ID,
          spikeDate: spike.date,
          startDate: subtractDays(spike.date, 2),
        });

        for (const rec of triggers.records) {
          const name = rec.get('name');
          const dateStr = formatDate(rec.get('date'));
          console.log(`      ← Trigger: "${name}" on ${dateStr}`);

          await tx.run(`
            MATCH (sy) WHERE elementId(sy) = $syId
            MATCH (t) WHERE elementId(t) = $tId
            CREATE (sy)-[:WORSENED_BY {
              reason: 'stress_trigger',
              confidence: 0.5,
              daysBefore: $daysBefore,
              detail: $detail
            }]->(t)
          `, {
            syId: spike.syId,
            tId: rec.get('tId'),
            daysBefore: daysDiff(dateStr, spike.date),
            detail: `Trigger "${name}" → ${spike.type} severity ${spike.severity}`,
          });
        }
      }
    });

    // ── Step 4: Summary ──
    const causalCount = await session.executeRead(async (tx) => {
      return tx.run(`
        MATCH ()-[r:LIKELY_CAUSED_BY|WORSENED_BY]->()
        RETURN type(r) AS type, count(r) AS count
      `);
    });

    console.log('\n\n✅ Causal edges created:');
    for (const rec of causalCount.records) {
      console.log(`   ${rec.get('type')}: ${rec.get('count').low}`);
    }

    // Print visualization queries
    console.log(`

╔══════════════════════════════════════════════════════════════╗
║  CAUSAL TRACE QUERIES — paste into Aura console             ║
╚══════════════════════════════════════════════════════════════╝

━━━ TRACE: Why was tremor bad on Feb 9? ━━━
MATCH (sy:Symptom {type: 'tremor'})-[r1:ON_DAY]->(d:Day {date: date('2026-02-09'), userId: '${USER_ID}'})
WHERE sy.severity >= 4
OPTIONAL MATCH (sy)-[caused:LIKELY_CAUSED_BY]->(cause)
OPTIONAL MATCH (sy)-[worsened:WORSENED_BY]->(trigger)
OPTIONAL MATCH (cause)-[r2:ON_DAY]->(causeDay:Day)
OPTIONAL MATCH (trigger)-[r3:TRIGGERED_ON]->(triggerDay:Day)
RETURN sy, d, r1, caused, cause, r2, causeDay, worsened, trigger, r3, triggerDay

━━━ TRACE: Why was tremor bad on Feb 16-17? ━━━
MATCH (sy:Symptom {type: 'tremor'})-[r1:ON_DAY]->(d:Day {userId: '${USER_ID}'})
WHERE d.date >= date('2026-02-16') AND d.date <= date('2026-02-17')
AND sy.severity >= 3
OPTIONAL MATCH (sy)-[caused:LIKELY_CAUSED_BY]->(cause)
OPTIONAL MATCH (sy)-[worsened:WORSENED_BY]->(trigger)
OPTIONAL MATCH (cause)-[r2:ON_DAY]->(causeDay:Day)
OPTIONAL MATCH (trigger)-[r3:TRIGGERED_ON]->(triggerDay:Day)
RETURN sy, d, r1, caused, cause, r2, causeDay, worsened, trigger, r3, triggerDay

━━━ ALL CAUSAL CHAINS (full picture) ━━━
MATCH (sy:Symptom)-[r1:ON_DAY]->(d:Day {userId: '${USER_ID}'})
WHERE EXISTS { (sy)-[:LIKELY_CAUSED_BY|WORSENED_BY]->() }
MATCH (sy)-[causal:LIKELY_CAUSED_BY|WORSENED_BY]->(cause)
OPTIONAL MATCH (cause)-[r2:ON_DAY]->(causeDay:Day)
OPTIONAL MATCH (cause)-[r3:TRIGGERED_ON]->(triggerDay:Day)
RETURN sy, d, r1, causal, cause, r2, causeDay, r3, triggerDay

━━━ GENERIC: Trace any symptom on any date ━━━
━━━ (change the date and type) ━━━
MATCH (sy:Symptom {type: 'tremor'})-[r1:ON_DAY]->(d:Day {date: date('2026-02-09'), userId: '${USER_ID}'})
OPTIONAL MATCH (sy)-[causal:LIKELY_CAUSED_BY|WORSENED_BY]->(cause)
OPTIONAL MATCH (cause)-[r2:ON_DAY|TRIGGERED_ON]->(causeDay)
RETURN sy, d, r1, causal, cause, r2, causeDay
`);

  } finally {
    await session.close();
    await driver.close();
  }
}

function subtractDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().split('T')[0];
}

function formatDate(dateObj: any): string {
  const y = dateObj.year?.low ?? dateObj.year;
  const m = String(dateObj.month?.low ?? dateObj.month).padStart(2, '0');
  const d = String(dateObj.day?.low ?? dateObj.day).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function daysDiff(dateA: string, dateB: string): number {
  const a = new Date(dateA + 'T00:00:00Z');
  const b = new Date(dateB + 'T00:00:00Z');
  return Math.round((b.getTime() - a.getTime()) / (86400 * 1000));
}

main();
