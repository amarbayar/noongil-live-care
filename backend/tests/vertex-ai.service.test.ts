import { beforeEach, describe, expect, it, vi } from 'vitest';

const { mockGetAccessToken } = vi.hoisted(() => ({
  mockGetAccessToken: vi.fn(),
}));

vi.mock('google-auth-library', () => ({
  GoogleAuth: vi.fn().mockImplementation(() => ({
    getClient: vi.fn().mockResolvedValue({
      getAccessToken: mockGetAccessToken,
    }),
  })),
}));

import { VertexAIService } from '../src/services/vertex-ai.service.js';

describe('VertexAIService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetAccessToken.mockResolvedValue({ token: 'access-token' });
    process.env.GCP_PROJECT_ID = 'test-project';
    process.env.GCP_REGION = 'us-central1';
  });

  it('accepts bytesBase64Encoded when Lyria omits audioContent', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        predictions: [
          {
            bytesBase64Encoded: 'AQID',
            mimeType: 'audio/wav',
          },
        ],
      }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const service = new VertexAIService();
    const result = await service.generateMusic({ prompt: 'gentle rain' });

    expect(result.audioBase64).toBe('AQID');
    expect(result.mimeType).toBe('audio/wav');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
