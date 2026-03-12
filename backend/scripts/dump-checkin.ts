import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

if (getApps().length === 0) initializeApp();
const db = getFirestore();
const userId = 'LqpiaTQgWjdHwcvqMsMoFqVbt5c2';

async function main() {
  const snap = await db.collection('users').doc(userId).collection('checkins').limit(1).get();
  if (snap.empty) {
    console.log('No documents found');
    return;
  }
  const doc = snap.docs[0];
  console.log('Document ID:', doc.id);
  console.log('Full data:', JSON.stringify(doc.data(), (key, value) => {
    // Handle Firestore Timestamps
    if (value && typeof value === 'object' && value._seconds !== undefined) {
      return `Timestamp(${new Date(value._seconds * 1000).toISOString()})`;
    }
    return value;
  }, 2));
}

main().catch(console.error);
