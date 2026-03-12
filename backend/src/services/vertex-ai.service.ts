import { GoogleAuth } from 'google-auth-library';

/// Vertex AI service for APIs not available via Gemini API key.
/// Currently only used for Lyria-002 music generation.
export class VertexAIService {
  private auth: GoogleAuth;
  private projectId: string;
  private region: string;

  constructor() {
    this.auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    });
    this.projectId = process.env.GCP_PROJECT_ID ?? '';
    this.region = process.env.GCP_REGION ?? 'us-central1';
  }

  private async getAccessToken(): Promise<string> {
    const client = await this.auth.getClient();
    const tokenResponse = await client.getAccessToken();
    if (!tokenResponse.token) {
      throw new Error('Failed to obtain access token');
    }
    return tokenResponse.token;
  }

  private baseUrl(): string {
    return `https://${this.region}-aiplatform.googleapis.com/v1/projects/${this.projectId}/locations/${this.region}`;
  }

  async generateMusic(req: {
    prompt: string;
    negativePrompt?: string;
  }): Promise<{ audioBase64: string; mimeType: string }> {
    const token = await this.getAccessToken();
    const url = `${this.baseUrl()}/publishers/google/models/lyria-002:predict`;

    const instance: Record<string, unknown> = { prompt: req.prompt };
    if (req.negativePrompt) {
      instance.negative_prompt = req.negativePrompt;
    }

    const body = {
      instances: [instance],
      parameters: {},
    };

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Lyria API error (${response.status}): ${errorText}`);
    }

    const data = (await response.json()) as {
      predictions: Array<{
        audioContent?: string;
        bytesBase64Encoded?: string;
        mimeType?: string;
      }>;
    };

    const prediction = data.predictions[0];
    const audioBase64 = prediction?.audioContent ?? prediction?.bytesBase64Encoded;
    if (!audioBase64) {
      throw new Error('Lyria generation response missing audio content');
    }

    return {
      audioBase64,
      mimeType: prediction.mimeType ?? 'audio/wav',
    };
  }
}

export const vertexAIService = new VertexAIService();
