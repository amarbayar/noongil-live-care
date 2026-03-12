// Universal serializer for Neo4j result values.
// Handles Integer wrappers, DateTime/Date objects, Node unwrapping, and nested structures.
// Adapted from lifepulse-aura hackathon project's battle-tested pattern.

export function serializeValue(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'object') return value;

  const obj = value as Record<string, unknown>;

  // Neo4j Node → extract properties
  if ('labels' in obj && 'properties' in obj) {
    return serializeValue(obj.properties);
  }

  // Neo4j Integer → unwrap {low, high}
  // Also check for .toNumber() method (driver v5 uses both patterns)
  if ('low' in obj && 'high' in obj && Object.keys(obj).length === 2) {
    return Number((obj as { low: number }).low);
  }
  if ('toNumber' in obj && typeof (obj as { toNumber: unknown }).toNumber === 'function') {
    return (obj as { toNumber: () => number }).toNumber();
  }

  // Neo4j DateTime/LocalDateTime/Date → ISO string
  // Each component (year, month, day, etc.) may itself be a Neo4j Integer.
  if ('year' in obj && 'month' in obj && 'day' in obj) {
    const y = extractInt(obj.year);
    const m = extractInt(obj.month);
    const d = extractInt(obj.day);

    // Date-only (no hour property or hour is undefined)
    if (!('hour' in obj)) {
      return `${y}-${pad(m)}-${pad(d)}`;
    }

    const hr = extractInt(obj.hour);
    const min = extractInt(obj.minute);
    const sec = extractInt(obj.second);
    return `${y}-${pad(m)}-${pad(d)}T${pad(hr)}:${pad(min)}:${pad(sec)}`;
  }

  // Array → recurse
  if (Array.isArray(value)) {
    return value.map(serializeValue);
  }

  // Plain object → recurse
  const result: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    result[k] = serializeValue(v);
  }
  return result;
}

// Extract a number from a potentially Integer-wrapped value.
function extractInt(val: unknown): number {
  if (val === null || val === undefined) return 0;
  if (typeof val === 'number') return val;
  if (typeof val === 'object' && val !== null) {
    const o = val as Record<string, unknown>;
    if ('low' in o) return Number(o.low);
    if ('toNumber' in o && typeof o.toNumber === 'function') {
      return (o as { toNumber: () => number }).toNumber();
    }
  }
  return 0;
}

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

// Convenience: convert a single value to number | null.
// Useful when you know the field should be numeric.
export function toNumber(val: unknown): number | null {
  if (val === null || val === undefined) return null;
  if (typeof val === 'number') return val;
  if (typeof val === 'object' && val !== null) {
    const o = val as Record<string, unknown>;
    if ('low' in o && 'high' in o) return Number(o.low);
    if ('toNumber' in o && typeof o.toNumber === 'function') {
      return (o as { toNumber: () => number }).toNumber();
    }
  }
  return null;
}
