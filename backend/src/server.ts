import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { initFirebase } from './services/firebase.js';
import { graphService } from './services/graph.service.js';
import { causalService } from './services/causal.service.js';
import { retentionCron } from './services/retention.cron.js';
import { registerAuditLog } from './lib/audit.js';
import { graphRoutes } from './routes/graph.routes.js';
import { reportRoutes } from './routes/report.routes.js';
import { caregiverRoutes } from './routes/caregiver.routes.js';
import { generateRoutes } from './routes/generate.routes.js';
import { dashboardRoutes } from './routes/dashboard.routes.js';
import { alertRoutes } from './routes/alert.routes.js';
import { userRoutes } from './routes/user.routes.js';

// Initialize Firebase Admin SDK
initFirebase();

const fastify = Fastify({ logger: true });

await fastify.register(cors);

// Rate limiting: 100 requests per minute, keyed by userId or IP
await fastify.register(rateLimit, {
  max: 100,
  timeWindow: '1 minute',
  keyGenerator: (request) => request.userId ?? request.ip,
});

// Audit logging on all responses
registerAuditLog(fastify);

// Health check
fastify.get('/health', async () => {
  return { status: 'ok', service: 'noongil-backend' };
});

// Register API routes
await fastify.register(graphRoutes);
await fastify.register(reportRoutes);
await fastify.register(caregiverRoutes);
await fastify.register(generateRoutes);
await fastify.register(dashboardRoutes);
await fastify.register(alertRoutes);
await fastify.register(userRoutes);

// Data retention: daily cleanup of expired data
await fastify.register(retentionCron);

// Connect to Neo4j on startup
const neo4jUri = process.env.NEO4J_URI;
if (neo4jUri) {
  try {
    await graphService.connect();
    await causalService.connect();
    fastify.log.info('Connected to Neo4j');
  } catch (err) {
    fastify.log.warn('Neo4j connection failed (will retry on first request): %s', err);
  }
}

// Graceful shutdown
fastify.addHook('onClose', async () => {
  await causalService.disconnect();
  await graphService.disconnect();
});

const port = parseInt(process.env.PORT ?? '8080', 10);

try {
  await fastify.listen({ port, host: '0.0.0.0' });
} catch (err) {
  fastify.log.error(err);
  process.exit(1);
}
