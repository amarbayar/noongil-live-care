import { describe, it, expect, vi, beforeAll, afterAll, beforeEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

// Mock firebase
const mockInvitationAdd = vi.fn();
const mockInvitationListGet = vi.fn();
const mockInvitationDocGet = vi.fn();
const mockInvitationDocUpdate = vi.fn();
const mockRelationshipAdd = vi.fn();
const mockVoiceMessageAdd = vi.fn();
const mockLookupSet = vi.fn();
const mockLookupGet = vi.fn();
const mockCaregiverLinkGet = vi.fn();
const mockCaregiverLinkSet = vi.fn();

const mockUserCollection = vi.fn((name: string) => {
  switch (name) {
    case 'caregiver_invitations':
      return {
        add: mockInvitationAdd,
        where: vi.fn(() => ({
          get: mockInvitationListGet,
        })),
        doc: vi.fn(() => ({
          get: mockInvitationDocGet,
          update: mockInvitationDocUpdate,
        })),
      };
    case 'caregiver_relationships':
      return {
        add: mockRelationshipAdd,
      };
    case 'voice_messages':
      return {
        add: mockVoiceMessageAdd,
      };
    default:
      return {
        add: vi.fn(),
        where: vi.fn(() => ({
          get: vi.fn(),
        })),
        doc: vi.fn(() => ({
          get: vi.fn(),
          update: vi.fn(),
        })),
      };
  }
});

const mockUserDoc = vi.fn(() => ({
  collection: mockUserCollection,
}));

const mockLookupDoc = vi.fn(() => ({
  set: mockLookupSet,
  get: mockLookupGet,
}));

vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(() => ({
    collection: vi.fn((name: string) => {
      if (name === 'users') {
        return {
          doc: mockUserDoc,
        };
      }

      if (name === 'caregiver_invitation_tokens') {
        return {
          doc: mockLookupDoc,
        };
      }

      if (name === 'caregiver_member_links') {
        return {
          where: vi.fn(() => ({
            get: mockCaregiverLinkGet,
          })),
          doc: vi.fn(() => ({
            set: mockCaregiverLinkSet,
          })),
        };
      }

      return {
        doc: vi.fn(() => ({
          get: vi.fn(),
          update: vi.fn(),
        })),
      };
    }),
    collectionGroup: vi.fn(),
  })),
}));

// Mock auth — sets userId, userEmail, and userName
vi.mock('../src/lib/auth.js', () => ({
  requireAuth: vi.fn(async (request: any, _reply: any) => {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return _reply.status(401).send({ error: 'Missing or malformed Authorization header' });
    }
    // Extract test user info from a custom header for test flexibility
    request.userId = request.headers['x-test-user-id'] ?? 'member-1';
    request.userEmail = request.headers['x-test-user-email'] ?? 'caregiver@example.com';
    request.userName = request.headers['x-test-user-name'] ?? 'Amar';
  }),
}));

const { mockSendCaregiverInvitationEmail } = vi.hoisted(() => ({
  mockSendCaregiverInvitationEmail: vi.fn().mockResolvedValue({
    status: 'skipped',
    inviteUrl: 'https://care.noongil.ai/dashboard?invite=test-token',
  }),
}));

vi.mock('../src/services/mailer.service.js', () => ({
  sendCaregiverInvitationEmail: mockSendCaregiverInvitationEmail,
}));

const { mockGetRelationship } = vi.hoisted(() => ({
  mockGetRelationship: vi.fn().mockResolvedValue({
    exists: true,
    permissions: ['medications', 'reminders', 'schedule', 'wellness'],
  }),
}));

vi.mock('../src/lib/caregiver-auth.js', () => ({
  getRelationship: mockGetRelationship,
  ALL_PERMISSIONS: ['medications', 'reminders', 'schedule', 'wellness'],
}));

import { caregiverRoutes } from '../src/routes/caregiver.routes.js';

const authHeaders = {
  authorization: 'Bearer valid-token',
  'x-test-user-id': 'member-1',
  'x-test-user-name': 'Amar',
};

describe('Caregiver Invitations', () => {
  let fastify: FastifyInstance;

  beforeAll(async () => {
    fastify = Fastify();
    await fastify.register(caregiverRoutes);
    await fastify.ready();
  });

  afterAll(async () => {
    await fastify.close();
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mockInvitationAdd.mockReset();
    mockInvitationListGet.mockReset();
    mockInvitationDocGet.mockReset();
    mockInvitationDocUpdate.mockReset();
    mockRelationshipAdd.mockReset();
    mockVoiceMessageAdd.mockReset();
    mockLookupSet.mockReset();
    mockLookupGet.mockReset();
    mockCaregiverLinkGet.mockReset();
    mockCaregiverLinkSet.mockReset();
    mockGetRelationship.mockReset();
    mockGetRelationship.mockResolvedValue({
      exists: true,
      permissions: ['medications', 'reminders', 'schedule', 'wellness'],
    });
    mockCaregiverLinkGet.mockResolvedValue({ docs: [] });
    mockSendCaregiverInvitationEmail.mockReset();
    mockSendCaregiverInvitationEmail.mockResolvedValue({
      status: 'skipped',
      inviteUrl: 'https://care.noongil.ai/dashboard?invite=test-token',
    });
  });

  describe('GET /api/caregiver/members', () => {
    it('lists only active caregiver relationships', async () => {
      mockCaregiverLinkGet.mockResolvedValueOnce({
        docs: [
          {
            data: () => ({
              memberId: 'member-1',
              memberName: 'Primary Member',
              role: 'primary',
              linkedAt: '2026-03-11T00:00:00Z',
              status: 'active',
            }),
          },
          {
            data: () => ({
              memberId: 'member-2',
              memberName: 'Inactive Member',
              role: 'backup',
              linkedAt: '2026-03-11T00:00:00Z',
              status: 'revoked',
            }),
          },
        ],
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/caregiver/members',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
        },
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.members).toEqual([
        {
          memberId: 'member-1',
          memberName: 'Primary Member',
          role: 'primary',
          linkedAt: '2026-03-11T00:00:00Z',
        },
      ]);
    });
  });

  describe('GET /api/caregiver/relationships', () => {
    it('lists active linked caregivers for the signed-in member', async () => {
      mockUserCollection.mockImplementationOnce((name: string) => {
        if (name === 'caregiver_relationships') {
          return {
            where: vi.fn(() => ({
              get: vi.fn().mockResolvedValue({
                docs: [
                  {
                    id: 'rel-1',
                    data: () => ({
                      memberId: 'member-1',
                      caregiverId: 'caregiver-1',
                      caregiverName: 'Jane',
                      role: 'primary',
                      status: 'active',
                      permissions: ['wellness', 'reminders'],
                      linkedAt: '2026-03-12T02:21:04.834Z',
                    }),
                  },
                ],
              }),
            })),
            add: mockRelationshipAdd,
          };
        }

        return {
          add: vi.fn(),
          where: vi.fn(() => ({ get: vi.fn() })),
          doc: vi.fn(() => ({ get: vi.fn(), update: vi.fn() })),
        };
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/caregiver/relationships',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.relationships).toEqual([
        {
          id: 'rel-1',
          memberId: 'member-1',
          caregiverId: 'caregiver-1',
          caregiverName: 'Jane',
          role: 'primary',
          status: 'active',
          permissions: ['wellness', 'reminders'],
          linkedAt: '2026-03-12T02:21:04.834Z',
        },
      ]);
    });
  });

  describe('POST /api/caregiver/invitations', () => {
    it('creates invitation with email, permissions, and token', async () => {
      process.env.PUBLIC_DASHBOARD_URL = 'https://care.noongil.ai';
      mockInvitationAdd.mockResolvedValueOnce({ id: 'inv-1', update: mockInvitationDocUpdate });
      mockLookupSet.mockResolvedValueOnce(undefined);
      mockSendCaregiverInvitationEmail.mockResolvedValueOnce({
        status: 'sent',
        inviteUrl: 'https://care.noongil.ai/dashboard?invite=invite-token',
      });

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitations',
        headers: authHeaders,
        payload: {
          caregiverEmail: 'alice@example.com',
          permissions: ['medications', 'wellness'],
        },
      });

      expect(response.statusCode).toBe(201);
      const body = JSON.parse(response.body);
      expect(body.id).toBe('inv-1');
      expect(body.caregiverEmail).toBe('alice@example.com');
      expect(body.permissions).toEqual(['medications', 'wellness']);
      expect(body.status).toBe('pending');
      expect(body.token).toBeDefined();
      expect(body.token.length).toBeGreaterThan(0);
      expect(body.expiresAt).toBeDefined();
      expect(body.inviteUrl).toBe('https://care.noongil.ai/dashboard?invite=invite-token');
      expect(body.emailDeliveryStatus).toBe('sent');
      expect(mockInvitationAdd).toHaveBeenCalledWith(expect.objectContaining({
        caregiverEmail: 'alice@example.com',
        memberName: 'Amar',
        permissions: ['medications', 'wellness'],
      }));
      expect(mockLookupSet).toHaveBeenCalledWith(expect.objectContaining({
        invitationId: 'inv-1',
        memberId: 'member-1',
      }));
      expect(mockSendCaregiverInvitationEmail).toHaveBeenCalledWith(expect.objectContaining({
        caregiverEmail: 'alice@example.com',
        dashboardBaseUrl: 'https://care.noongil.ai',
        memberId: 'member-1',
        memberName: 'Amar',
        permissions: ['medications', 'wellness'],
      }));
    });

    it('returns 502 if email delivery fails after invitation creation', async () => {
      mockInvitationAdd.mockResolvedValueOnce({ id: 'inv-1', update: mockInvitationDocUpdate });
      mockLookupSet.mockResolvedValueOnce(undefined);
      mockInvitationDocUpdate.mockResolvedValueOnce(undefined);
      mockSendCaregiverInvitationEmail.mockRejectedValueOnce(new Error('mailer offline'));

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitations',
        headers: authHeaders,
        payload: {
          caregiverEmail: 'alice@example.com',
          permissions: ['medications', 'wellness'],
        },
      });

      expect(response.statusCode).toBe(502);
      const body = JSON.parse(response.body);
      expect(body.error).toContain('Failed to send caregiver invitation email');
      expect(mockInvitationDocUpdate).toHaveBeenCalledWith(expect.objectContaining({ status: 'email_failed' }));
    });

    it('returns 400 for invalid email', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitations',
        headers: authHeaders,
        payload: {
          caregiverEmail: 'not-an-email',
          permissions: ['medications'],
        },
      });

      expect(response.statusCode).toBe(400);
    });

    it('returns 400 for empty permissions', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitations',
        headers: authHeaders,
        payload: {
          caregiverEmail: 'alice@example.com',
          permissions: [],
        },
      });

      expect(response.statusCode).toBe(400);
    });

    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitations',
        payload: {
          caregiverEmail: 'alice@example.com',
          permissions: ['medications'],
        },
      });

      expect(response.statusCode).toBe(401);
    });
  });

  describe('POST /api/caregiver/members/:memberId/voice-messages', () => {
    it('creates a voice message for an active caregiver relationship', async () => {
      mockVoiceMessageAdd.mockResolvedValueOnce({ id: 'voice-1' });

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/members/member-1/voice-messages',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
          'x-test-user-email': 'caregiver@example.com',
          'x-test-user-name': 'Amar',
        },
        payload: {
          audioBase64: 'UklGRiQAAABXQVZFZm10IA==',
          mimeType: 'audio/wav',
          durationSeconds: 6.4,
          transcript: 'Hi, just checking in.',
        },
      });

      expect(response.statusCode).toBe(201);
      const body = JSON.parse(response.body);
      expect(body.id).toBe('voice-1');
      expect(body.status).toBe('unread');
      expect(mockGetRelationship).toHaveBeenCalledWith('caregiver-1', 'member-1');
      expect(mockVoiceMessageAdd).toHaveBeenCalledWith(expect.objectContaining({
        caregiverId: 'caregiver-1',
        caregiverName: 'Amar',
        mimeType: 'audio/wav',
        durationSeconds: 6.4,
        status: 'unread',
      }));
    });

    it('returns 403 when no active caregiver relationship exists', async () => {
      mockGetRelationship.mockResolvedValueOnce({ exists: false, permissions: [] });

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/members/member-1/voice-messages',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
        },
        payload: {
          audioBase64: 'UklGRiQAAABXQVZFZm10IA==',
          mimeType: 'audio/wav',
          durationSeconds: 6.4,
        },
      });

      expect(response.statusCode).toBe(403);
    });
  });

  describe('GET /api/caregiver/invitations', () => {
    it('lists pending and accepted invitations', async () => {
      mockInvitationListGet.mockResolvedValueOnce({
        docs: [
          {
            id: 'inv-1',
            data: () => ({
              caregiverEmail: 'alice@example.com',
              permissions: ['medications'],
              status: 'pending',
              token: 'tok-1',
              createdAt: '2026-03-10T00:00:00Z',
              expiresAt: '2026-03-17T00:00:00Z',
            }),
          },
        ],
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/caregiver/invitations',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.invitations).toHaveLength(1);
      expect(body.invitations[0].caregiverEmail).toBe('alice@example.com');
    });
  });

  describe('DELETE /api/caregiver/invitations/:id', () => {
    it('revokes an invitation', async () => {
      mockInvitationDocGet.mockResolvedValueOnce({ exists: true });
      mockInvitationDocUpdate.mockResolvedValueOnce(undefined);

      const response = await fastify.inject({
        method: 'DELETE',
        url: '/api/caregiver/invitations/inv-1',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.status).toBe('revoked');
    });

    it('returns 404 for non-existent invitation', async () => {
      mockInvitationDocGet.mockResolvedValueOnce({ exists: false });

      const response = await fastify.inject({
        method: 'DELETE',
        url: '/api/caregiver/invitations/nope',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe('GET /api/caregiver/invitation/:token', () => {
    it('returns invitation details by token', async () => {
      mockLookupGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          invitationId: 'inv-1',
          memberId: 'member-1',
        }),
      });
      mockInvitationDocGet.mockResolvedValueOnce({
        exists: true,
        id: 'inv-1',
        data: () => ({
          caregiverEmail: 'alice@example.com',
          permissions: ['medications', 'wellness'],
          status: 'pending',
          expiresAt: '2026-03-17T00:00:00Z',
        }),
      });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/caregiver/invitation/some-uuid-token',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.caregiverEmail).toBe('alice@example.com');
      expect(body.permissions).toEqual(['medications', 'wellness']);
    });

    it('returns 404 for unknown token', async () => {
      mockLookupGet.mockResolvedValueOnce({ exists: false });

      const response = await fastify.inject({
        method: 'GET',
        url: '/api/caregiver/invitation/bad-token',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe('POST /api/caregiver/invitation/:token/accept', () => {
    function mockInvitationDoc(overrides: Record<string, unknown> = {}) {
      const data = {
        caregiverEmail: 'caregiver@example.com',
        memberName: 'Amarbayar Amarsanaa',
        permissions: ['medications', 'wellness'],
        status: 'pending',
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
        ...overrides,
      };

      return {
        exists: true,
        id: 'inv-1',
        data: () => data,
        ref: {
          update: mockInvitationDocUpdate,
          parent: {
            parent: { id: 'member-1' },
          },
        },
      };
    }

    it('accepts invitation and creates relationship', async () => {
      mockLookupGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          invitationId: 'inv-1',
          memberId: 'member-1',
        }),
      });
      mockInvitationDocGet.mockResolvedValueOnce(mockInvitationDoc());
      mockRelationshipAdd.mockResolvedValueOnce({ id: 'rel-1' });
      mockCaregiverLinkSet.mockResolvedValueOnce(undefined);
      mockInvitationDocUpdate.mockResolvedValueOnce(undefined);

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitation/some-token/accept',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
          'x-test-user-email': 'caregiver@example.com',
        },
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.status).toBe('accepted');
      expect(body.memberId).toBe('member-1');
      expect(mockRelationshipAdd).toHaveBeenCalledWith(expect.objectContaining({
        memberName: 'Amarbayar Amarsanaa',
        caregiverName: 'Amar',
      }));
      expect(mockCaregiverLinkSet).toHaveBeenCalledWith(expect.objectContaining({
        caregiverId: 'caregiver-1',
        memberId: 'member-1',
        memberName: 'Amarbayar Amarsanaa',
        caregiverName: 'Amar',
        status: 'active',
      }));
    });

    it('returns 403 if email does not match', async () => {
      mockLookupGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          invitationId: 'inv-1',
          memberId: 'member-1',
        }),
      });
      mockInvitationDocGet.mockResolvedValueOnce(mockInvitationDoc());

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitation/some-token/accept',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
          'x-test-user-email': 'wrong@example.com',
        },
      });

      expect(response.statusCode).toBe(403);
    });

    it('returns 400 if invitation is revoked', async () => {
      mockLookupGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          invitationId: 'inv-1',
          memberId: 'member-1',
        }),
      });
      mockInvitationDocGet.mockResolvedValueOnce(mockInvitationDoc({ status: 'revoked' }));

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitation/some-token/accept',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
          'x-test-user-email': 'caregiver@example.com',
        },
      });

      expect(response.statusCode).toBe(400);
      const body = JSON.parse(response.body);
      expect(body.error).toContain('revoked');
    });

    it('returns 400 if invitation is expired', async () => {
      mockLookupGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          invitationId: 'inv-1',
          memberId: 'member-1',
        }),
      });
      mockInvitationDocGet.mockResolvedValueOnce(mockInvitationDoc({
        expiresAt: new Date(Date.now() - 86400000).toISOString(),
      }));
      mockInvitationDocUpdate.mockResolvedValueOnce(undefined);

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitation/some-token/accept',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
          'x-test-user-email': 'caregiver@example.com',
        },
      });

      expect(response.statusCode).toBe(400);
      const body = JSON.parse(response.body);
      expect(body.error).toContain('expired');
    });

    it('returns 404 for unknown token', async () => {
      mockLookupGet.mockResolvedValueOnce({ exists: false });

      const response = await fastify.inject({
        method: 'POST',
        url: '/api/caregiver/invitation/bad-token/accept',
        headers: {
          ...authHeaders,
          'x-test-user-id': 'caregiver-1',
          'x-test-user-email': 'caregiver@example.com',
        },
      });

      expect(response.statusCode).toBe(404);
    });
  });
});
