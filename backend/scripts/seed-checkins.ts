/**
 * Seed Firestore with 1 week of realistic check-in data.
 *
 * Usage:
 *   npx tsx scripts/seed-checkins.ts                # auto-discovers first user
 *   npx tsx scripts/seed-checkins.ts <userId>       # explicit user ID
 *   npx tsx scripts/seed-checkins.ts --clean-only   # only delete, don't seed
 *
 * Requires: GOOGLE_APPLICATION_CREDENTIALS or ADC configured.
 */

import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

// ─── Init ────────────────────────────────────────────────────

if (getApps().length === 0) initializeApp();
const db: Firestore = getFirestore();

// ─── Types (mirror iOS Codable structs exactly) ──────────────

interface MoodEntry {
  score: number;
  description: string;
  label: string; // "positive" | "negative" | "neutral"
}

interface SleepEntry {
  hours: number;
  quality: number;
  interruptions: number;
  description: string;
}

interface SymptomEntry {
  type: string;
  severity: number;
  location: string | null;
  duration: string | null;
  userDescription: string | null;
  comparedToYesterday: string | null; // "better" | "same" | "worse"
}

interface MedicationAdherenceEntry {
  medicationId: string | null;
  medicationName: string;
  status: string; // "taken" | "missed" | "skipped" | "delayed"
  scheduledTime: string | null;
  takenAt: Timestamp | null;
  reportedVia: string;
}

interface CheckInDoc {
  userId: string;
  type: string; // "morning" | "evening" | "adhoc"
  startedAt: Timestamp;
  completedAt: Timestamp;
  completionStatus: string;
  durationSeconds: number;
  pipelineMode: string;
  inputMethod: string;
  mood: MoodEntry;
  sleep: SleepEntry;
  symptoms: SymptomEntry[];
  medicationAdherence: MedicationAdherenceEntry[];
  aiSummary: string;
  checkInNumber: number;
  createdAt: Timestamp;
}

// ─── Helpers ─────────────────────────────────────────────────

function ts(dateStr: string, time: string): Timestamp {
  return Timestamp.fromDate(new Date(`${dateStr}T${time}:00+08:00`));
}

function medTaken(
  name: string,
  scheduledTime: string,
  dateStr: string,
  delayMin = 0
): MedicationAdherenceEntry {
  const [h, m] = scheduledTime.split(':').map(Number);
  const takenDate = new Date(`${dateStr}T${scheduledTime}:00+08:00`);
  takenDate.setMinutes(takenDate.getMinutes() + delayMin);
  return {
    medicationId: null,
    medicationName: name,
    status: delayMin > 30 ? 'delayed' : 'taken',
    scheduledTime,
    takenAt: Timestamp.fromDate(takenDate),
    reportedVia: 'voice',
  };
}

function medMissed(name: string, scheduledTime: string): MedicationAdherenceEntry {
  return {
    medicationId: null,
    medicationName: name,
    status: 'missed',
    scheduledTime,
    takenAt: null,
    reportedVia: 'voice',
  };
}

// ─── 7-Day Journal ───────────────────────────────────────────
// Simulates a Parkinson's user over Feb 21-27, 2026.
// Embedded patterns:
//   - Sleep quality → next-day tremor severity
//   - Missed meds → stiffness spike
//   - Walking/exercise → better mood next day
//   - One bad night mid-week causes a cascade

interface DayEntry {
  date: string;
  morning: {
    startTime: string;
    endTime: string;
    mood: MoodEntry;
    sleep: SleepEntry;
    symptoms: SymptomEntry[];
    meds: MedicationAdherenceEntry[];
    summary: string;
  };
  evening?: {
    startTime: string;
    endTime: string;
    mood: MoodEntry;
    symptoms: SymptomEntry[];
    meds: MedicationAdherenceEntry[];
    summary: string;
  };
}

function buildWeek(userId: string): DayEntry[] {
  return [
    // ── Day 1 (Sat Feb 21) — Good baseline ──
    {
      date: '2026-02-21',
      morning: {
        startTime: '08:15',
        endTime: '08:28',
        mood: { score: 4, description: 'Feeling pretty good today, had a nice sleep', label: 'positive' },
        sleep: { hours: 7.5, quality: 4, interruptions: 0, description: 'Slept through the night' },
        symptoms: [
          { type: 'tremor', severity: 2, location: 'left hand', duration: 'intermittent', userDescription: 'slight shaking when I hold my cup', comparedToYesterday: 'same' },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-21', 10),
          medTaken('Pramipexole', '08:00', '2026-02-21', 10),
        ],
        summary: 'Good night of sleep (7.5h). Mild intermittent tremor in left hand. Mood positive. Medications taken on time.',
      },
      evening: {
        startTime: '20:05',
        endTime: '20:14',
        mood: { score: 4, description: 'Had a nice walk with the dog, feeling relaxed', label: 'positive' },
        symptoms: [
          { type: 'fatigue', severity: 2, location: null, duration: 'late afternoon', userDescription: 'got a bit tired around 4pm but the walk helped', comparedToYesterday: 'same' },
        ],
        meds: [
          medTaken('Levodopa', '14:00', '2026-02-21', 5),
          medTaken('Levodopa', '20:00', '2026-02-21', 5),
        ],
        summary: 'Mild afternoon fatigue, improved after evening walk. Mood remains positive. All medications taken.',
      },
    },

    // ── Day 2 (Sun Feb 22) — Good, exercise benefit ──
    {
      date: '2026-02-22',
      morning: {
        startTime: '08:30',
        endTime: '08:41',
        mood: { score: 4, description: 'Good morning, that walk yesterday really helped me sleep', label: 'positive' },
        sleep: { hours: 8, quality: 5, interruptions: 0, description: 'Best sleep in a while, fell asleep right away' },
        symptoms: [
          { type: 'tremor', severity: 1, location: 'left hand', duration: 'barely noticeable', userDescription: 'hand is steady this morning', comparedToYesterday: 'better' },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-22', 5),
          medTaken('Pramipexole', '08:00', '2026-02-22', 5),
        ],
        summary: 'Excellent sleep (8h, quality 5). Tremor notably reduced — likely from yesterday\'s exercise. Feeling positive.',
      },
    },

    // ── Day 3 (Mon Feb 23) — Sleep disrupted, tremor worse ──
    {
      date: '2026-02-23',
      morning: {
        startTime: '07:50',
        endTime: '08:05',
        mood: { score: 3, description: 'Not great, the neighbors had a party last night', label: 'negative' },
        sleep: { hours: 5.5, quality: 2, interruptions: 3, description: 'Woke up three times from the noise, only got about five and a half hours' },
        symptoms: [
          { type: 'tremor', severity: 3, location: 'left hand', duration: 'constant this morning', userDescription: 'shaking is worse today, can barely hold my phone', comparedToYesterday: 'worse' },
          { type: 'stiffness', severity: 2, location: 'shoulders', duration: 'morning', userDescription: 'shoulders feel tight', comparedToYesterday: 'worse' },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-23', 0),
          medTaken('Pramipexole', '08:00', '2026-02-23', 0),
        ],
        summary: 'Poor sleep (5.5h, 3 interruptions from noise). Tremor and stiffness both worsened. Mood low. Medications taken on time despite difficult morning.',
      },
      evening: {
        startTime: '19:45',
        endTime: '19:55',
        mood: { score: 3, description: 'Bit better now, had a quiet afternoon', label: 'neutral' },
        symptoms: [
          { type: 'tremor', severity: 2, location: 'left hand', duration: 'easing off', userDescription: 'tremor got better after the afternoon dose kicked in', comparedToYesterday: 'same' },
        ],
        meds: [
          medTaken('Levodopa', '14:00', '2026-02-23', 20),
          medTaken('Levodopa', '20:00', '2026-02-23', 0),
        ],
        summary: 'Tremor improved after afternoon medication. Quiet evening helped mood recover slightly.',
      },
    },

    // ── Day 4 (Tue Feb 24) — Recovery, missed evening meds ──
    {
      date: '2026-02-24',
      morning: {
        startTime: '08:10',
        endTime: '08:22',
        mood: { score: 3, description: 'Okay I guess, still catching up on sleep', label: 'neutral' },
        sleep: { hours: 7, quality: 3, interruptions: 1, description: 'Slept better but woke up once, took a while to fall back asleep' },
        symptoms: [
          { type: 'tremor', severity: 2, location: 'left hand', duration: 'on and off', userDescription: 'not as bad as yesterday', comparedToYesterday: 'better' },
          { type: 'fatigue', severity: 3, location: null, duration: 'all morning', userDescription: 'just feel drained', comparedToYesterday: 'worse' },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-24', 10),
          medTaken('Pramipexole', '08:00', '2026-02-24', 10),
        ],
        summary: 'Sleep improving (7h) but still fatigued from Monday. Tremor better than yesterday. Energy low.',
      },
      evening: {
        startTime: '21:30',
        endTime: '21:38',
        mood: { score: 2, description: 'Frustrated, fell asleep on the couch and missed my evening dose', label: 'negative' },
        symptoms: [
          { type: 'fatigue', severity: 4, location: null, duration: 'all evening', userDescription: 'so tired I dozed off', comparedToYesterday: 'worse' },
        ],
        meds: [
          medTaken('Levodopa', '14:00', '2026-02-24', 15),
          medMissed('Levodopa', '20:00'),
        ],
        summary: 'Fell asleep on couch, missed evening Levodopa dose. Fatigue severe. Frustration about missed medication.',
      },
    },

    // ── Day 5 (Wed Feb 25) — Missed med consequences ──
    {
      date: '2026-02-25',
      morning: {
        startTime: '08:00',
        endTime: '08:18',
        mood: { score: 2, description: 'Rough morning, body is stiff', label: 'negative' },
        sleep: { hours: 6, quality: 3, interruptions: 2, description: 'Woke up stiff and uncomfortable, hard to get back to sleep' },
        symptoms: [
          { type: 'tremor', severity: 3, location: 'left hand and arm', duration: 'since waking', userDescription: 'shaking in my whole arm not just the hand', comparedToYesterday: 'worse' },
          { type: 'stiffness', severity: 4, location: 'legs and back', duration: 'since waking', userDescription: 'legs feel like concrete, back is locked up', comparedToYesterday: 'worse' },
          { type: 'pain', severity: 2, location: 'lower back', duration: 'morning', userDescription: 'dull ache in my lower back', comparedToYesterday: null },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-25', 0),
          medTaken('Pramipexole', '08:00', '2026-02-25', 0),
        ],
        summary: 'Missed evening dose yesterday causing noticeable stiffness spike. Tremor spread to full arm. Back pain new this morning. Took morning meds immediately.',
      },
      evening: {
        startTime: '19:30',
        endTime: '19:42',
        mood: { score: 3, description: 'Better after meds kicked in, did some stretching', label: 'neutral' },
        symptoms: [
          { type: 'stiffness', severity: 2, location: 'legs', duration: 'easing', userDescription: 'stretching helped a lot', comparedToYesterday: 'better' },
          { type: 'tremor', severity: 2, location: 'left hand', duration: 'intermittent', userDescription: 'back to just the hand', comparedToYesterday: 'better' },
        ],
        meds: [
          medTaken('Levodopa', '14:00', '2026-02-25', 0),
          medTaken('Levodopa', '20:00', '2026-02-25', 0),
        ],
        summary: 'Stiffness and tremor improving after consistent medication. Stretching helped. Making sure not to miss doses again.',
      },
    },

    // ── Day 6 (Thu Feb 26) — Recovering, good day ──
    {
      date: '2026-02-26',
      morning: {
        startTime: '08:20',
        endTime: '08:32',
        mood: { score: 4, description: 'Much better today, slept well', label: 'positive' },
        sleep: { hours: 7.5, quality: 4, interruptions: 0, description: 'Slept straight through, set an alarm for my meds' },
        symptoms: [
          { type: 'tremor', severity: 2, location: 'left hand', duration: 'mild, morning only', userDescription: 'back to normal level', comparedToYesterday: 'better' },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-26', 5),
          medTaken('Pramipexole', '08:00', '2026-02-26', 5),
        ],
        summary: 'Good recovery. Sleep back to normal (7.5h). Tremor at baseline. Set medication alarm — smart strategy after Tuesday\'s miss.',
      },
      evening: {
        startTime: '20:00',
        endTime: '20:10',
        mood: { score: 4, description: 'Good day, went for a short walk and called my daughter', label: 'positive' },
        symptoms: [
          { type: 'fatigue', severity: 1, location: null, duration: 'mild late afternoon', userDescription: 'just normal tiredness', comparedToYesterday: 'better' },
        ],
        meds: [
          medTaken('Levodopa', '14:00', '2026-02-26', 0),
          medTaken('Levodopa', '20:00', '2026-02-26', 0),
        ],
        summary: 'Positive day. Walk and social connection boosted mood. Mild fatigue only. All meds on time with alarm system.',
      },
    },

    // ── Day 7 (Fri Feb 27) — Great day, best of the week ──
    {
      date: '2026-02-27',
      morning: {
        startTime: '08:05',
        endTime: '08:20',
        mood: { score: 5, description: 'Wonderful morning, feeling like myself again', label: 'positive' },
        sleep: { hours: 8, quality: 5, interruptions: 0, description: 'Deep sleep, woke up refreshed' },
        symptoms: [
          { type: 'tremor', severity: 1, location: 'left hand', duration: 'barely there', userDescription: 'hand is almost perfectly still today', comparedToYesterday: 'better' },
        ],
        meds: [
          medTaken('Levodopa', '08:00', '2026-02-27', 3),
          medTaken('Pramipexole', '08:00', '2026-02-27', 3),
        ],
        summary: 'Best morning of the week. Excellent sleep, minimal tremor, high mood. Two days of consistent meds and exercise paying off.',
      },
      evening: {
        startTime: '19:50',
        endTime: '20:02',
        mood: { score: 5, description: 'Great day all around, gardened for an hour', label: 'positive' },
        symptoms: [],
        meds: [
          medTaken('Levodopa', '14:00', '2026-02-27', 0),
          medTaken('Levodopa', '20:00', '2026-02-27', 0),
        ],
        summary: 'Excellent day. No notable symptoms. Gardening for an hour with steady hands. All medications on time.',
      },
    },
  ];
}

// ─── Build Firestore documents ───────────────────────────────

function buildCheckInDocs(userId: string): CheckInDoc[] {
  const week = buildWeek(userId);
  const docs: CheckInDoc[] = [];
  let checkInNumber = 1;

  for (const day of week) {
    // Morning check-in
    const m = day.morning;
    docs.push({
      userId,
      type: 'morning',
      startedAt: ts(day.date, m.startTime),
      completedAt: ts(day.date, m.endTime),
      completionStatus: 'completed',
      durationSeconds: timeDiffSeconds(m.startTime, m.endTime),
      pipelineMode: 'live',
      inputMethod: 'voice',
      mood: m.mood,
      sleep: m.sleep,
      symptoms: m.symptoms,
      medicationAdherence: m.meds,
      aiSummary: m.summary,
      checkInNumber: checkInNumber++,
      createdAt: ts(day.date, m.startTime),
    });

    // Evening check-in (if present)
    if (day.evening) {
      const e = day.evening;
      docs.push({
        userId,
        type: 'evening',
        startedAt: ts(day.date, e.startTime),
        completedAt: ts(day.date, e.endTime),
        completionStatus: 'completed',
        durationSeconds: timeDiffSeconds(e.startTime, e.endTime),
        pipelineMode: 'live',
        inputMethod: 'voice',
        mood: e.mood,
        sleep: { hours: 0, quality: 0, interruptions: 0, description: '' },
        symptoms: e.symptoms,
        medicationAdherence: e.meds,
        aiSummary: e.summary,
        checkInNumber: checkInNumber++,
        createdAt: ts(day.date, e.startTime),
      });
    }
  }

  return docs;
}

function timeDiffSeconds(start: string, end: string): number {
  const [sh, sm] = start.split(':').map(Number);
  const [eh, em] = end.split(':').map(Number);
  return (eh * 60 + em - sh * 60 - sm) * 60;
}

// ─── Firestore Operations ────────────────────────────────────

async function deleteCollection(path: string): Promise<number> {
  const coll = db.collection(path);
  const snapshot = await coll.get();
  if (snapshot.empty) return 0;

  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return snapshot.size;
}

async function cleanUser(userId: string): Promise<void> {
  const collections = ['checkins', 'transcripts', 'medication_adherence'];
  for (const col of collections) {
    const path = `users/${userId}/${col}`;
    const count = await deleteCollection(path);
    console.log(`  Deleted ${count} docs from ${col}`);
  }
}

async function seedCheckIns(userId: string): Promise<void> {
  const docs = buildCheckInDocs(userId);
  const coll = db.collection(`users/${userId}/checkins`);

  for (const doc of docs) {
    const ref = coll.doc();
    await ref.set(doc);
    const date = doc.startedAt.toDate().toISOString().slice(0, 10);
    console.log(`  #${doc.checkInNumber} ${doc.type.padEnd(7)} ${date}  mood=${doc.mood.score}  sleep=${doc.sleep.hours}h  symptoms=${doc.symptoms.length}`);
  }

  console.log(`\n  Seeded ${docs.length} check-ins.`);
}

// ─── Main ────────────────────────────────────────────────────

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const cleanOnly = args.includes('--clean-only');
  let userId = args.find((a) => !a.startsWith('--'));

  if (!userId) {
    // Auto-discover first user from Firebase Auth
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

  // Clean
  console.log('\nCleaning existing data...');
  await cleanUser(userId);

  if (cleanOnly) {
    console.log('\nDone (clean only).');
    return;
  }

  // Seed
  console.log('\nSeeding 7 days of check-ins (Feb 21-27, 2026)...\n');
  await seedCheckIns(userId);

  console.log('\nDone!');
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
