import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp();
const db = getFirestore();
const uid = 'LqpiaTQgWjdHwcvqMsMoFqVbt5c2';

const collections = ['checkins', 'medications', 'customReminders', 'companion_sessions', 'companion_outbox'];

for (const col of collections) {
  const snap = await db.collection('users').doc(uid).collection(col).get();
  console.log(`\n${col}: ${snap.size} docs`);
  for (const doc of snap.docs) {
    const d = doc.data();
    const startedAt = d.startedAt?.toDate?.()?.toISOString?.()?.split('T')[0] ?? '';
    const completedAt = d.completedAt?.toDate?.()?.toISOString?.()?.split('T')[0] ?? '';
    const dateStr = startedAt || completedAt || '';
    const summary = d.aiSummary || d.type || '';
    console.log(`  ${doc.id} ${dateStr ? '(' + dateStr + ')' : ''} ${summary}`);
  }
}
