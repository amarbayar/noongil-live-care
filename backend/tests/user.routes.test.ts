import { describe, it, expect, vi, beforeAll, afterAll, beforeEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

// Mock auth
vi.mock('../src/lib/auth.js', () => ({
  requireAuth: vi.fn(async (request: any, _reply: any) => {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return _reply.status(401).send({ error: 'Missing or malformed Authorization header' });
    }
    request.userId = 'user1';
  }),
}));

// Mock firebase
const { mockRecursiveDelete, mockGet, mockCollectionGet } = vi.hoisted(() => ({
  mockRecursiveDelete: vi.fn().mockResolvedValue(undefined),
  mockGet: vi.fn().mockResolvedValue({ exists: true, data: () => ({ name: 'Test User' }) }),
  mockCollectionGet: vi.fn().mockResolvedValue({ docs: [] }),
}));

vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(() => ({
    collection: vi.fn().mockReturnValue({
      doc: vi.fn().mockReturnValue({
        get: mockGet,
        collection: vi.fn().mockReturnValue({
          get: mockCollectionGet,
        }),
      }),
    }),
    recursiveDelete: mockRecursiveDelete,
  })),
}));

// Mock firebase-admin/auth
const { mockDeleteUser } = vi.hoisted(() => ({
  mockDeleteUser: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('firebase-admin/auth', () => ({
  getAuth: vi.fn(() => ({
    deleteUser: mockDeleteUser,
  })),
}));

// Mock graph service
const { mockDeleteUserData } = vi.hoisted(() => ({
  mockDeleteUserData: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../src/services/graph.service.js', () => ({
  graphService: {
    deleteUserData: mockDeleteUserData,
  },
}));

import { userRoutes } from '../src/routes/user.routes.js';

const authHeaders = { authorization: 'Bearer valid-token' };

describe('User Routes', () => {
  let fastify: FastifyInstance;

  beforeAll(async () => {
    fastify = Fastify();
    await fastify.register(userRoutes);
    await fastify.ready();
  });

  afterAll(async () => {
    await fastify.close();
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('DELETE /api/users/me', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'DELETE',
        url: '/api/users/me',
      });
      expect(response.statusCode).toBe(401);
    });

    it('cascading deletes Firestore, Neo4j, and Firebase Auth', async () => {
      const response = await fastify.inject({
        method: 'DELETE',
        url: '/api/users/me',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      expect(JSON.parse(response.body).status).toBe('deleted');
      expect(mockRecursiveDelete).toHaveBeenCalled();
      expect(mockDeleteUserData).toHaveBeenCalledWith('user1');
      expect(mockDeleteUser).toHaveBeenCalledWith('user1');
    });

    it('still succeeds if Neo4j deletion fails', async () => {
      mockDeleteUserData.mockRejectedValueOnce(new Error('Neo4j not connected'));

      const response = await fastify.inject({
        method: 'DELETE',
        url: '/api/users/me',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      expect(mockDeleteUser).toHaveBeenCalledWith('user1');
    });
  });

  describe('GET /api/users/me/export', () => {
    it('returns 401 without auth', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/users/me/export',
      });
      expect(response.statusCode).toBe(401);
    });

    it('returns user data export', async () => {
      const response = await fastify.inject({
        method: 'GET',
        url: '/api/users/me/export',
        headers: authHeaders,
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.userId).toBe('user1');
      expect(body.profile).toEqual({ name: 'Test User' });
      expect(body.exportedAt).toBeDefined();
    });
  });
});
