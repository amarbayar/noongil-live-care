import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../lib/auth.js';
import { getDb } from '../services/firebase.js';
import { graphService } from '../services/graph.service.js';
import { getAuth } from 'firebase-admin/auth';

export async function userRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('preHandler', requireAuth);

  // Cascading account deletion
  fastify.delete('/api/users/me', async (request, reply) => {
    const userId = request.userId!;
    const db = getDb();

    // 1. Delete all Firestore user data
    const userDoc = db.collection('users').doc(userId);
    await db.recursiveDelete(userDoc);

    // 2. Delete Neo4j graph data
    try {
      await graphService.deleteUserData(userId);
    } catch (err) {
      request.log.warn({ err, userId }, 'Neo4j deletion failed (may not be connected)');
    }

    // 3. Delete Firebase Auth account
    try {
      await getAuth().deleteUser(userId);
    } catch (err) {
      request.log.warn({ err, userId }, 'Firebase Auth deletion failed');
    }

    return { status: 'deleted' };
  });

  // Data export
  fastify.get('/api/users/me/export', async (request, reply) => {
    const userId = request.userId!;
    const db = getDb();

    // Collect all user data from Firestore
    const userDoc = db.collection('users').doc(userId);
    const profileSnap = await userDoc.get();
    const profile = profileSnap.exists ? profileSnap.data() : null;

    // Sub-collections
    const collections = ['checkins', 'medications', 'memory', 'caregiver_relationships', 'fcm_tokens'];
    const data: Record<string, any[]> = {};

    for (const col of collections) {
      const snap = await userDoc.collection(col).get();
      data[col] = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    }

    return {
      userId,
      profile,
      ...data,
      exportedAt: new Date().toISOString(),
    };
  });
}
