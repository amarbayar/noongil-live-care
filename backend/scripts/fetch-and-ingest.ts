import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp();
const db = getFirestore();
const uid = 'LqpiaTQgWjdHwcvqMsMoFqVbt5c2';

// Fetch latest check-in from Firestore
const snap = await db.collection('users').doc(uid).collection('checkins')
  .orderBy('createdAt', 'desc').limit(3).get();

if (snap.empty) {
  console.log('No check-ins found');
  process.exit(1);
}

for (const doc of snap.docs) {
  const d = doc.data();
  const completedAt = d.completedAt?.toDate?.()?.toISOString() ?? new Date().toISOString();

  const payload = {
    eventId: `manual-ingest-${doc.id}`,
    userId: uid,
    checkIn: {
      id: doc.id,
      userId: uid,
      type: d.type ?? 'adhoc',
      completedAt,
      completionStatus: d.completionStatus ?? 'completed',
      durationSeconds: d.durationSeconds,
      mood: d.mood ? { score: d.mood.score, description: d.mood.label } : undefined,
      sleep: d.sleep ? { hours: d.sleep.hours, quality: d.sleep.quality } : undefined,
      symptoms: d.symptoms?.map((s: any) => ({ type: s.type, severity: s.severity })),
      medicationAdherence: d.medicationAdherence?.map((m: any) => ({
        medicationName: m.medicationName,
        status: m.status,
      })),
    },
  };

  console.log(`Ingesting ${doc.id} (${completedAt.split('T')[0]})...`);

  const res = await fetch('http://localhost:8090/api/graph/ingest', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const body = await res.json();
  console.log(`  → ${res.status}:`, JSON.stringify(body));
}

console.log('\nDone. Check dashboard with userId:', uid);
