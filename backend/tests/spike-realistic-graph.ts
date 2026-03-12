/**
 * REALISTIC GRAPH SIMULATION
 *
 * Simulates Margaret, 67, early-stage Parkinson's, over 30 days.
 * Natural diary entries → entity extraction → graph building → visualization.
 *
 * Run: npx tsx tests/spike-realistic-graph.ts
 * Then open Neo4j Aura console → Query tab → paste the visualization queries printed at the end.
 */

import neo4j from 'neo4j-driver';
import { GraphService, type CheckInInput } from '../src/services/graph.service.js';
import { CorrelationService } from '../src/services/correlation.service.js';

const NEO4J_URI = process.env.NEO4J_URI ?? '';
const NEO4J_USER = process.env.NEO4J_USER ?? '';
const NEO4J_PASSWORD = process.env.NEO4J_PASSWORD ?? '';

const USER_ID = 'margaret-sim';

// ─── Margaret's 30-Day Journal ───────────────────────────────
//
// Each entry simulates what Mira would extract from a voice check-in.
// Patterns embedded in the data:
//   - Sleep drops → tremor worsens next day
//   - Missed Levodopa → stiffness spike 1-2 days later
//   - Good walks → better mood next day
//   - Stress events (daughter visit, plumber) → sleep disruption
//   - Gradual medication timing drift week 3
//   - Week 4 recovery after neurologist adjusts dosage

interface DayJournal {
  date: string;
  diary: string;  // What Margaret actually said to Mira
  // Extracted by Gemini (simulated):
  mood: { score: number; description: string };
  sleep: { hours: number; quality: number; interruptions: number };
  symptoms: Array<{ type: string; severity: number; location?: string; duration?: string }>;
  medications: Array<{ name: string; status: 'taken' | 'missed' | 'late'; scheduledTime: string; delayMinutes?: number }>;
  activities?: string[];
  concerns?: string[];
}

const JOURNAL: DayJournal[] = [
  // ── Week 1: Baseline (stable) ──
  {
    date: '2026-02-01',
    diary: "Good morning Mira. Slept okay, about seven hours. The usual tremor in my left hand but nothing too bad. Took my Levodopa with breakfast. Feeling pretty good actually, might go for a walk later.",
    mood: { score: 4, description: 'positive, energetic' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 2, location: 'left hand', duration: 'intermittent' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['walking'],
  },
  {
    date: '2026-02-02',
    diary: "Morning Mira. Went for that walk yesterday and I think it helped — I feel good today. Slept well, maybe seven and a half hours. Hand is steady this morning. Already took my pills.",
    mood: { score: 4, description: 'good, walk helped' },
    sleep: { hours: 7.5, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand', duration: 'minimal' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['reading'],
  },
  {
    date: '2026-02-03',
    diary: "Hi Mira. Not as great today. Only got about six hours of sleep — the neighbor's dog was barking. Tremor is a bit worse, maybe a two or three. Feeling a little foggy. Took my morning meds though.",
    mood: { score: 3, description: 'foggy, tired' },
    sleep: { hours: 6, quality: 3, interruptions: 2 },
    symptoms: [
      { type: 'tremor', severity: 3, location: 'left hand', duration: '30 min' },
      { type: 'brain_fog', severity: 2, duration: 'morning' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 15 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
  },
  {
    date: '2026-02-04',
    diary: "Better today Mira, thank goodness. Got almost eight hours. The tremor calmed down. I did some gentle stretching this morning, felt nice. Mood is good.",
    mood: { score: 4, description: 'recovered, calm' },
    sleep: { hours: 7.8, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand', duration: 'brief' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['stretching'],
  },
  {
    date: '2026-02-05',
    diary: "Mira, today was lovely. Went to the garden center with my friend Ruth. Hands were steady enough to pick out some seedlings. Slept well, took everything on time. This is a good stretch.",
    mood: { score: 5, description: 'happy, social' },
    sleep: { hours: 7.5, quality: 5, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand', duration: 'none noticed' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['gardening', 'socializing'],
  },
  {
    date: '2026-02-06',
    diary: "Hi Mira. Pretty normal day. Tremor was about a two, which is my usual. Slept fine. I noticed some stiffness in my right shoulder when I was getting dressed. First time I've felt that there.",
    mood: { score: 3, description: 'neutral, noticing new symptom' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [
      { type: 'tremor', severity: 2, location: 'left hand' },
      { type: 'stiffness', severity: 2, location: 'right shoulder', duration: '20 min' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 10 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['new stiffness in right shoulder'],
  },
  {
    date: '2026-02-07',
    diary: "Morning. Okay night, about six and a half hours. The shoulder stiffness is gone today, so maybe it was just how I slept. Tremor normal. Taking it easy today.",
    mood: { score: 3, description: 'cautious but okay' },
    sleep: { hours: 6.5, quality: 3, interruptions: 1 },
    symptoms: [{ type: 'tremor', severity: 2, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
  },

  // ── Week 2: Stress event + sleep disruption ──
  {
    date: '2026-02-08',
    diary: "Mira, my daughter Sarah called — she's coming to visit this weekend with the grandkids. I'm excited but also a little anxious. You know how tiring it can be. Didn't sleep great, kept thinking about getting the house ready. Tremor worse today.",
    mood: { score: 3, description: 'anxious about visit, excited' },
    sleep: { hours: 5.5, quality: 2, interruptions: 3 },
    symptoms: [
      { type: 'tremor', severity: 3, location: 'left hand', duration: 'most of morning' },
      { type: 'anxiety', severity: 3 },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 25 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['anxious about family visit'],
  },
  {
    date: '2026-02-09',
    diary: "Terrible night. Maybe four hours? I was up cleaning and then couldn't fall asleep. My hand is really shaking today. Also my balance felt off when I got up — had to hold the wall. I forgot to take my evening Pramipexole last night, I was so distracted.",
    mood: { score: 2, description: 'exhausted, frustrated' },
    sleep: { hours: 4, quality: 1, interruptions: 4 },
    symptoms: [
      { type: 'tremor', severity: 4, location: 'left hand', duration: 'constant' },
      { type: 'balance_issues', severity: 3, duration: 'morning' },
      { type: 'fatigue', severity: 4 },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 40 },
      { name: 'Pramipexole', status: 'missed', scheduledTime: '20:00' },
    ],
    concerns: ['missed evening medication', 'balance issues when standing'],
  },
  {
    date: '2026-02-10',
    diary: "Sarah and the kids arrived. It's wonderful to see them but I'm so tired. The tremor is still bad. I couldn't hold my coffee cup steady at lunch — Tommy noticed and asked if I was okay. That was hard. Slept a little better at least, maybe six hours.",
    mood: { score: 2, description: 'emotional, embarrassed about tremor' },
    sleep: { hours: 6, quality: 3, interruptions: 1 },
    symptoms: [
      { type: 'tremor', severity: 4, location: 'left hand', duration: 'all day' },
      { type: 'fatigue', severity: 3 },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 10 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['grandson noticed tremor', 'difficulty holding cup'],
  },
  {
    date: '2026-02-11',
    diary: "The kids wore me out yesterday but in a good way. Sarah made dinner which was sweet. Slept better — seven hours. Tremor is calming down a bit, maybe a three. Still a bit stiff but managing.",
    mood: { score: 3, description: 'tired but grateful' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [
      { type: 'tremor', severity: 3, location: 'left hand' },
      { type: 'stiffness', severity: 2, location: 'right shoulder' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['family time'],
  },
  {
    date: '2026-02-12',
    diary: "Everyone left today. The house is quiet again. I feel a bit down honestly. But I slept well and the tremor is back to a two. Going to have a quiet evening.",
    mood: { score: 2, description: 'lonely after family left' },
    sleep: { hours: 7.5, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 2, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
  },
  {
    date: '2026-02-13',
    diary: "Feeling better today Mira. Called Ruth and we're going for a walk tomorrow. That gives me something to look forward to. Sleep was good, tremor is mild. Back to my routine.",
    mood: { score: 4, description: 'better, making plans' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 2, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
  },
  {
    date: '2026-02-14',
    diary: "Happy Valentine's Day Mira. Went for that walk with Ruth — about forty minutes. It felt so good to move. Tremor was barely there. I think the walking really helps. Took everything on time today.",
    mood: { score: 5, description: 'great, exercise helped' },
    sleep: { hours: 7.5, quality: 5, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand', duration: 'barely noticed' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['walking', 'socializing'],
  },

  // ── Week 3: Medication timing drift ──
  {
    date: '2026-02-15',
    diary: "Good morning. Slept okay — about six and a half hours. I woke up early and couldn't get back to sleep. Tremor is a two. The plumber is coming today to fix the kitchen sink so I'm a bit stressed about that.",
    mood: { score: 3, description: 'stressed about plumber visit' },
    sleep: { hours: 6.5, quality: 3, interruptions: 1 },
    symptoms: [{ type: 'tremor', severity: 2, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 20 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
  },
  {
    date: '2026-02-16',
    diary: "The plumber was here all day. Very disruptive. I forgot my morning Levodopa until almost 10. Tremor has been bad — maybe a three or four. I feel rattled. Didn't eat lunch on time either.",
    mood: { score: 2, description: 'disrupted, forgot medication' },
    sleep: { hours: 6, quality: 3, interruptions: 1 },
    symptoms: [
      { type: 'tremor', severity: 4, location: 'left hand', duration: 'afternoon' },
      { type: 'stiffness', severity: 3, location: 'legs' },
    ],
    medications: [
      { name: 'Levodopa', status: 'late', scheduledTime: '08:00', delayMinutes: 120 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['medication taken 2 hours late', 'stiffness in legs — new location'],
  },
  {
    date: '2026-02-17',
    diary: "Still recovering from yesterday. The stiffness in my legs is still there. Tremor is a three. I'm being more careful with my medication timing today — took it right at 8. But I feel like my body is punishing me for yesterday's miss.",
    mood: { score: 2, description: 'frustrated with body' },
    sleep: { hours: 5.5, quality: 2, interruptions: 2 },
    symptoms: [
      { type: 'tremor', severity: 3, location: 'left hand' },
      { type: 'stiffness', severity: 3, location: 'legs', duration: 'most of day' },
      { type: 'fatigue', severity: 3 },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['persistent leg stiffness after missed dose'],
  },
  {
    date: '2026-02-18',
    diary: "A bit better. The leg stiffness is easing up. Slept six hours. I've been thinking I should tell my neurologist about the stiffness — it seems new. Tremor back to a two.",
    mood: { score: 3, description: 'recovering, thinking about doctor' },
    sleep: { hours: 6, quality: 3, interruptions: 1 },
    symptoms: [
      { type: 'tremor', severity: 2, location: 'left hand' },
      { type: 'stiffness', severity: 2, location: 'legs', duration: 'morning only' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 10 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['want to discuss new stiffness with neurologist'],
  },
  {
    date: '2026-02-19',
    diary: "Good day today. Went for a walk — only twenty minutes but it felt good. Tremor was a one most of the day. The stiffness seems gone. Seven hours of sleep. Things are stabilizing.",
    mood: { score: 4, description: 'stabilizing, positive' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    activities: ['walking'],
  },
  {
    date: '2026-02-20',
    diary: "Mira, I took my Levodopa late again today — not as bad as the plumber day, just about 45 minutes late. I overslept. Tremor jumped to a three by noon. I really need to set an alarm.",
    mood: { score: 3, description: 'annoyed at self' },
    sleep: { hours: 8, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 3, location: 'left hand', duration: 'noon onward' }],
    medications: [
      { name: 'Levodopa', status: 'late', scheduledTime: '08:00', delayMinutes: 45 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
    concerns: ['medication timing keeps drifting'],
  },
  {
    date: '2026-02-21',
    diary: "Took meds right on time today — set an alarm like I said. What a difference. Tremor is a one, mood is good, seven hours of sleep. I should always use the alarm.",
    mood: { score: 4, description: 'on track, disciplined' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
    ],
  },

  // ── Week 4: Neurologist visit + dosage adjustment ──
  {
    date: '2026-02-22',
    diary: "Neurologist appointment today. He's adding Rasagiline to my regimen — says it should help with the stiffness I mentioned. I'm a bit nervous about a new medication but he was reassuring. Tremor was a two during the visit.",
    mood: { score: 3, description: 'anxious about new medication' },
    sleep: { hours: 6.5, quality: 3, interruptions: 1 },
    symptoms: [
      { type: 'tremor', severity: 2, location: 'left hand' },
      { type: 'anxiety', severity: 2 },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
    ],
    concerns: ['starting new medication Rasagiline'],
  },
  {
    date: '2026-02-23',
    diary: "First full day on Rasagiline. I feel a little nauseated — the doctor said that might happen the first few days. Tremor about the same, a two. Sleep was okay. I'll give it time.",
    mood: { score: 3, description: 'cautious, mildly nauseous' },
    sleep: { hours: 7, quality: 3, interruptions: 0 },
    symptoms: [
      { type: 'tremor', severity: 2, location: 'left hand' },
      { type: 'nausea', severity: 2, duration: 'morning' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
    ],
    concerns: ['nausea from new medication'],
  },
  {
    date: '2026-02-24',
    diary: "Nausea is less today, that's encouraging. And Mira — I think the stiffness is actually better? My legs felt looser when I walked to the mailbox. Tremor a two. Slept well.",
    mood: { score: 4, description: 'encouraged by improvement' },
    sleep: { hours: 7.5, quality: 4, interruptions: 0 },
    symptoms: [
      { type: 'tremor', severity: 2, location: 'left hand' },
      { type: 'nausea', severity: 1, duration: 'brief' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
    ],
  },
  {
    date: '2026-02-25',
    diary: "Great walk with Ruth today — thirty minutes! No stiffness at all. Tremor was barely a one. I think the Rasagiline is working. Mood is the best it's been in weeks. Seven and a half hours of sleep.",
    mood: { score: 5, description: 'optimistic, active' },
    sleep: { hours: 7.5, quality: 5, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand', duration: 'barely noticed' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
    ],
    activities: ['walking', 'socializing'],
  },
  {
    date: '2026-02-26',
    diary: "Another good day. Nausea is completely gone now. I feel more like myself. Went to the garden center again — bought some herbs. Tremor at one, slept seven hours. I'm grateful for this run of good days.",
    mood: { score: 5, description: 'grateful, active' },
    sleep: { hours: 7, quality: 4, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
    ],
    activities: ['gardening'],
  },
  {
    date: '2026-02-27',
    diary: "Bit of a dip today. Only five and a half hours of sleep — was reading too late. Tremor went up to a three and I had some brain fog mid-afternoon. But I know it's just the sleep. Took all meds on time.",
    mood: { score: 3, description: 'tired but self-aware' },
    sleep: { hours: 5.5, quality: 2, interruptions: 1 },
    symptoms: [
      { type: 'tremor', severity: 3, location: 'left hand', duration: 'afternoon' },
      { type: 'brain_fog', severity: 2, duration: 'afternoon' },
    ],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 5 },
    ],
  },
  {
    date: '2026-02-28',
    diary: "Last day of February. Went to bed early, got a full eight hours. What a difference — tremor is back to a one, mood is great. I'm going to tell Mira to prepare my doctor summary for my follow-up next week. Overall this month has had ups and downs but the new medication seems to be helping.",
    mood: { score: 5, description: 'reflective, optimistic' },
    sleep: { hours: 8, quality: 5, interruptions: 0 },
    symptoms: [{ type: 'tremor', severity: 1, location: 'left hand' }],
    medications: [
      { name: 'Levodopa', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
      { name: 'Pramipexole', status: 'taken', scheduledTime: '20:00' },
      { name: 'Rasagiline', status: 'taken', scheduledTime: '08:00', delayMinutes: 0 },
    ],
    activities: ['planning doctor visit'],
  },
];

// ─── Convert journal to CheckInInput ─────────────────────────

function journalToCheckIn(day: DayJournal): CheckInInput {
  const hour = day.date.endsWith('') ? '08' : '08'; // morning check-ins
  return {
    id: `ci-${day.date}`,
    userId: USER_ID,
    type: 'morning',
    completedAt: `${day.date}T${hour}:30:00Z`,
    completionStatus: 'completed',
    durationSeconds: 90 + Math.floor(Math.random() * 60),
    mood: day.mood,
    sleep: day.sleep,
    symptoms: day.symptoms,
    medicationAdherence: day.medications.map(m => ({
      medicationName: m.name,
      status: m.status === 'late' ? 'taken' : m.status,
      scheduledTime: m.scheduledTime,
      delayMinutes: m.delayMinutes ?? 0,
    })),
  };
}

// ─── Additional graph enrichment ─────────────────────────────
// Beyond what GraphService handles, add Activity, Concern, and Diary nodes
// to make the graph richer and more visual.

async function enrichGraph(driver: neo4j.Driver) {
  const session = driver.session();

  try {
    await session.executeWrite(async (tx) => {
      for (const day of JOURNAL) {
        // Store the diary text as a node
        await tx.run(`
          MATCH (d:Day {date: date($date), userId: $userId})
          CREATE (diary:DiaryEntry {
            text: $text,
            date: date($date),
            userId: $userId
          })
          MERGE (diary)-[:RECORDED_ON]->(d)
        `, { date: day.date, userId: USER_ID, text: day.diary });

        // Activity nodes (entity nodes — MERGE to deduplicate)
        if (day.activities) {
          for (const activity of day.activities) {
            await tx.run(`
              MATCH (d:Day {date: date($date), userId: $userId})
              MERGE (a:Activity {name: $name, userId: $userId})
              CREATE (ae:ActivityEvent {date: date($date), userId: $userId})
              MERGE (ae)-[:OF_TYPE]->(a)
              MERGE (ae)-[:ON_DAY]->(d)
            `, { date: day.date, userId: USER_ID, name: activity });
          }
        }

        // Concern nodes (themes Margaret mentions)
        if (day.concerns) {
          for (const concern of day.concerns) {
            await tx.run(`
              MATCH (d:Day {date: date($date), userId: $userId})
              CREATE (c:Concern {
                text: $text,
                date: date($date),
                userId: $userId
              })
              MERGE (c)-[:RAISED_ON]->(d)
            `, { date: day.date, userId: USER_ID, text: concern });
          }
        }
      }

      // Create Trigger → Day links for identifiable stress events
      const triggers = [
        { date: '2026-02-08', name: 'family visit preparation', type: 'stress' },
        { date: '2026-02-09', name: 'sleep deprivation from cleaning', type: 'sleep' },
        { date: '2026-02-12', name: 'family departure loneliness', type: 'emotional' },
        { date: '2026-02-16', name: 'plumber disruption', type: 'stress' },
        { date: '2026-02-22', name: 'neurologist appointment', type: 'medical' },
        { date: '2026-02-22', name: 'new medication started', type: 'medication_change' },
      ];

      for (const trigger of triggers) {
        await tx.run(`
          MATCH (d:Day {date: date($date), userId: $userId})
          MERGE (t:Trigger {name: $name, type: $type, userId: $userId})
          MERGE (t)-[:TRIGGERED_ON]->(d)
        `, { date: trigger.date, userId: USER_ID, name: trigger.name, type: trigger.type });
      }
    });

    console.log('  ✅ Graph enriched with diary entries, activities, concerns, and triggers');
  } finally {
    await session.close();
  }
}

// ─── Main ────────────────────────────────────────────────────

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  Margaret\'s 30-Day Health Graph — Realistic Simulation      ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');

  process.env.NEO4J_URI = NEO4J_URI;
  process.env.NEO4J_USER = NEO4J_USER;
  process.env.NEO4J_PASSWORD = NEO4J_PASSWORD;

  const graphService = new GraphService();
  const driver = neo4j.driver(NEO4J_URI, neo4j.auth.basic(NEO4J_USER, NEO4J_PASSWORD));

  try {
    // Connect
    await graphService.connect();
    console.log('✅ Connected to Neo4j Aura\n');

    // Step 1: Ingest all check-ins
    console.log('📥 Ingesting 28 days of check-ins...');
    for (const day of JOURNAL) {
      const checkIn = journalToCheckIn(day);
      await graphService.ingestCheckIn(USER_ID, checkIn);
      await graphService.updateDayComposite(USER_ID, day.date);
      process.stdout.write('.');
    }
    console.log('\n  ✅ Check-ins ingested\n');

    // Step 2: Enrich with diary text, activities, concerns, triggers
    console.log('🎨 Enriching graph with context nodes...');
    await enrichGraph(driver);

    // Step 3: Run correlation engine
    console.log('\n📊 Running correlation engine...');
    const { graphService: gs } = await import('../src/services/graph.service.js');
    await gs.connect();
    const correlationService = new CorrelationService();
    const correlations = await correlationService.computeForUser(USER_ID);
    console.log(`  ✅ Found ${correlations.length} significant correlations:`);
    for (const c of correlations) {
      const arrow = c.correlation > 0 ? '↑↑' : '↑↓';
      const lagNote = c.lag > 0 ? ` (${c.lag}-day lag)` : '';
      console.log(`     ${arrow} ${c.nameA} ↔ ${c.nameB}: r=${c.correlation}${lagNote}`);
    }
    await gs.disconnect();

    // Step 4: Print summary stats
    const graphData = await graphService.getGraphData(USER_ID, '2026-02-01', '2026-02-28');
    console.log(`\n📈 Graph Summary:`);
    console.log(`   Days with data: ${graphData.length}`);
    console.log(`   Mood range: ${Math.min(...graphData.map(d => d.avgMood!).filter(Boolean))} - ${Math.max(...graphData.map(d => d.avgMood!).filter(Boolean))}`);
    console.log(`   Sleep range: ${Math.min(...graphData.map(d => d.avgSleep!).filter(Boolean))}h - ${Math.max(...graphData.map(d => d.avgSleep!).filter(Boolean))}h`);
    console.log(`   Worst day: ${graphData.reduce((a, b) => (a.overallScore ?? 99) < (b.overallScore ?? 99) ? a : b).date} (score: ${graphData.reduce((a, b) => (a.overallScore ?? 99) < (b.overallScore ?? 99) ? a : b).overallScore?.toFixed(1)})`);
    console.log(`   Best day: ${graphData.reduce((a, b) => (a.overallScore ?? 0) > (b.overallScore ?? 0) ? a : b).date} (score: ${graphData.reduce((a, b) => (a.overallScore ?? 0) > (b.overallScore ?? 0) ? a : b).overallScore?.toFixed(1)})`);

    // Step 5: Node count
    const session = driver.session();
    const countResult = await session.executeRead(async (tx) => {
      return tx.run(`
        MATCH (n {userId: $userId})
        WITH labels(n)[0] AS label, count(*) AS cnt
        RETURN label, cnt ORDER BY cnt DESC
      `, { userId: USER_ID });
    });
    console.log('\n🗂️  Node counts:');
    for (const record of countResult.records) {
      console.log(`   ${record.get('label')}: ${record.get('cnt').low}`);
    }
    await session.close();

    // Print visualization queries
    console.log('\n');
    console.log('╔══════════════════════════════════════════════════════════════╗');
    console.log('║  VISUALIZATION QUERIES                                      ║');
    console.log('║  Open Neo4j Aura → Query tab → paste these                  ║');
    console.log('╚══════════════════════════════════════════════════════════════╝');

    console.log(`
━━━ 1. FULL GRAPH OVERVIEW (everything) ━━━
MATCH (n {userId: '${USER_ID}'})
OPTIONAL MATCH (n)-[r]->(m {userId: '${USER_ID}'})
RETURN n, r, m
LIMIT 300

━━━ 2. TEMPORAL BACKBONE (Day chain + scores) ━━━
MATCH (d:Day {userId: '${USER_ID}'})-[:NEXT_DAY]->(d2:Day {userId: '${USER_ID}'})
RETURN d, d2
ORDER BY d.date

━━━ 3. WORST WEEK (Feb 8-12: stress event cascade) ━━━
MATCH (d:Day {userId: '${USER_ID}'})
WHERE d.date >= date('2026-02-08') AND d.date <= date('2026-02-12')
OPTIONAL MATCH (n)-[r]->(d)
OPTIONAL MATCH (d)<-[r2]-(n2)
RETURN d, n, r, n2, r2

━━━ 4. CORRELATIONS (MetricType nodes + CORRELATES_WITH edges) ━━━
MATCH (a:MetricType {userId: '${USER_ID}'})-[r:CORRELATES_WITH]->(b:MetricType {userId: '${USER_ID}'})
RETURN a, r, b

━━━ 5. MEDICATION TIMELINE (all doses, colored by status) ━━━
MATCH (md:MedicationDose)-[:ON_DAY]->(d:Day {userId: '${USER_ID}'})
RETURN md.medicationName AS med, d.date AS date, md.status AS status, md.delayMinutes AS delay
ORDER BY d.date, md.medicationName

━━━ 6. SYMPTOM PATTERNS (tremor + triggers) ━━━
MATCH (s:Symptom)-[:ON_DAY]->(d:Day {userId: '${USER_ID}'})
OPTIONAL MATCH (t:Trigger)-[:TRIGGERED_ON]->(d)
RETURN d, s, t
ORDER BY d.date

━━━ 7. CONCERNS RAISED (patient-reported) ━━━
MATCH (c:Concern)-[:RAISED_ON]->(d:Day {userId: '${USER_ID}'})
RETURN d.date AS date, c.text AS concern
ORDER BY d.date

━━━ 8. SLEEP → TREMOR NEXT-DAY PATTERN ━━━
MATCH (d1:Day {userId: '${USER_ID}'})-[:NEXT_DAY]->(d2:Day {userId: '${USER_ID}'})
OPTIONAL MATCH (sl:SleepEntry)-[:ON_DAY]->(d1)
OPTIONAL MATCH (sy:Symptom {type: 'tremor'})-[:ON_DAY]->(d2)
RETURN d1.date AS sleepDay, sl.hours AS sleepHours, sl.quality AS sleepQuality,
       d2.date AS nextDay, sy.severity AS nextDayTremor
ORDER BY d1.date

━━━ 9. ACTIVITY IMPACT (days with walking vs without) ━━━
MATCH (d:Day {userId: '${USER_ID}'})
OPTIONAL MATCH (ae:ActivityEvent)-[:ON_DAY]->(d)
OPTIONAL MATCH (ae)-[:OF_TYPE]->(a:Activity {name: 'walking'})
OPTIONAL MATCH (me:MoodEntry)-[:ON_DAY]->(d)
OPTIONAL MATCH (sy:Symptom {type: 'tremor'})-[:ON_DAY]->(d)
RETURN d.date AS date,
       CASE WHEN a IS NOT NULL THEN 'walked' ELSE 'no walk' END AS walked,
       me.score AS mood, sy.severity AS tremor
ORDER BY d.date

━━━ 10. DIARY ENTRIES (Margaret's own words) ━━━
MATCH (diary:DiaryEntry)-[:RECORDED_ON]->(d:Day {userId: '${USER_ID}'})
RETURN d.date AS date, diary.text AS entry
ORDER BY d.date
`);

    console.log('\n✅ SIMULATION COMPLETE');
    console.log('   Graph is live in Neo4j Aura — go explore!');
    console.log('   Data will persist until you delete it.\n');

  } catch (err) {
    console.error('\n❌ ERROR:', err);
    process.exit(1);
  } finally {
    await graphService.disconnect();
    await driver.close();
  }
}

main();
