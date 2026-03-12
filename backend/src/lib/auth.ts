import type { FastifyRequest, FastifyReply } from 'fastify';
import { getAuth } from 'firebase-admin/auth';

declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
    userEmail?: string;
    userName?: string;
  }
}

/**
 * Fastify preHandler hook that validates a Firebase ID token from the
 * Authorization header and sets request.userId.
 */
export async function requireAuth(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return reply.status(401).send({ error: 'Missing or malformed Authorization header' });
  }

  const token = header.slice(7);
  try {
    const decoded = await getAuth().verifyIdToken(token);
    request.userId = decoded.uid;
    request.userEmail = decoded.email;
    request.userName = typeof decoded.name === 'string' ? decoded.name : undefined;
  } catch (err) {
    request.log.warn({ err }, 'Invalid Firebase ID token');
    return reply.status(401).send({ error: 'Invalid or expired token' });
  }
}
