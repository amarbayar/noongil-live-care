# Noongil

Voice-first live wellness companion for people with Parkinson's and other motor impairments.

This public repo is the hackathon submission slice for the Gemini Live Agent Challenge 2026. It focuses on the `Live Agents` category: real-time, interruptible voice interaction, multimodal camera context, and Google Cloud-hosted backend services.

## What This Submission Demonstrates

- Gemini Live native-audio conversations on iOS
- Ray-Ban Meta smart glasses support through Meta Wearables DAT
- Multimodal camera / glasses handoff for vision-grounded responses
- Structured live check-ins with tool-calling guidance
- Firebase / Firestore-backed app state
- Fastify backend prepared for Cloud Run
- Vertex AI integration for server-side generation paths

## Repo Scope

This is a curated public submission repo, not the full private product repository.

- Included: the demoable source code, tests, deployment assets, and judge-facing setup material
- Excluded: internal strategy docs, confidential business planning, local secrets, and private environment configuration
- Excluded: bundled private on-device speech models and vendored native runtime binaries that are not required for the judged Gemini Live demo path

See [PUBLIC_REPO_SCOPE.md](PUBLIC_REPO_SCOPE.md).

## Monorepo Layout

- `ios/`: iOS app, including Meta Wearables / smart-glasses support
- `backend/`: Fastify backend for Cloud Run
- `contracts/`: shared schemas and codegen
- `infra/`: deployment scripts and Terraform
- `config/`: prompts, flags, strings, and theme config

## Quick Start

### Prerequisites

- Xcode 16+
- `xcodegen`
- Node.js 22+
- Firebase project credentials
- Google Cloud project
- Gemini API key for local development

### 1. Install dependencies

```bash
make setup
```

Note: this public repo intentionally excludes several private/local iOS model bundles and vendored speech-runtime binaries used in the private product build. The judged hackathon demo path does not depend on those omitted assets.

### 2. Configure iOS secrets

Add your own Firebase config file at:

```bash
ios/GoogleService-Info.plist
```

This file is intentionally not checked into the public repo.

Provide build settings for:

- `GEMINI_API_KEY`
- `BACKEND_BASE_URL`
- `PUBLIC_DASHBOARD_URL` if your caregiver dashboard lives on a different public host than the API
- `DEVELOPMENT_TEAM` if you want signed device builds

### 3. Configure backend env

Create:

```bash
backend/.env
```

Starting point:

```bash
cp backend/.env.example backend/.env
```

If you want the caregiver dashboard auth flow to work outside the deployed demo environment, provide Firebase Web config to the dashboard page, for example via a runtime script that sets:

```js
window.__NOONGIL_FIREBASE_CONFIG__ = {
  apiKey: "...",
  authDomain: "...",
  projectId: "...",
  storageBucket: "...",
  appId: "...",
  messagingSenderId: "...",
  measurementId: "..."
};
```

### 4. Run backend locally

```bash
make backend-dev
```

### 5. Build iOS app

```bash
cd ios
./build.sh
```

To check device-demo readiness before attempting signing:

```bash
cd ios
./build.sh doctor
```

For a signed device build:

```bash
cd ios
DEVELOPMENT_TEAM=YOURTEAMID \
PRODUCT_BUNDLE_IDENTIFIER=your.bundle.id \
BACKEND_BASE_URL=https://your-backend-url \
PUBLIC_DASHBOARD_URL=https://your-backend-url \
GEMINI_API_KEY=your_gemini_api_key \
./build.sh sign
```

### 6. Run tests

```bash
make backend-test
cd ios && ./build.sh test
```

To run the real Gemini Live integration tests:

```bash
cd ios && ./build.sh test-live
```

The Python fallback also requires `GEMINI_API_KEY` from the environment:

```bash
cd ios
GEMINI_API_KEY=your_gemini_api_key python3 Tests/test-gemini-live.py
```

## Google Cloud Deployment

Cloud deployment assets are under `infra/`.

Recommended Cloud Run deploy path:

```bash
cp infra/scripts/cloudrun.env.example .env.cloudrun
# edit .env.cloudrun with your project and runtime values
set -a
source .env.cloudrun
set +a
./infra/scripts/deploy-backend.sh
```

What the deploy script does:

- enables the required Google Cloud APIs
- creates an Artifact Registry repository if needed
- builds the backend image with Cloud Build
- deploys the backend to Cloud Run
- injects the backend env vars needed by the current enabled features
- prints the deployed service URL and `/health` endpoint

Optional Terraform path:

```bash
cd infra/terraform
terraform init
terraform plan \
  -var="project_id=your-gcp-project-id" \
  -var="image=us-central1-docker.pkg.dev/your-gcp-project-id/noongil/noongil-backend:latest"
terraform apply
```

Before deploying, set your own:

- `GCP_PROJECT_ID`
- `GCP_REGION`
- Firebase Admin / Firestore access in the target GCP project
- `PUBLIC_DASHBOARD_URL` so caregiver invites point at the right web host
- any Neo4j / Datadog / MailerSend / additional service env vars needed for the backend paths you enable

The checked-in Terraform is intentionally minimal. It does not build the image for you; it deploys an image URI you provide.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Final architecture image:

- `docs/architecture/noongil-architecture.png`

## Important Notes

- This submission repo includes a real Meta Wearables DAT integration path for Ray-Ban Meta smart glasses.
- This submission repo still contains direct Gemini client calls on iOS for the live demo path. That is acceptable for the hackathon demo, but not the intended production security posture.
- During development, we evaluated official Swift SDK-backed Live API options. For this submission, we kept the demo on the direct Gemini Live API transport because it produced the most reliable low-latency audio behavior for interruption-sensitive voice interaction.
- The backend contains a real Vertex AI service path and Cloud Run deployment assets, but not every Gemini path has been moved behind the backend yet.
- Caregiver email invites require `MAILERSEND_API_KEY`, `MAILERSEND_FROM_EMAIL`, and `PUBLIC_DASHBOARD_URL`. Caregivers must sign in with the same email address that was invited.
- The repo is optimized for judge inspection and reproducibility, not as a full production release artifact.
- For the hackathon, the strongest Cloud Run proof is:
  - a deployed `noongil-backend` service on Google Cloud
  - a short proof recording showing the service in Cloud Run and the app/backend working together
- Signed phone builds require:
  - a real `ios/GoogleService-Info.plist`
  - a valid Apple Development signing identity visible to `security find-identity -v -p codesigning`
  - `DEVELOPMENT_TEAM`
  - a real `PRODUCT_BUNDLE_IDENTIFIER`

## Judge Checklist

- Inspect `ios/features/gemini/` for Gemini Live client implementation
- Inspect `ios/features/glasses/` and `ios/Noongil/NoongilApp.swift` for Ray-Ban Meta smart-glasses integration
- Inspect `ios/features/checkin/` for live check-in flow
- Inspect `backend/src/services/vertex-ai.service.ts` for Google Cloud AI usage
- Inspect `infra/` for deployment automation
- Inspect `ios/Tests/GeminiLiveIntegrationTests.swift` for end-to-end live-agent validation
