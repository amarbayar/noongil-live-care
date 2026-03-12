import { describe, it, expect, vi, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import crypto from 'node:crypto';

// Mock firebase
const { mockCollectionGroup, mockCollection } = vi.hoisted(() => ({
  mockCollectionGroup: vi.fn(),
  mockCollection: vi.fn(),
}));

vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(() => ({
    collectionGroup: mockCollectionGroup,
    collection: mockCollection,
  })),
}));

// Mock firebase-admin/messaging
const { mockSendEachForMulticast } = vi.hoisted(() => ({
  mockSendEachForMulticast: vi.fn().mockResolvedValue({ successCount: 1, failureCount: 0 }),
}));

vi.mock('firebase-admin/messaging', () => ({
  getMessaging: vi.fn(() => ({
    sendEachForMulticast: mockSendEachForMulticast,
  })),
}));

import { alertRoutes } from '../src/routes/alert.routes.js';

describe('Alert Routes', () => {
  let fastify: FastifyInstance;

  beforeAll(async () => {
    fastify = Fastify();
    await fastify.register(alertRoutes);
    await fastify.ready();
  });

  afterAll(async () => {
    await fastify.close();
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    delete process.env.PAGERDUTY_WEBHOOK_SECRET;
  });

  const makeWebhookPayload = (userId: string | null = 'user1') => ({
    messages: [{
      event: {
        event_type: 'incident.triggered',
        data: {
          id: 'inc-001',
          title: 'Symptom spike: tremor severity 5/5',
          urgency: 'high',
          custom_details: userId ? { user_id: userId } : {},
        },
      },
    }],
  });

  function signPayload(payload: unknown, secret: string): string {
    const body = JSON.stringify(payload);
    return 'v1=' + crypto.createHmac('sha256', secret).update(body).digest('hex');
  }

  function setupMocks(caregiverIds: string[] = ['caregiver1'], tokens: string[] = ['fcm-token-1']) {
    // Mock collectionGroup for caregiver_relationships
    mockCollectionGroup.mockReturnValue({
      where: vi.fn().mockReturnValue({
        where: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue({
            docs: caregiverIds.map(id => ({
              data: () => ({ caregiverId: id, memberId: 'user1', status: 'active' }),
            })),
          }),
        }),
      }),
    });

    // Mock collection for FCM tokens
    mockCollection.mockReturnValue({
      doc: vi.fn().mockReturnValue({
        collection: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue({
            docs: tokens.map(t => ({ data: () => ({ token: t }) })),
          }),
        }),
      }),
    });
  }

  // MARK: - Signature Verification

  describe('Webhook signature verification', () => {
    it('returns 401 when secret is set but signature is missing', async () => {
      process.env.PAGERDUTY_WEBHOOK_SECRET = 'test-secret';

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: makeWebhookPayload('user1'),
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.body).error).toBe('Missing webhook signature');
    });

    it('returns 401 when signature is invalid', async () => {
      process.env.PAGERDUTY_WEBHOOK_SECRET = 'test-secret';

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        headers: { 'x-pagerduty-signature': 'v1=invalid' },
        payload: makeWebhookPayload('user1'),
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.body).error).toBe('Invalid webhook signature');
    });

    it('passes when signature is valid', async () => {
      process.env.PAGERDUTY_WEBHOOK_SECRET = 'test-secret';
      setupMocks(['caregiver1'], ['fcm-token-1']);

      const payload = makeWebhookPayload('user1');
      const signature = signPayload(payload, 'test-secret');

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        headers: { 'x-pagerduty-signature': signature },
        payload,
      });

      expect(response.statusCode).toBe(200);
    });

    it('skips verification when no secret is configured', async () => {
      delete process.env.PAGERDUTY_WEBHOOK_SECRET;
      setupMocks(['caregiver1'], ['fcm-token-1']);

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: makeWebhookPayload('user1'),
      });

      expect(response.statusCode).toBe(200);
    });
  });

  // MARK: - Webhook Behavior

  describe('POST /api/alerts/webhook', () => {
    it('sends FCM push to caregiver on incident.triggered', async () => {
      setupMocks(['caregiver1'], ['fcm-token-1']);

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: makeWebhookPayload('user1'),
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.status).toBe('ok');
      expect(body.results).toHaveLength(1);
      expect(body.results[0].notified).toBe(1);

      // Notification body should be generic (no health details on lock screen)
      expect(mockSendEachForMulticast).toHaveBeenCalledWith({
        notification: {
          title: 'Health Alert',
          body: 'Someone you care for may need your attention.',
        },
        data: {
          type: 'health_alert',
          memberId: 'user1',
          alertDetail: 'Symptom spike: tremor severity 5/5',
        },
        tokens: ['fcm-token-1'],
      });
    });

    it('ignores non-triggered event types', async () => {
      const payload = {
        messages: [{
          event: {
            event_type: 'incident.resolved',
            data: { id: 'inc-002', title: 'Resolved' },
          },
        }],
      };

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload,
      });

      expect(response.statusCode).toBe(200);
      expect(mockSendEachForMulticast).not.toHaveBeenCalled();
    });

    it('handles missing userId in custom_details', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: makeWebhookPayload(null),
      });

      expect(response.statusCode).toBe(200);
      expect(mockSendEachForMulticast).not.toHaveBeenCalled();
    });

    it('handles no caregivers found', async () => {
      setupMocks([], []);

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: makeWebhookPayload('user1'),
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.results[0].notified).toBe(0);
      expect(mockSendEachForMulticast).not.toHaveBeenCalled();
    });

    it('returns 400 on invalid payload', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: { messages: [] },
      });

      expect(response.statusCode).toBe(400);
    });

    it('sends to multiple caregiver tokens', async () => {
      setupMocks(['cg1', 'cg2'], ['token-a', 'token-b']);
      mockSendEachForMulticast.mockResolvedValueOnce({ successCount: 2, failureCount: 0 });

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/alerts/webhook',
        payload: makeWebhookPayload('user1'),
      });

      const body = JSON.parse(response.body);
      expect(body.results[0].notified).toBe(2);
    });
  });
});
