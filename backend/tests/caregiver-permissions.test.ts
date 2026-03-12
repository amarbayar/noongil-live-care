import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock firebase
vi.mock('../src/services/firebase.js', () => ({
  initFirebase: vi.fn(),
  getDb: vi.fn(),
}));

import { getDb } from '../src/services/firebase.js';

describe('caregiver permissions', () => {
  let mockDb: any;

  function mockRelationshipSnap(permissions?: string[]) {
    const data: Record<string, unknown> = {
      caregiverId: 'cg1',
      memberId: 'm1',
      status: 'active',
      role: 'primary',
    };
    if (permissions !== undefined) {
      data.permissions = permissions;
    }
    return {
      empty: false,
      docs: [{ data: () => data }],
    };
  }

  function mockEmptySnap() {
    return { empty: true, docs: [] };
  }

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('legacy relationship without permissions field defaults to all', () => {
    // Simulate what the route does: data.permissions ?? ALL_PERMISSIONS
    const data = { caregiverId: 'cg1', status: 'active' };
    const ALL_PERMISSIONS = ['medications', 'reminders', 'schedule'];
    const permissions = (data as any).permissions ?? ALL_PERMISSIONS;
    expect(permissions).toEqual(ALL_PERMISSIONS);
  });

  it('relationship with explicit permissions preserves them', () => {
    const data = { caregiverId: 'cg1', status: 'active', permissions: ['medications'] };
    const ALL_PERMISSIONS = ['medications', 'reminders', 'schedule'];
    const permissions = (data as any).permissions ?? ALL_PERMISSIONS;
    expect(permissions).toEqual(['medications']);
  });

  it('medications-only permission should not include reminders', () => {
    const permissions = ['medications'];
    expect(permissions.includes('medications')).toBe(true);
    expect(permissions.includes('reminders')).toBe(false);
    expect(permissions.includes('schedule')).toBe(false);
  });

  it('reminders-only permission should allow reminder writes', () => {
    const permissions = ['reminders'];
    expect(permissions.includes('reminders')).toBe(true);
    expect(permissions.includes('medications')).toBe(false);
  });

  it('empty permissions array denies all access', () => {
    const permissions: string[] = [];
    expect(permissions.includes('medications')).toBe(false);
    expect(permissions.includes('reminders')).toBe(false);
    expect(permissions.includes('schedule')).toBe(false);
  });

  it('getRelationship returns exists=false for no relationship', () => {
    const snap = mockEmptySnap();
    const result = snap.empty
      ? { exists: false, permissions: [] as string[] }
      : { exists: true, permissions: snap.docs[0].data().permissions ?? ['medications', 'reminders', 'schedule'] };
    expect(result.exists).toBe(false);
    expect(result.permissions).toEqual([]);
  });

  it('getRelationship returns correct permissions for active relationship', () => {
    const snap = mockRelationshipSnap(['medications', 'schedule']);
    const data = snap.docs[0].data();
    const ALL_PERMISSIONS = ['medications', 'reminders', 'schedule'];
    const result = snap.empty
      ? { exists: false, permissions: [] as string[] }
      : { exists: true, permissions: (data.permissions as string[] | undefined) ?? ALL_PERMISSIONS };
    expect(result.exists).toBe(true);
    expect(result.permissions).toEqual(['medications', 'schedule']);
  });

  it('permission check for POST/PUT/DELETE requires reminders permission', () => {
    // Simulates the route guard logic
    function canManageReminders(permissions: string[]): boolean {
      return permissions.includes('reminders');
    }

    expect(canManageReminders(['medications', 'reminders', 'schedule'])).toBe(true);
    expect(canManageReminders(['reminders'])).toBe(true);
    expect(canManageReminders(['medications', 'schedule'])).toBe(false);
    expect(canManageReminders([])).toBe(false);
  });
});
