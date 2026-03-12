# Private Local Models

This public submission repo intentionally excludes the bundled on-device speech and audio models that exist in the private product repository.

Why they are omitted:

- several files are large enough to exceed GitHub's normal push limits
- these assets are not required for the judged Gemini Live + Google Cloud demo path
- some local model/runtime packaging is proprietary to the private product build

The hackathon demo path uses:

- Gemini Live for real-time voice interaction
- Firebase / Firestore for app state
- Cloud Run for backend APIs and caregiver workflows

If you are reproducing the full private local build, restore the model bundle from your own private asset source before running signed device builds.
