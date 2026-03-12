import type { FastifyInstance } from 'fastify';
import { runCleanup } from './retention.service.js';

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export async function retentionCron(fastify: FastifyInstance): Promise<void> {
  let timer: ReturnType<typeof setInterval> | null = null;

  // Run cleanup daily
  timer = setInterval(async () => {
    try {
      fastify.log.info('Starting daily data retention cleanup');
      const results = await runCleanup();
      for (const r of results) {
        fastify.log.info(`Retention cleanup: deleted ${r.deletedCount} docs from ${r.collection}`);
      }
      fastify.log.info('Data retention cleanup complete');
    } catch (err) {
      fastify.log.error('Data retention cleanup failed: %s', err);
    }
  }, ONE_DAY_MS);

  // Cleanup on shutdown
  fastify.addHook('onClose', async () => {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  });
}
