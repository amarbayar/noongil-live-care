import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import crypto from 'node:crypto';
import { getDb } from '../services/firebase.js';
import { requireAuth } from '../lib/auth.js';
import { getRelationship, ALL_PERMISSIONS } from '../lib/caregiver-auth.js';
import { sendCaregiverInvitationEmail } from '../services/mailer.service.js';

const AddReminderBody = z.object({
  title: z.string().min(1),
  note: z.string().optional(),
  schedule: z.array(z.string().regex(/^\d{2}:\d{2}$/)),
  isEnabled: z.boolean().default(true),
});

const UpdateReminderBody = AddReminderBody.partial();

const CreateVoiceMessageBody = z.object({
  audioBase64: z.string().min(1),
  mimeType: z.string().default('audio/wav'),
  durationSeconds: z.number().positive().max(30),
  transcript: z.string().optional(),
});

const CreateInvitationBody = z.object({
  caregiverEmail: z.string().email(),
  permissions: z.array(z.enum(['medications', 'reminders', 'schedule', 'wellness'])).min(1),
});

type CaregiverInvitationRecord = {
  caregiverEmail: string;
  memberName?: string | null;
  permissions: Array<'medications' | 'reminders' | 'schedule' | 'wellness'>;
  status: 'pending' | 'accepted' | 'revoked' | 'expired' | 'email_failed';
  expiresAt: string;
};

function normalizeBaseUrl(url: string): string {
  return url.trim().replace(/\/+$/, '');
}

function getDashboardBaseUrl(request: { headers: Record<string, unknown>; protocol: string }): string | null {
  const explicit = process.env.PUBLIC_DASHBOARD_URL?.trim();
  if (explicit) {
    return normalizeBaseUrl(explicit);
  }

  const forwardedProto = request.headers['x-forwarded-proto'];
  const forwardedHost = request.headers['x-forwarded-host'];
  const proto = Array.isArray(forwardedProto) ? forwardedProto[0] : forwardedProto;
  const host = Array.isArray(forwardedHost) ? forwardedHost[0] : (forwardedHost ?? request.headers.host);

  if (typeof host !== 'string' || host.length === 0) {
    return null;
  }

  const scheme = typeof proto === 'string' && proto.length > 0 ? proto : request.protocol;
  return `${scheme}://${host}`;
}

async function getInvitationRefByToken(db: ReturnType<typeof getDb>, token: string) {
  const lookupDoc = await db.collection('caregiver_invitation_tokens').doc(token).get();
  if (!lookupDoc.exists) {
    return null;
  }

  const lookup = lookupDoc.data() as { memberId?: string; invitationId?: string } | undefined;
  if (!lookup?.memberId || !lookup.invitationId) {
    return null;
  }

  return db
    .collection('users')
    .doc(lookup.memberId)
    .collection('caregiver_invitations')
    .doc(lookup.invitationId);
}

export async function caregiverRoutes(fastify: FastifyInstance): Promise<void> {
  // All routes require auth
  fastify.addHook('preHandler', requireAuth);

  // --- List active caregivers linked to this member ---
  fastify.get('/api/caregiver/relationships', async (request, _reply) => {
    const memberId = request.userId!;
    const db = getDb();

    const snap = await db
      .collection('users')
      .doc(memberId)
      .collection('caregiver_relationships')
      .where('status', '==', 'active')
      .get();

    const relationships = snap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    return { relationships };
  });

  // --- List members this caregiver is linked to ---
  fastify.get('/api/caregiver/members', async (request, reply) => {
    const caregiverId = request.userId!;
    const db = getDb();

    const snap = await db
      .collection('caregiver_member_links')
      .where('caregiverId', '==', caregiverId)
      .get();

    const members = snap.docs
      .map((doc) => doc.data())
      .filter((data) => data.status === 'active')
      .map((data) => {
        return {
          memberId: data.memberId as string,
          memberName: data.memberName as string | undefined,
          role: data.role as string,
          linkedAt: data.linkedAt,
        };
      });

    return { members };
  });

  // --- Get member's reminders (meds + check-in schedule + custom) ---
  fastify.get<{ Params: { memberId: string } }>(
    '/api/caregiver/members/:memberId/reminders',
    async (request, reply) => {
      const caregiverId = request.userId!;
      const { memberId } = request.params;

      const rel = await getRelationship(caregiverId, memberId);
      if (!rel.exists) {
        return reply.status(403).send({ error: 'No active caregiver relationship' });
      }

      const db = getDb();
      const userRef = db.collection('users').doc(memberId);
      const perms = rel.permissions;

      // Fetch only collections the caregiver has permission for
      const [medsSnap, remindersSnap, scheduleDoc] = await Promise.all([
        perms.includes('medications')
          ? userRef.collection('medications').where('isActive', '==', true).get()
          : Promise.resolve({ docs: [] }),
        perms.includes('reminders')
          ? userRef.collection('reminders').get()
          : Promise.resolve({ docs: [] }),
        perms.includes('schedule')
          ? userRef.collection('profile').doc('checkInSchedule').get()
          : Promise.resolve({ exists: false, data: () => null }),
      ]);

      const medications = (medsSnap as any).docs.map((doc: any) => ({
        id: doc.id,
        ...doc.data(),
        type: 'medication' as const,
      }));

      const customReminders = (remindersSnap as any).docs.map((doc: any) => ({
        id: doc.id,
        ...doc.data(),
        type: 'custom' as const,
      }));

      const checkInSchedule = (scheduleDoc as any).exists ? (scheduleDoc as any).data() : null;

      return { medications, customReminders, checkInSchedule };
    }
  );

  // --- Add a custom reminder for a member ---
  fastify.post<{ Params: { memberId: string } }>(
    '/api/caregiver/members/:memberId/reminders',
    async (request, reply) => {
      const caregiverId = request.userId!;
      const { memberId } = request.params;

      const rel = await getRelationship(caregiverId, memberId);
      if (!rel.exists) {
        return reply.status(403).send({ error: 'No active caregiver relationship' });
      }
      if (!rel.permissions.includes('reminders')) {
        return reply.status(403).send({ error: 'No permission to manage reminders' });
      }

      const parsed = AddReminderBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: parsed.error.flatten() });
      }

      const db = getDb();
      const reminder = {
        userId: memberId,
        title: parsed.data.title,
        note: parsed.data.note ?? null,
        schedule: parsed.data.schedule,
        isEnabled: parsed.data.isEnabled,
        createdBy: {
          userId: caregiverId,
          name: null,
          role: 'caregiver',
        },
        createdAt: new Date().toISOString(),
      };

      const docRef = await db
        .collection('users')
        .doc(memberId)
        .collection('reminders')
        .add(reminder);

      return reply.status(201).send({ id: docRef.id, ...reminder });
    }
  );

  // --- Update a custom reminder ---
  fastify.put<{ Params: { memberId: string; id: string } }>(
    '/api/caregiver/members/:memberId/reminders/:id',
    async (request, reply) => {
      const caregiverId = request.userId!;
      const { memberId, id } = request.params;

      const rel = await getRelationship(caregiverId, memberId);
      if (!rel.exists) {
        return reply.status(403).send({ error: 'No active caregiver relationship' });
      }
      if (!rel.permissions.includes('reminders')) {
        return reply.status(403).send({ error: 'No permission to manage reminders' });
      }

      const parsed = UpdateReminderBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: parsed.error.flatten() });
      }

      const db = getDb();
      const docRef = db.collection('users').doc(memberId).collection('reminders').doc(id);
      const doc = await docRef.get();

      if (!doc.exists) {
        return reply.status(404).send({ error: 'Reminder not found' });
      }

      await docRef.update(parsed.data);
      return { id, ...doc.data(), ...parsed.data };
    }
  );

  // --- Delete a custom reminder ---
  fastify.delete<{ Params: { memberId: string; id: string } }>(
    '/api/caregiver/members/:memberId/reminders/:id',
    async (request, reply) => {
      const caregiverId = request.userId!;
      const { memberId, id } = request.params;

      const rel = await getRelationship(caregiverId, memberId);
      if (!rel.exists) {
        return reply.status(403).send({ error: 'No active caregiver relationship' });
      }
      if (!rel.permissions.includes('reminders')) {
        return reply.status(403).send({ error: 'No permission to manage reminders' });
      }

      const db = getDb();
      await db.collection('users').doc(memberId).collection('reminders').doc(id).delete();
      return { status: 'deleted' };
    }
  );

  // --- Create a caregiver voice message for a member ---
  fastify.post<{ Params: { memberId: string } }>(
    '/api/caregiver/members/:memberId/voice-messages',
    async (request, reply) => {
      const caregiverId = request.userId!;
      const { memberId } = request.params;

      const rel = await getRelationship(caregiverId, memberId);
      if (!rel.exists) {
        return reply.status(403).send({ error: 'No active caregiver relationship' });
      }

      const parsed = CreateVoiceMessageBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: parsed.error.flatten() });
      }

      const db = getDb();
      const message = {
        caregiverId,
        caregiverName: request.userName?.trim()
          || request.userEmail?.split('@')[0]?.trim()
          || null,
        audioBase64: parsed.data.audioBase64,
        mimeType: parsed.data.mimeType,
        durationSeconds: parsed.data.durationSeconds,
        transcript: parsed.data.transcript ?? null,
        status: 'unread',
        createdAt: new Date().toISOString(),
      };

      const docRef = await db
        .collection('users')
        .doc(memberId)
        .collection('voice_messages')
        .add(message);

      return reply.status(201).send({ id: docRef.id, ...message });
    }
  );

  // --- Create an invitation (member invites caregiver by email) ---
  fastify.post('/api/caregiver/invitations', async (request, reply) => {
    const memberId = request.userId!;
    const memberName = request.userName?.trim()
      || request.userEmail?.split('@')[0]?.trim()
      || null;
    const dashboardBaseUrl = getDashboardBaseUrl(request);

    const parsed = CreateInvitationBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: parsed.error.flatten() });
    }

    const db = getDb();
    const invitation = {
      caregiverEmail: parsed.data.caregiverEmail.toLowerCase(),
      memberName,
      permissions: parsed.data.permissions,
      status: 'pending' as const,
      token: crypto.randomUUID(),
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    };

    const docRef = await db
      .collection('users')
      .doc(memberId)
      .collection('caregiver_invitations')
      .add(invitation);

    await db
      .collection('caregiver_invitation_tokens')
      .doc(invitation.token)
      .set({
        memberId,
        invitationId: docRef.id,
        createdAt: invitation.createdAt,
        expiresAt: invitation.expiresAt,
      });

    try {
      const delivery = await sendCaregiverInvitationEmail({
        caregiverEmail: invitation.caregiverEmail,
        memberId,
        memberName,
        permissions: invitation.permissions,
        invitationToken: invitation.token,
        expiresAt: invitation.expiresAt,
        dashboardBaseUrl,
      });

      return reply.status(201).send({
        id: docRef.id,
        ...invitation,
        inviteUrl: delivery.inviteUrl,
        emailDeliveryStatus: delivery.status,
      });
    } catch (error) {
      await docRef.update({
        status: 'email_failed',
        emailErrorAt: new Date().toISOString(),
      });
      request.log.error({ error, memberId }, 'Failed to send caregiver invitation email');
      return reply.status(502).send({
        error: 'Failed to send caregiver invitation email. Please try again.',
      });
    }
  });

  // --- List invitations for this member ---
  fastify.get('/api/caregiver/invitations', async (request, _reply) => {
    const memberId = request.userId!;
    const db = getDb();

    const snap = await db
      .collection('users')
      .doc(memberId)
      .collection('caregiver_invitations')
      .where('status', 'in', ['pending', 'accepted'])
      .get();

    const invitations = snap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    return { invitations };
  });

  // --- Revoke an invitation ---
  fastify.delete<{ Params: { id: string } }>(
    '/api/caregiver/invitations/:id',
    async (request, reply) => {
      const memberId = request.userId!;
      const { id } = request.params;
      const db = getDb();

      const docRef = db
        .collection('users')
        .doc(memberId)
        .collection('caregiver_invitations')
        .doc(id);

      const doc = await docRef.get();
      if (!doc.exists) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }

      await docRef.update({ status: 'revoked' });
      return { status: 'revoked' };
    }
  );

  // --- View invitation details by token (caregiver) ---
  fastify.get<{ Params: { token: string } }>(
    '/api/caregiver/invitation/:token',
    async (request, reply) => {
      const db = getDb();
      const { token } = request.params;

      const invitationRef = await getInvitationRefByToken(db, token);
      if (!invitationRef) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }
      const doc = await invitationRef.get();
      if (!doc.exists) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }
      const data = doc.data() as CaregiverInvitationRecord | undefined;
      if (!data) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }

      return {
        id: doc.id,
        caregiverEmail: data.caregiverEmail,
        permissions: data.permissions,
        status: data.status,
        expiresAt: data.expiresAt,
      };
    }
  );

  // --- Accept invitation (caregiver) ---
  fastify.post<{ Params: { token: string } }>(
    '/api/caregiver/invitation/:token/accept',
    async (request, reply) => {
      const caregiverId = request.userId!;
      const caregiverEmail = request.userEmail?.toLowerCase();
      const { token } = request.params;

      const db = getDb();

      const invitationRef = await getInvitationRefByToken(db, token);
      if (!invitationRef) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }
      const doc = await invitationRef.get();
      if (!doc.exists) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }
      const data = doc.data() as CaregiverInvitationRecord | undefined;
      if (!data) {
        return reply.status(404).send({ error: 'Invitation not found' });
      }

      // Check status
      if (data.status !== 'pending') {
        return reply.status(400).send({ error: `Invitation is ${data.status}` });
      }

      // Check expiry
      if (new Date(data.expiresAt) < new Date()) {
        await doc.ref.update({ status: 'expired' });
        return reply.status(400).send({ error: 'Invitation has expired' });
      }

      // Verify email matches
      if (caregiverEmail !== data.caregiverEmail) {
        return reply.status(403).send({
          error: 'Email mismatch: this invitation was sent to a different email address',
        });
      }

      // Extract memberId from the doc path: users/{memberId}/caregiver_invitations/{docId}
      const memberId = doc.ref.parent.parent!.id;

      // Create caregiver_relationship
      const relationship = {
        memberId,
        caregiverId,
        memberName: data.memberName ?? null,
        caregiverName: request.userName?.trim()
          || request.userEmail?.split('@')[0]?.trim()
          || null,
        role: 'primary',
        status: 'active',
        permissions: data.permissions,
        linkedAt: new Date().toISOString(),
      };

      await db
        .collection('users')
        .doc(memberId)
        .collection('caregiver_relationships')
        .add(relationship);

      await db
        .collection('caregiver_member_links')
        .doc(`${caregiverId}_${memberId}`)
        .set(relationship);

      // Update invitation status
      await doc.ref.update({
        status: 'accepted',
        acceptedAt: new Date().toISOString(),
        acceptedBy: caregiverId,
      });

      return { status: 'accepted', memberId };
    }
  );
}
