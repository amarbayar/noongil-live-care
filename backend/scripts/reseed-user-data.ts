import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

initializeApp();
const db = getFirestore();
const uid = 'LqpiaTQgWjdHwcvqMsMoFqVbt5c2';

// Step 1: Delete all existing check-ins
const checkInsRef = db.collection('users').doc(uid).collection('checkins');
const existing = await checkInsRef.get();
console.log(`Deleting ${existing.size} existing check-ins...`);

const batch = db.batch();
for (const doc of existing.docs) {
  batch.delete(doc.ref);
}
await batch.commit();
console.log('Deleted.');

// Step 2: Seed fresh check-ins for the last 7 days
const calendar = new Date();
calendar.setHours(8, 30, 0, 0);

interface DaySeed {
  ago: number;
  moodScore: number;
  moodLabel: string;
  sleepHours: number;
  sleepQuality: number;
  symptoms: Array<{ type: string; severity: number }>;
  summary: string;
}

const days: DaySeed[] = [
  {
    ago: 6, moodScore: 4, moodLabel: 'positive', sleepHours: 7.5, sleepQuality: 4,
    symptoms: [{ type: 'tremor', severity: 2 }],
    summary: 'Good morning. Slept well, mild tremor. Took meds on time. Feeling positive.',
  },
  {
    ago: 5, moodScore: 3, moodLabel: 'neutral', sleepHours: 5.5, sleepQuality: 2,
    symptoms: [{ type: 'tremor', severity: 4 }, { type: 'stiffness', severity: 3 }],
    summary: 'Poor sleep from noise. Tremor and stiffness both worsened. Low energy.',
  },
  {
    ago: 4, moodScore: 4, moodLabel: 'positive', sleepHours: 8, sleepQuality: 5,
    symptoms: [{ type: 'tremor', severity: 1 }],
    summary: 'Great sleep. Tremor notably reduced. Afternoon walk helped. Feeling good.',
  },
  {
    ago: 3, moodScore: 2, moodLabel: 'negative', sleepHours: 6, sleepQuality: 3,
    symptoms: [{ type: 'stiffness', severity: 4 }, { type: 'fatigue', severity: 3 }],
    summary: 'Missed evening dose yesterday. Stiffness spike this morning. Frustrated.',
  },
  {
    ago: 2, moodScore: 3, moodLabel: 'neutral', sleepHours: 7, sleepQuality: 4,
    symptoms: [{ type: 'tremor', severity: 2 }, { type: 'stiffness', severity: 2 }],
    summary: 'Recovering from missed dose. Stiffness improving. Back on schedule.',
  },
  {
    ago: 1, moodScore: 5, moodLabel: 'positive', sleepHours: 7.5, sleepQuality: 5,
    symptoms: [{ type: 'tremor', severity: 1 }],
    summary: 'Best day this week. Gardened for an hour with steady hands. All meds on time.',
  },
  {
    ago: 0, moodScore: 4, moodLabel: 'positive', sleepHours: 7, sleepQuality: 4,
    symptoms: [{ type: 'tremor', severity: 2 }],
    summary: 'Good morning. Slept well. Mild tremor, manageable. Ready for the day.',
  },
];

console.log('Seeding 7 days of fresh check-ins...');

for (const day of days) {
  const date = new Date();
  date.setDate(date.getDate() - day.ago);
  date.setHours(8, 30, 0, 0);

  const completedAt = new Date(date);
  completedAt.setMinutes(completedAt.getMinutes() + 8 + Math.floor(Math.random() * 5));

  const checkIn = {
    userId: uid,
    type: 'adhoc',
    pipelineMode: 'unified',
    inputMethod: 'voice',
    startedAt: Timestamp.fromDate(date),
    completedAt: Timestamp.fromDate(completedAt),
    completionStatus: 'completed',
    durationSeconds: Math.floor((completedAt.getTime() - date.getTime()) / 1000),
    createdAt: Timestamp.fromDate(date),
    mood: {
      score: day.moodScore,
      label: day.moodLabel,
    },
    sleep: {
      hours: day.sleepHours,
      quality: day.sleepQuality,
    },
    symptoms: day.symptoms.map(s => ({
      type: s.type,
      severity: s.severity,
    })),
    medicationAdherence: [
      { medicationName: 'Levodopa', status: day.ago === 3 ? 'missed' : 'taken' },
    ],
    aiSummary: day.summary,
  };

  const ref = await checkInsRef.add(checkIn);
  const dateStr = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  console.log(`  ${dateStr} → ${ref.id} (mood: ${day.moodScore}, sleep: ${day.sleepHours}h)`);
}

console.log('\nDone! 7 fresh check-ins seeded (today through 6 days ago).');
