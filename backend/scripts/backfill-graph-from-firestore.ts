import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { graphService, type CheckInInput } from '../src/services/graph.service.js';
import { causalService } from '../src/services/causal.service.js';
import { correlationService } from '../src/services/correlation.service.js';

initializeApp();

const db = getFirestore();
const userId = process.argv[2];
const start = process.argv[3] ?? null;
const end = process.argv[4] ?? null;

if (!userId) {
  console.error('Usage: tsx --env-file=.env scripts/backfill-graph-from-firestore.ts <userId> [start] [end]');
  process.exit(1);
}

function toIsoDateTime(value: unknown): string {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === 'string') {
    return value;
  }
  return new Date().toISOString();
}

function inRange(isoString: string): boolean {
  const day = isoString.slice(0, 10);
  if (start && day < start) return false;
  if (end && day > end) return false;
  return true;
}

function toCheckInInput(id: string, userId: string, data: Record<string, any>): CheckInInput {
  const completedAt = toIsoDateTime(data.completedAt ?? data.createdAt);

  return {
    id,
    userId,
    type: data.type ?? 'adhoc',
    completedAt,
    completionStatus: data.completionStatus ?? 'completed',
    durationSeconds: typeof data.durationSeconds === 'number' ? data.durationSeconds : undefined,
    mood: typeof data.mood?.score === 'number'
      ? {
          score: data.mood.score,
          description: data.mood.label ?? data.mood.description,
        }
      : undefined,
    sleep: typeof data.sleep?.hours === 'number'
      ? {
          hours: data.sleep.hours,
          quality: typeof data.sleep.quality === 'number' ? data.sleep.quality : undefined,
          interruptions: typeof data.sleep.interruptions === 'number' ? data.sleep.interruptions : undefined,
        }
      : undefined,
    symptoms: Array.isArray(data.symptoms)
      ? data.symptoms.map((symptom: any) => ({
          type: symptom.type,
          severity: typeof symptom.severity === 'number' ? symptom.severity : undefined,
          location: symptom.location,
          duration: symptom.duration,
        }))
      : undefined,
    medicationAdherence: Array.isArray(data.medicationAdherence)
      ? data.medicationAdherence.map((medication: any) => ({
          medicationName: medication.medicationName,
          status: medication.status,
          scheduledTime: medication.scheduledTime,
          takenAt: medication.takenAt,
          delayMinutes: typeof medication.delayMinutes === 'number' ? medication.delayMinutes : undefined,
        }))
      : undefined,
  };
}

async function main() {
  const snap = await db.collection('users').doc(userId).collection('checkins').get();
  const checkIns = snap.docs
    .map((doc) => ({ id: doc.id, data: doc.data() as Record<string, any> }))
    .map(({ id, data }) => ({ id, payload: toCheckInInput(id, userId, data) }))
    .filter(({ payload }) => inRange(payload.completedAt))
    .sort((a, b) => a.payload.completedAt.localeCompare(b.payload.completedAt));

  console.log(`Backfilling ${checkIns.length} check-ins for ${userId}`);

  await graphService.connect();
  await causalService.connect();

  try {
    for (const { id, payload } of checkIns) {
      const eventId = `${id}_graph_sync`;
      const result = await graphService.ingestCheckIn(userId, eventId, payload);
      await graphService.updateDayComposite(userId, payload.completedAt.slice(0, 10));
      console.log(`${payload.completedAt.slice(0, 10)} ${id} duplicate=${result.duplicate}`);
    }

    await causalService.buildCausalEdges(userId);
    await correlationService.computeForUser(userId);
  } finally {
    await causalService.disconnect();
    await graphService.disconnect();
  }

  console.log('Backfill complete.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
