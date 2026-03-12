import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock firebase before importing the module
vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(),
}));

vi.mock('../src/services/graph.service.js', () => ({
  graphService: {
    deleteOldGraphData: vi.fn().mockResolvedValue(5),
  },
}));

import { RETENTION_POLICIES, runCleanup } from '../src/services/retention.service.js';
import { getDb } from '../src/services/firebase.js';
import { graphService } from '../src/services/graph.service.js';

// Mock Firestore helpers
function createMockDoc(id: string, data: Record<string, any>) {
  return {
    id,
    ref: { id },
    data: () => data,
  };
}

function createMockSnapshot(docs: any[]) {
  return {
    docs,
    empty: docs.length === 0,
    size: docs.length,
  };
}

function createMockBatch() {
  const deleted: string[] = [];
  return {
    delete: vi.fn((ref: any) => deleted.push(ref.id)),
    commit: vi.fn().mockResolvedValue(undefined),
    _deleted: deleted,
  };
}

describe('retention.service', () => {
  let mockDb: any;
  let mockBatch: any;

  beforeEach(() => {
    vi.restoreAllMocks();
    vi.mocked(graphService.deleteOldGraphData).mockResolvedValue(5);
    mockBatch = createMockBatch();

    // Build a mock Firestore
    const mockCollection = vi.fn().mockReturnValue({
      where: vi.fn().mockReturnValue({
        limit: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue(createMockSnapshot([])),
        }),
        get: vi.fn().mockResolvedValue(createMockSnapshot([])),
      }),
      get: vi.fn().mockResolvedValue(createMockSnapshot([])),
    });

    const mockUserDoc = vi.fn().mockReturnValue({
      collection: mockCollection,
    });

    mockDb = {
      collection: vi.fn().mockReturnValue({
        listDocuments: vi.fn().mockResolvedValue([{ id: 'user1' }]),
        doc: mockUserDoc,
      }),
      batch: vi.fn().mockReturnValue(mockBatch),
    };

    vi.mocked(getDb).mockReturnValue(mockDb as any);
  });

  it('has correct retention periods', () => {
    expect(RETENTION_POLICIES.checkins).toBe(365);
    expect(RETENTION_POLICIES.medication_adherence).toBe(365);
    expect(RETENTION_POLICIES.memory).toBe(365);
    expect(RETENTION_POLICIES.checkin_sessions).toBe(90);
    expect(RETENTION_POLICIES.invite_codes).toBe(30);
    expect(RETENTION_POLICIES.graph).toBe(730);
    expect(RETENTION_POLICIES.caregiver_revoked).toBe(90);
    expect(RETENTION_POLICIES.medications_deactivated).toBe(365);
  });

  it('calls graph deleteOldGraphData with 2-year cutoff', async () => {
    await runCleanup();
    expect(graphService.deleteOldGraphData).toHaveBeenCalledTimes(1);
    const arg = vi.mocked(graphService.deleteOldGraphData).mock.calls[0][0];
    // Should be roughly 2 years ago (730 days)
    const cutoff = new Date(arg);
    const expectedCutoff = new Date();
    expectedCutoff.setDate(expectedCutoff.getDate() - 730);
    // Within 1 day tolerance
    expect(Math.abs(cutoff.getTime() - expectedCutoff.getTime())).toBeLessThan(86400000);
  });

  it('processes all user collections', async () => {
    await runCleanup();
    // Should query users collection
    expect(mockDb.collection).toHaveBeenCalledWith('users');
  });

  it('returns empty results when nothing to delete', async () => {
    const results = await runCleanup();
    // All Firestore queries return empty, graph returns 5
    const graphResult = results.find(r => r.collection === 'neo4j_graph');
    expect(graphResult?.deletedCount).toBe(5);
  });

  it('skips graph cleanup when Neo4j is not connected', async () => {
    vi.mocked(graphService.deleteOldGraphData).mockRejectedValue(new Error('Not connected'));
    const results = await runCleanup();
    const graphResult = results.find(r => r.collection === 'neo4j_graph');
    // Should not throw, returns 0 and gets filtered out
    expect(graphResult).toBeUndefined();
  });

  it('queries subcollections for each user', async () => {
    await runCleanup();
    const docCalls = mockDb.collection('users').doc;
    expect(docCalls).toHaveBeenCalledWith('user1');
  });

  it('processes multiple users', async () => {
    // Re-setup mockDb to have two users
    const mockSubCollection = vi.fn().mockReturnValue({
      where: vi.fn().mockReturnValue({
        limit: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue(createMockSnapshot([])),
        }),
      }),
    });

    const mockUserDocFn = vi.fn().mockReturnValue({
      collection: mockSubCollection,
    });

    const mockUsersCollection = {
      listDocuments: vi.fn().mockResolvedValue([{ id: 'user1' }, { id: 'user2' }]),
      doc: mockUserDocFn,
    };

    mockDb.collection = vi.fn().mockReturnValue(mockUsersCollection);

    const results = await runCleanup();
    // Should have called doc for both users
    expect(mockUserDocFn).toHaveBeenCalledWith('user1');
    expect(mockUserDocFn).toHaveBeenCalledWith('user2');
    // Graph result should be present (deleteOldGraphData returns 5)
    expect(results.some(r => r.collection === 'neo4j_graph')).toBe(true);
  });

  it('deletes old documents when found', async () => {
    const oldDoc = createMockDoc('old-checkin', {});
    const mockSubCollection = {
      where: vi.fn().mockReturnValue({
        limit: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue(createMockSnapshot([oldDoc])),
        }),
      }),
    };

    // Override the first subcollection call (checkins) to return a doc
    let callCount = 0;
    const mockUserDocFn = vi.fn().mockReturnValue({
      collection: vi.fn().mockImplementation(() => {
        callCount++;
        if (callCount === 1) return mockSubCollection; // checkins
        return {
          where: vi.fn().mockReturnValue({
            limit: vi.fn().mockReturnValue({
              get: vi.fn().mockResolvedValue(createMockSnapshot([])),
            }),
          }),
        };
      }),
    });

    mockDb.collection.mockReturnValue({
      listDocuments: vi.fn().mockResolvedValue([{ id: 'user1' }]),
      doc: mockUserDocFn,
    });

    const results = await runCleanup();
    // Should have a result for the checkins deletion
    const checkinResult = results.find(r => r.collection === 'user1/checkins');
    expect(checkinResult?.deletedCount).toBe(1);
    expect(mockBatch.delete).toHaveBeenCalledWith(oldDoc.ref);
    expect(mockBatch.commit).toHaveBeenCalled();
  });
});
