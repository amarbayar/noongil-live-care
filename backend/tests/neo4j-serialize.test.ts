import { describe, it, expect } from 'vitest';
import { serializeValue, toNumber } from '../src/lib/neo4j-serialize.js';

describe('neo4j-serialize', () => {
  describe('serializeValue', () => {
    it('should pass through primitives', () => {
      expect(serializeValue(42)).toBe(42);
      expect(serializeValue('hello')).toBe('hello');
      expect(serializeValue(true)).toBe(true);
      expect(serializeValue(null)).toBe(null);
      expect(serializeValue(undefined)).toBe(null);
    });

    it('should unwrap Neo4j Integer {low, high}', () => {
      expect(serializeValue({ low: 42, high: 0 })).toBe(42);
      expect(serializeValue({ low: 0, high: 0 })).toBe(0);
    });

    it('should unwrap Neo4j Integer with toNumber()', () => {
      const neo4jInt = { low: 5, high: 0, toNumber: () => 5 };
      // Has more than 2 keys, so low/high check won't match — falls to toNumber
      expect(serializeValue(neo4jInt)).toBe(5);
    });

    it('should convert Neo4j Date to ISO date string', () => {
      // Neo4j Date: { year, month, day } — each may be an Integer
      const neo4jDate = {
        year: { low: 2026, high: 0 },
        month: { low: 2, high: 0 },
        day: { low: 5, high: 0 },
      };
      expect(serializeValue(neo4jDate)).toBe('2026-02-05');
    });

    it('should convert Neo4j Date with primitive components', () => {
      const neo4jDate = { year: 2026, month: 12, day: 25 };
      expect(serializeValue(neo4jDate)).toBe('2026-12-25');
    });

    it('should convert Neo4j DateTime to ISO datetime string', () => {
      const neo4jDateTime = {
        year: { low: 2026, high: 0 },
        month: { low: 2, high: 0 },
        day: { low: 15, high: 0 },
        hour: { low: 8, high: 0 },
        minute: { low: 30, high: 0 },
        second: { low: 0, high: 0 },
      };
      expect(serializeValue(neo4jDateTime)).toBe('2026-02-15T08:30:00');
    });

    it('should zero-pad single-digit date components', () => {
      const neo4jDate = { year: 2026, month: 1, day: 3 };
      expect(serializeValue(neo4jDate)).toBe('2026-01-03');
    });

    it('should unwrap Neo4j Node objects', () => {
      const node = {
        labels: ['Day'],
        properties: { date: '2026-02-15', overallScore: { low: 4, high: 0 } },
      };
      const result = serializeValue(node) as Record<string, unknown>;
      expect(result.date).toBe('2026-02-15');
      expect(result.overallScore).toBe(4);
    });

    it('should recurse into arrays', () => {
      const arr = [{ low: 1, high: 0 }, null, { low: 3, high: 0 }];
      expect(serializeValue(arr)).toEqual([1, null, 3]);
    });

    it('should recurse into nested objects', () => {
      const obj = {
        score: { low: 4, high: 0 },
        label: 'test',
        nested: { value: { low: 7, high: 0 } },
      };
      const result = serializeValue(obj) as Record<string, unknown>;
      expect(result.score).toBe(4);
      expect(result.label).toBe('test');
      expect((result.nested as Record<string, unknown>).value).toBe(7);
    });
  });

  describe('toNumber', () => {
    it('should return number for primitive', () => {
      expect(toNumber(42)).toBe(42);
      expect(toNumber(3.14)).toBe(3.14);
    });

    it('should return null for null/undefined', () => {
      expect(toNumber(null)).toBeNull();
      expect(toNumber(undefined)).toBeNull();
    });

    it('should unwrap Neo4j Integer', () => {
      expect(toNumber({ low: 42, high: 0 })).toBe(42);
    });

    it('should use toNumber() method', () => {
      expect(toNumber({ toNumber: () => 99 })).toBe(99);
    });

    it('should return null for non-numeric types', () => {
      expect(toNumber('hello')).toBeNull();
      expect(toNumber(true)).toBeNull();
    });
  });
});
