# Architecture

The final architecture image lives at:

- [docs/architecture/noongil-architecture.png](architecture/noongil-architecture.png)

Use this PNG for the Devpost architecture upload and README references.

## Core Flow

- `ios/`: realtime voice pipeline, Meta Ray-Ban smart-glasses integration, multimodal camera handoff, live check-in orchestration
- `backend/`: Fastify service for caregiver APIs, dashboard reads, graph ingest, reporting, and voice messages
- `infra/`: Cloud Run deployment assets and Terraform
- `Firestore`: application state, reminders, caregiver relationships, voice messages
- `Neo4j`: symptom / trigger / heuristic graph analytics
- `Vertex AI`: server-side generation path

## Notes

- The strongest demo path is the on-device live-agent loop.
- The iOS app includes a real Meta Wearables DAT integration path for Ray-Ban Meta smart glasses.
- Cloud Run, Firestore, and Vertex AI provide the Google Cloud footprint.
- Some Gemini calls still originate from the client for the current hackathon demo slice because live latency was prioritized.
