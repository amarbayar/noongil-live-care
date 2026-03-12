import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

if (getApps().length === 0) initializeApp();
const db = getFirestore();
const userId = 'LqpiaTQgWjdHwcvqMsMoFqVbt5c2';

async function main() {
  const snap = await db.collection('users').doc(userId).collection('checkins').get();
  console.log('Documents found:', snap.size);
  for (const doc of snap.docs) {
    const d = doc.data();
    const date = d.startedAt?.toDate?.()?.toISOString?.() ?? 'no-date';
    console.log(`  ${doc.id}  ${d.type?.padEnd(7)}  ${date}  mood=${d.mood?.score}  status=${d.completionStatus}`);
  }
}

main().catch(console.error);
