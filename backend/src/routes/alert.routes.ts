import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import crypto from 'node:crypto';
import { getDb } from '../services/firebase.js';
import { getMessaging } from 'firebase-admin/messaging';

// PagerDuty webhook v3 payload (simplified to what we need)
const PagerDutyEvent = z.object({
  event: z.object({
    event_type: z.string(),
    data: z.object({
      id: z.string(),
      title: z.string(),
      urgency: z.string().optional(),
      custom_details: z.record(z.unknown()).optional(),
    }),
  }),
});

const WebhookBody = z.object({
  messages: z.array(PagerDutyEvent).min(1),
});

export async function alertRoutes(fastify: FastifyInstance): Promise<void> {
  // PagerDuty → FCM webhook
  fastify.post('/api/alerts/webhook', {
    config: { rawBody: true },
  }, async (request, reply) => {
    // Verify PagerDuty webhook signature
    const webhookSecret = process.env.PAGERDUTY_WEBHOOK_SECRET;
    if (webhookSecret) {
      const signature = request.headers['x-pagerduty-signature'] as string | undefined;
      if (!signature) {
        return reply.status(401).send({ error: 'Missing webhook signature' });
      }

      const rawBody = typeof request.body === 'string'
        ? request.body
        : JSON.stringify(request.body);
      const expectedSig = 'v1=' + crypto
        .createHmac('sha256', webhookSecret)
        .update(rawBody)
        .digest('hex');

      const sigBuffer = Buffer.from(signature);
      const expectedBuffer = Buffer.from(expectedSig);
      if (sigBuffer.length !== expectedBuffer.length || !crypto.timingSafeEqual(sigBuffer, expectedBuffer)) {
        return reply.status(401).send({ error: 'Invalid webhook signature' });
      }
    }

    const parsed = WebhookBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: parsed.error.flatten() });
    }

    const results: Array<{ incidentId: string; notified: number }> = [];

    for (const msg of parsed.data.messages) {
      const { event_type, data } = msg.event;

      // Only act on triggered incidents
      if (event_type !== 'incident.triggered') continue;

      const userId = extractUserId(data.custom_details);
      if (!userId) {
        fastify.log.warn({ incidentId: data.id }, 'No userId in PagerDuty incident custom_details');
        continue;
      }

      // Look up caregivers for this user
      const caregiverTokens = await getCaregiverFcmTokens(userId);
      if (caregiverTokens.length === 0) {
        fastify.log.info({ userId, incidentId: data.id }, 'No caregiver FCM tokens found');
        results.push({ incidentId: data.id, notified: 0 });
        continue;
      }

      // Send FCM push to all caregivers
      const notified = await sendCaregiverNotifications(
        caregiverTokens,
        data.title,
        userId
      );

      results.push({ incidentId: data.id, notified });
      fastify.log.info({ userId, incidentId: data.id, notified }, 'Caregiver alerts sent');
    }

    return { status: 'ok', results };
  });
}

function extractUserId(customDetails: Record<string, unknown> | undefined): string | null {
  if (!customDetails) return null;
  const userId = customDetails.user_id ?? customDetails.userId;
  return typeof userId === 'string' ? userId : null;
}

async function getCaregiverFcmTokens(memberId: string): Promise<string[]> {
  const db = getDb();
  const snap = await db.collectionGroup('caregiver_relationships')
    .where('memberId', '==', memberId)
    .where('status', '==', 'active')
    .get();

  const caregiverIds = snap.docs.map((doc) => doc.data().caregiverId as string);
  if (caregiverIds.length === 0) return [];

  // Get FCM tokens for each caregiver
  const tokens: string[] = [];
  for (const caregiverId of caregiverIds) {
    const tokenSnap = await db.collection('users').doc(caregiverId)
      .collection('fcm_tokens').get();
    for (const doc of tokenSnap.docs) {
      const token = doc.data().token;
      if (typeof token === 'string') tokens.push(token);
    }
  }

  return tokens;
}

async function sendCaregiverNotifications(
  tokens: string[],
  alertTitle: string,
  memberId: string
): Promise<number> {
  if (tokens.length === 0) return 0;

  const messaging = getMessaging();
  const message = {
    notification: {
      title: 'Health Alert',
      // Generic body — no health details on lock screen
      body: 'Someone you care for may need your attention.',
    },
    data: {
      type: 'health_alert',
      memberId,
      // Health details in data payload only (not shown on lock screen)
      alertDetail: alertTitle,
    },
    tokens,
  };

  const result = await messaging.sendEachForMulticast(message);
  return result.successCount;
}
