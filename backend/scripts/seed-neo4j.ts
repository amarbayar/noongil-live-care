/**
 * Backfill Firestore check-ins into Neo4j knowledge graph.
 *
 * Reads all check-ins for a user from Firestore, ingests each into Neo4j
 * via graphService, updates day composites, then builds causal edges.
 *
 * Usage:
 *   npx tsx scripts/seed-neo4j.ts                # auto-discovers first user
 *   npx tsx scripts/seed-neo4j.ts <userId>       # explicit user ID
 *
 * Requires:
 *   - GOOGLE_APPLICATION_CREDENTIALS or ADC configured
 *   - NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD env vars
 */

import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, type Firestore, type Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { graphService, type CheckInInput } from '../src/services/graph.service.js';
import { causalService } from '../src/services/causal.service.js';

// ─── Init ────────────────────────────────────────────────────

if (getApps().length === 0) initializeApp();
const db: Firestore = getFirestore();

// ─── Firestore → GraphService Conversion ─────────────────────

function toISO(ts: Timestamp | undefined): string {
  if (!ts) return new Date().toISOString();
  return ts.toDate().toISOString();
}

function firestoreDocToCheckInInput(docId: string, data: Record<string, unknown>): CheckInInput {
  const completedAt = toISO(data.completedAt as Timestamp | undefined);

  const mood = data.mood as Record<string, unknown> | undefined;
  const sleep = data.sleep as Record<string, unknown> | undefined;
  const symptoms = data.symptoms as Array<Record<string, unknown>> | undefined;
  const meds = data.medicationAdherence as Array<Record<string, unknown>> | undefined;

  return {
    id: docId,
    userId: data.userId as string,
    type: (data.type as string) || 'adhoc',
    completedAt,
    completionStatus: (data.completionStatus as string) || 'completed',
    durationSeconds: (data.durationSeconds as number) || 0,
    mood: mood?.score != null
      ? { score: mood.score as number, description: mood.description as string | undefined }
      : undefined,
    sleep: sleep?.hours != null && (sleep.hours as number) > 0
      ? {
          hours: sleep.hours as number,
          quality: sleep.quality as number | undefined,
          interruptions: sleep.interruptions as number | undefined,
        }
      : undefined,
    symptoms: symptoms?.length
      ? symptoms.map((s) => ({
          type: s.type as string,
          severity: s.severity as number | undefined,
          location: s.location as string | undefined,
          duration: s.duration as string | undefined,
        }))
      : undefined,
    medicationAdherence: meds?.length
      ? meds.map((m) => ({
          medicationName: m.medicationName as string,
          status: m.status as string,
          scheduledTime: m.scheduledTime as string | undefined,
          takenAt: m.takenAt ? toISO(m.takenAt as Timestamp) : undefined,
          delayMinutes: m.delayMinutes as number | undefined,
        }))
      : undefined,
  };
}

// ─── Main ────────────────────────────────────────────────────

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  let userId = args.find((a) => !a.startsWith('--'));

  if (!userId) {
    console.log('No userId provided, discovering from Firebase Auth...');
    const auth = getAuth();
    const listResult = await auth.listUsers(1);
    if (listResult.users.length === 0) {
      console.error('No users found in Firebase Auth. Pass a userId as argument.');
      process.exit(1);
    }
    userId = listResult.users[0].uid;
    const user = listResult.users[0];
    console.log(`Found user: ${user.displayName ?? user.email ?? user.uid}`);
  }

  console.log(`\nUser: ${userId}`);

  // Connect to Neo4j
  console.log('\nConnecting to Neo4j...');
  await graphService.connect();
  await causalService.connect();
  console.log('Connected.');

  // Read all check-ins from Firestore
  console.log('\nReading check-ins from Firestore...');
  const snapshot = await db
    .collection(`users/${userId}/checkins`)
    .orderBy('startedAt', 'asc')
    .get();

  if (snapshot.empty) {
    console.log('No check-ins found in Firestore. Run seed-checkins.ts first.');
    await cleanup();
    return;
  }

  console.log(`Found ${snapshot.size} check-ins.\n`);

  // Ingest each check-in into Neo4j
  const dates = new Set<string>();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const checkIn = firestoreDocToCheckInInput(doc.id, data);
    const date = checkIn.completedAt.split('T')[0];
    dates.add(date);

    try {
      await graphService.ingestCheckIn(userId!, checkIn);
      const type = (checkIn.type || 'adhoc').padEnd(7);
      const moodStr = checkIn.mood ? `mood=${checkIn.mood.score}` : 'mood=—';
      const sleepStr = checkIn.sleep ? `sleep=${checkIn.sleep.hours}h` : 'sleep=—';
      const symStr = `symptoms=${checkIn.symptoms?.length ?? 0}`;
      console.log(`  ✓ ${date} ${type} ${moodStr}  ${sleepStr}  ${symStr}`);
    } catch (err) {
      console.error(`  ✗ ${date} ${checkIn.type}: ${err}`);
    }
  }

  // Update day composites
  console.log('\nUpdating day composites...');
  for (const date of Array.from(dates).sort()) {
    const score = await graphService.updateDayComposite(userId!, date);
    console.log(`  ${date} → overallScore=${score?.toFixed(2) ?? 'null'}`);
  }

  // Build causal edges
  console.log('\nBuilding causal edges...');
  const result = await causalService.buildCausalEdges(userId!);
  console.log(`  Found ${result.spikesFound} spikes, created ${result.created} causal edges.`);

  await cleanup();
  console.log('\nDone!');
}

async function cleanup(): Promise<void> {
  await causalService.disconnect();
  await graphService.disconnect();
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
