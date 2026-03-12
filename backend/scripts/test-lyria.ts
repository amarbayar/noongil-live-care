import { VertexAIService } from '../src/services/vertex-ai.service.js';

async function main() {
  const svc = new VertexAIService();
  console.log('Testing Lyria-002 music generation...');
  console.log('Project:', process.env.GCP_PROJECT_ID);
  console.log('Region:', process.env.GCP_REGION);

  try {
    const result = await svc.generateMusic({ prompt: 'gentle rain ambient piano' });
    console.log('SUCCESS');
    console.log('  mimeType:', result.mimeType);
    console.log('  audioBase64 length:', result.audioBase64.length);
  } catch (err: any) {
    console.log('ERROR:', err.message);
  }
}

main();
