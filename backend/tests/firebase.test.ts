import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('firebase-admin/app', () => ({
  initializeApp: vi.fn(() => ({ name: '[DEFAULT]' })),
  getApps: vi.fn(() => []),
  cert: vi.fn(),
}));

vi.mock('firebase-admin/firestore', () => ({
  getFirestore: vi.fn(() => ({ collection: vi.fn() })),
}));

describe('firebase', () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
  });

  it('should call initializeApp on first call', async () => {
    const { initializeApp, getApps } = await import('firebase-admin/app');
    (getApps as ReturnType<typeof vi.fn>).mockReturnValue([]);

    const { initFirebase } = await import('../src/services/firebase.js');
    initFirebase();

    expect(initializeApp).toHaveBeenCalledOnce();
  });

  it('should not reinitialize when app already exists', async () => {
    const { initializeApp, getApps } = await import('firebase-admin/app');
    (getApps as ReturnType<typeof vi.fn>).mockReturnValue([{ name: '[DEFAULT]' }]);

    const { initFirebase } = await import('../src/services/firebase.js');
    initFirebase();

    expect(initializeApp).not.toHaveBeenCalled();
  });

  it('should throw when getDb called before init', async () => {
    const { getDb } = await import('../src/services/firebase.js');
    expect(() => getDb()).toThrow('Firebase not initialized');
  });
});
