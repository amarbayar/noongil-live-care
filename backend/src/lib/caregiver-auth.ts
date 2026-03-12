import type { FastifyRequest, FastifyReply } from 'fastify';
import { getDb } from '../services/firebase.js';

export const ALL_PERMISSIONS = ['medications', 'reminders', 'schedule', 'wellness'];

export interface RelationshipInfo {
  exists: boolean;
  permissions: string[];
}

export async function getRelationship(
  caregiverId: string,
  memberId: string
): Promise<RelationshipInfo> {
  const db = getDb();
  const snap = await db
    .collection('users')
    .doc(memberId)
    .collection('caregiver_relationships')
    .where('caregiverId', '==', caregiverId)
    .where('status', '==', 'active')
    .limit(1)
    .get();

  if (snap.empty) {
    return { exists: false, permissions: [] };
  }

  const data = snap.docs[0].data();
  const permissions = (data.permissions as string[] | undefined) ?? ALL_PERMISSIONS;
  return { exists: true, permissions };
}

/**
 * Checks if the authed user either IS the member or has an active caregiver
 * relationship with the 'wellness' permission. Sends 403 if not.
 * Returns the caregiver's permissions array if access is granted,
 * or null if denied (reply already sent). Self-access returns ALL_PERMISSIONS.
 */
export async function requireWellnessAccess(
  request: FastifyRequest,
  reply: FastifyReply,
  memberId: string
): Promise<string[] | null> {
  const authUserId = request.userId!;

  // Self-access: user viewing their own data — all permissions
  if (authUserId === memberId) {
    return [...ALL_PERMISSIONS];
  }

  // Caregiver access: check for active relationship with wellness permission
  const rel = await getRelationship(authUserId, memberId);
  if (!rel.exists) {
    reply.status(403).send({ error: 'No active caregiver relationship' });
    return null;
  }

  if (!rel.permissions.includes('wellness')) {
    reply.status(403).send({ error: 'Missing wellness permission' });
    return null;
  }

  return rel.permissions;
}
