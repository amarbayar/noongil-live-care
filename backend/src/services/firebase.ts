import { initializeApp, cert, getApps, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

let app: App | undefined;
let db: Firestore | undefined;

export function initFirebase(): void {
  if (getApps().length > 0) return;

  // Uses Application Default Credentials (ADC) in production (Cloud Run)
  // and GOOGLE_APPLICATION_CREDENTIALS env var in dev
  app = initializeApp();
  db = getFirestore(app);
}

export function getDb(): Firestore {
  if (!db) {
    throw new Error('Firebase not initialized. Call initFirebase() first.');
  }
  return db;
}
