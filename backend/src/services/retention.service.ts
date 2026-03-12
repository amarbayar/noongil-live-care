import { getDb } from './firebase.js';
import { graphService } from './graph.service.js';

// Retention periods in days
export const RETENTION_POLICIES = {
  checkins: 365,             // 1 year
  medication_adherence: 365, // 1 year
  memory: 365,               // 1 year
  checkin_sessions: 90,      // 90 days
  invite_codes: 30,          // 30 days
  medications_deactivated: 365, // 1 year after deactivation
  caregiver_revoked: 90,     // 90 days after revocation
  graph: 730,                // 2 years
} as const;

export interface CleanupResult {
  collection: string;
  deletedCount: number;
}

export async function runCleanup(): Promise<CleanupResult[]> {
  const results: CleanupResult[] = [];
  const db = getDb();

  // Get all user IDs
  const usersSnap = await db.collection('users').listDocuments();

  for (const userRef of usersSnap) {
    const userId = userRef.id;

    // 1. Checkins older than 1 year
    results.push(await deleteOldDocs(
      db, userId, 'checkins', 'createdAt', RETENTION_POLICIES.checkins
    ));

    // 2. Medication adherence older than 1 year
    results.push(await deleteOldDocs(
      db, userId, 'medication_adherence', 'timestamp', RETENTION_POLICIES.medication_adherence
    ));

    // 3. Memory older than 1 year
    results.push(await deleteOldDocs(
      db, userId, 'memory', 'createdAt', RETENTION_POLICIES.memory
    ));

    // 4. Check-in sessions older than 90 days
    results.push(await deleteOldDocs(
      db, userId, 'checkin_sessions', 'startedAt', RETENTION_POLICIES.checkin_sessions
    ));

    // 5. Invite codes older than 30 days
    results.push(await deleteOldDocs(
      db, userId, 'invite_codes', 'createdAt', RETENTION_POLICIES.invite_codes
    ));

    // 6. Deactivated medications: delete if deactivated for > 1 year
    results.push(await deleteDeactivatedMedications(db, userId));

    // 7. Revoked caregiver relationships: delete if revoked for > 90 days
    results.push(await deleteRevokedRelationships(db, userId));
  }

  // 8. Graph data older than 2 years (Neo4j)
  try {
    const graphCutoff = daysAgo(RETENTION_POLICIES.graph);
    const graphCutoffStr = graphCutoff.toISOString().split('T')[0];
    const graphDeleted = await graphService.deleteOldGraphData(graphCutoffStr);
    results.push({ collection: 'neo4j_graph', deletedCount: graphDeleted });
  } catch {
    // Neo4j may not be connected — skip graph cleanup
    results.push({ collection: 'neo4j_graph', deletedCount: 0 });
  }

  return results.filter(r => r.deletedCount > 0);
}

async function deleteOldDocs(
  db: FirebaseFirestore.Firestore,
  userId: string,
  collection: string,
  dateField: string,
  retentionDays: number
): Promise<CleanupResult> {
  const cutoff = daysAgo(retentionDays);
  const snap = await db
    .collection('users')
    .doc(userId)
    .collection(collection)
    .where(dateField, '<', cutoff)
    .limit(500)
    .get();

  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
  }
  if (!snap.empty) {
    await batch.commit();
  }

  return { collection: `${userId}/${collection}`, deletedCount: snap.size };
}

async function deleteDeactivatedMedications(
  db: FirebaseFirestore.Firestore,
  userId: string
): Promise<CleanupResult> {
  const cutoff = daysAgo(RETENTION_POLICIES.medications_deactivated);
  // Only delete inactive medications that have been deactivated long enough
  // Medications without deactivatedAt are skipped (still active or legacy)
  const snap = await db
    .collection('users')
    .doc(userId)
    .collection('medications')
    .where('isActive', '==', false)
    .limit(500)
    .get();

  const batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    // Check deactivatedAt if it exists, otherwise use createdAt as fallback
    const deactivatedAt = data.deactivatedAt?.toDate?.() ?? data.createdAt?.toDate?.();
    if (deactivatedAt && deactivatedAt < cutoff) {
      batch.delete(doc.ref);
      count++;
    }
  }
  if (count > 0) {
    await batch.commit();
  }

  return { collection: `${userId}/medications`, deletedCount: count };
}

async function deleteRevokedRelationships(
  db: FirebaseFirestore.Firestore,
  userId: string
): Promise<CleanupResult> {
  const cutoff = daysAgo(RETENTION_POLICIES.caregiver_revoked);
  const snap = await db
    .collection('users')
    .doc(userId)
    .collection('caregiver_relationships')
    .where('status', '==', 'revoked')
    .limit(500)
    .get();

  const batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const revokedAt = data.revokedAt?.toDate?.();
    if (revokedAt && revokedAt < cutoff) {
      batch.delete(doc.ref);
      count++;
    }
  }
  if (count > 0) {
    await batch.commit();
  }

  return { collection: `${userId}/caregiver_relationships`, deletedCount: count };
}

function daysAgo(days: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d;
}
