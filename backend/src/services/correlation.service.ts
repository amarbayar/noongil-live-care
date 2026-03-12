import { sampleCorrelation } from 'simple-statistics';
import { graphService, type TimeSeriesData, type CorrelationResult } from './graph.service.js';

// Metric pairs to correlate. Each pair is checked at lags 0-3 days.
const METRIC_PAIRS: Array<[string, string]> = [
  ['mood', 'sleepHours'],
  ['mood', 'sleepQuality'],
  ['mood', 'medAdherence'],
  ['sleepHours', 'medAdherence'],
  ['sleepQuality', 'medAdherence'],
];

// Significance thresholds
const P_THRESHOLD = 0.05;
const R_THRESHOLD = 0.3;
const MIN_SAMPLES = 7;
const MAX_LAG = 3;
const WINDOW_DAYS = 30;

export class CorrelationService {
  // Run correlation analysis for a user over a rolling window.
  // Designed to be called as a nightly batch job.
  async computeForUser(userId: string): Promise<CorrelationResult[]> {
    const endDate = new Date().toISOString().split('T')[0];
    const startDate = subtractDays(endDate, WINDOW_DAYS);

    const timeSeries = await graphService.extractTimeSeries(userId, startDate, endDate);
    const metricVectors = buildMetricVectors(timeSeries);

    // Discover symptom types present in the data
    const symptomTypes = await discoverSymptomTypes(timeSeries, userId, startDate, endDate);

    // Load symptom series
    const symptomVectors: Record<string, (number | null)[]> = {};
    for (const type of symptomTypes) {
      symptomVectors[type] = await graphService.extractSymptomSeries(
        userId, type, startDate, endDate
      );
    }

    const significant: CorrelationResult[] = [];

    // Core metric pairs
    for (const [nameA, nameB] of METRIC_PAIRS) {
      const seriesA = metricVectors[nameA];
      const seriesB = metricVectors[nameB];
      if (!seriesA || !seriesB) continue;

      const best = findBestLagCorrelation(seriesA, seriesB, nameA, nameB);
      if (best) significant.push(best);
    }

    // Symptom vs. core metrics
    for (const symptomType of symptomTypes) {
      const symptomSeries = symptomVectors[symptomType];
      if (!symptomSeries) continue;

      for (const metricName of ['mood', 'sleepHours', 'sleepQuality', 'medAdherence']) {
        const metricSeries = metricVectors[metricName];
        if (!metricSeries) continue;

        const best = findBestLagCorrelation(symptomSeries, metricSeries, symptomType, metricName);
        if (best) significant.push(best);
      }
    }

    // Store results in graph
    for (const result of significant) {
      await graphService.storeCorrelation(userId, result, startDate, endDate);
    }

    return significant;
  }
}

// Build named vectors from time series data.
function buildMetricVectors(ts: TimeSeriesData): Record<string, (number | null)[]> {
  return {
    mood: ts.moodSeries,
    sleepHours: ts.sleepHoursSeries,
    sleepQuality: ts.sleepQualitySeries,
    medAdherence: ts.medAdherenceSeries,
  };
}

// Discover which symptom types are present by checking the graph.
// Uses a lightweight heuristic: extract day aggregates and collect distinct symptom types.
async function discoverSymptomTypes(
  _ts: TimeSeriesData,
  userId: string,
  startDate: string,
  endDate: string
): Promise<string[]> {
  const graphData = await graphService.getGraphData(userId, startDate, endDate);
  const types = new Set<string>();
  for (const day of graphData) {
    for (const sym of day.symptoms) {
      if (sym.type) types.add(sym.type);
    }
  }
  return Array.from(types);
}

// Find the lag (0 to MAX_LAG) that produces the strongest significant correlation.
function findBestLagCorrelation(
  seriesA: (number | null)[],
  seriesB: (number | null)[],
  nameA: string,
  nameB: string
): CorrelationResult | null {
  let best: CorrelationResult | null = null;
  let bestAbsR = 0;

  for (let lag = 0; lag <= MAX_LAG; lag++) {
    // Shift seriesB forward by `lag` — does A on day N correlate with B on day N+lag?
    const { x, y } = alignWithLag(seriesA, seriesB, lag);
    if (x.length < MIN_SAMPLES) continue;

    const r = sampleCorrelation(x, y);
    if (!isFinite(r)) continue;

    const n = x.length;
    const pValue = pearsonPValue(r, n);

    if (Math.abs(r) > R_THRESHOLD && pValue < P_THRESHOLD && Math.abs(r) > bestAbsR) {
      bestAbsR = Math.abs(r);
      best = {
        nameA,
        nameB,
        correlation: Math.round(r * 1000) / 1000,
        pValue: Math.round(pValue * 10000) / 10000,
        sampleSize: n,
        lag,
        method: 'pearson',
      };
    }
  }

  return best;
}

// Align two series with a lag, dropping null values from both.
// lag=0: pair A[i] with B[i]
// lag=1: pair A[i] with B[i+1] (does A today predict B tomorrow?)
function alignWithLag(
  a: (number | null)[],
  b: (number | null)[],
  lag: number
): { x: number[]; y: number[] } {
  const x: number[] = [];
  const y: number[] = [];
  const limit = Math.min(a.length, b.length - lag);

  for (let i = 0; i < limit; i++) {
    const av = a[i];
    const bv = b[i + lag];
    if (av !== null && bv !== null) {
      x.push(av);
      y.push(bv);
    }
  }

  return { x, y };
}

// Two-tailed p-value for Pearson r using the t-distribution.
// t = r * sqrt((n-2) / (1 - r^2)), df = n - 2
export function pearsonPValue(r: number, n: number): number {
  if (n <= 2) return 1;
  if (Math.abs(r) >= 1) return 0;

  const df = n - 2;
  const t = Math.abs(r) * Math.sqrt(df / (1 - r * r));
  // Two-tailed: p = 2 * (1 - CDF_t(|t|, df))
  return 2 * (1 - tDistCDF(t, df));
}

// CDF of the t-distribution via the regularized incomplete beta function.
// For t >= 0: CDF(t, df) = 1 - 0.5 * I(df / (df + t^2), df/2, 1/2)
// where I is the regularized incomplete beta function.
function tDistCDF(t: number, df: number): number {
  if (t < 0) return 1 - tDistCDF(-t, df);
  const x = df / (df + t * t);
  return 1 - 0.5 * regularizedBeta(x, df / 2, 0.5);
}

// Regularized incomplete beta function I_x(a, b) via continued fraction (Lentz's method).
// Accurate to ~1e-10 for typical statistical use.
function regularizedBeta(x: number, a: number, b: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;

  const lnBeta = gammaln(a) + gammaln(b) - gammaln(a + b);
  const front = Math.exp(Math.log(x) * a + Math.log(1 - x) * b - lnBeta);

  // Use continued fraction expansion
  if (x < (a + 1) / (a + b + 2)) {
    return (front * betaCF(x, a, b)) / a;
  }
  return 1 - (front * betaCF(1 - x, b, a)) / b;
}

// Continued fraction for the incomplete beta function (modified Lentz's algorithm).
function betaCF(x: number, a: number, b: number): number {
  const maxIter = 200;
  const eps = 1e-14;
  const tiny = 1e-30;

  let c = 1;
  let d = 1 / Math.max(Math.abs(1 - (a + b) * x / (a + 1)), tiny);
  let h = d;

  for (let m = 1; m <= maxIter; m++) {
    // Even step
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((a + m2 - 1) * (a + m2));
    d = 1 / Math.max(Math.abs(1 + aa * d), tiny);
    c = Math.max(Math.abs(1 + aa / c), tiny);
    h *= d * c;

    // Odd step
    aa = -((a + m) * (a + b + m) * x) / ((a + m2) * (a + m2 + 1));
    d = 1 / Math.max(Math.abs(1 + aa * d), tiny);
    c = Math.max(Math.abs(1 + aa / c), tiny);
    const delta = d * c;
    h *= delta;

    if (Math.abs(delta - 1) < eps) break;
  }

  return h;
}

// Log-gamma function (Lanczos approximation).
function gammaln(z: number): number {
  const g = 7;
  const coef = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];

  if (z < 0.5) {
    return Math.log(Math.PI / Math.sin(Math.PI * z)) - gammaln(1 - z);
  }

  z -= 1;
  let x = coef[0];
  for (let i = 1; i < g + 2; i++) {
    x += coef[i] / (z + i);
  }
  const t = z + g + 0.5;
  return 0.5 * Math.log(2 * Math.PI) + (z + 0.5) * Math.log(t) - t + Math.log(x);
}

function subtractDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().split('T')[0];
}

export const correlationService = new CorrelationService();
