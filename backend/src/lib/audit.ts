import type { FastifyInstance } from 'fastify';
import crypto from 'node:crypto';

function hashUserId(userId: string): string {
  return crypto.createHash('sha256').update(userId).digest('hex').slice(0, 16);
}

export function registerAuditLog(fastify: FastifyInstance): void {
  fastify.addHook('onResponse', (request, reply, done) => {
    const userId = request.userId ? hashUserId(request.userId) : 'anon';
    const durationMs = reply.elapsedTime;

    request.log.info({
      audit: true,
      userId,
      method: request.method,
      url: request.url,
      statusCode: reply.statusCode,
      durationMs: Math.round(durationMs),
      timestamp: new Date().toISOString(),
    }, 'audit');

    done();
  });
}
