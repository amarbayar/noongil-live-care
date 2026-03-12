import { graphService, type DayAggregate, type CorrelationEdge } from './graph.service.js';

export interface ReportOutput {
  userId: string;
  startDate: string;
  endDate: string;
  checkInCount: number;
  executiveSummary: string;
  moodTimeSeries: Array<{ date: string; value: number }>;
  sleepTimeSeries: Array<{ date: string; value: number }>;
  symptomTimeSeries: Record<string, Array<{ date: string; value: number }>>;
  overallAdherencePercent: number | null;
  perMedicationAdherence: Array<{ name: string; takenCount: number; totalCount: number }>;
  correlations: CorrelationEdge[];
  concerns: Array<{ theme: string; count: number; quotes: string[] }>;
}

export class ReportService {
  async generateReport(
    userId: string,
    startDate: string,
    endDate: string
  ): Promise<ReportOutput> {
    const [graphData, correlations] = await Promise.all([
      graphService.getGraphData(userId, startDate, endDate),
      graphService.getCorrelations(userId),
    ]);

    const moodTimeSeries = extractTimeSeries(graphData, 'avgMood');
    const sleepTimeSeries = extractTimeSeries(graphData, 'avgSleep');
    const symptomTimeSeries = extractSymptomTimeSeries(graphData);
    const { overallPercent, perMedication } = computeAdherence(graphData);
    const executiveSummary = buildExecutiveSummary(
      graphData, moodTimeSeries, sleepTimeSeries, overallPercent
    );

    return {
      userId,
      startDate,
      endDate,
      checkInCount: graphData.length,
      executiveSummary,
      moodTimeSeries,
      sleepTimeSeries,
      symptomTimeSeries,
      overallAdherencePercent: overallPercent,
      perMedicationAdherence: perMedication,
      correlations,
      concerns: [], // Populated by Gemini transcript analysis (future)
    };
  }
}

function extractTimeSeries(
  data: DayAggregate[],
  field: 'avgMood' | 'avgSleep'
): Array<{ date: string; value: number }> {
  return data
    .filter((d) => d[field] != null)
    .map((d) => ({ date: d.date, value: d[field]! }));
}

function extractSymptomTimeSeries(
  data: DayAggregate[]
): Record<string, Array<{ date: string; value: number }>> {
  const result: Record<string, Array<{ date: string; value: number }>> = {};

  for (const day of data) {
    for (const sym of day.symptoms) {
      if (!sym.type) continue;
      if (!result[sym.type]) result[sym.type] = [];
      result[sym.type].push({
        date: day.date,
        value: (sym.severity as number) ?? 0,
      });
    }
  }

  return result;
}

function computeAdherence(data: DayAggregate[]): {
  overallPercent: number | null;
  perMedication: Array<{ name: string; takenCount: number; totalCount: number }>;
} {
  let totalTaken = 0;
  let totalDoses = 0;

  for (const day of data) {
    totalTaken += day.medsTaken;
    totalDoses += day.medsTotal;
  }

  return {
    overallPercent: totalDoses > 0 ? (totalTaken / totalDoses) * 100 : null,
    perMedication: [], // Per-med breakdown requires additional query (future)
  };
}

function buildExecutiveSummary(
  data: DayAggregate[],
  moodSeries: Array<{ date: string; value: number }>,
  sleepSeries: Array<{ date: string; value: number }>,
  adherencePercent: number | null
): string {
  const parts: string[] = [];
  const dayCount = data.length;

  parts.push(`Report covers ${dayCount} day${dayCount !== 1 ? 's' : ''} of data.`);

  if (moodSeries.length > 0) {
    const avg = moodSeries.reduce((s, p) => s + p.value, 0) / moodSeries.length;
    const trend = computeTrend(moodSeries.map((p) => p.value));
    parts.push(`Average mood: ${avg.toFixed(1)}/5 (${trend}).`);
  }

  if (sleepSeries.length > 0) {
    const avg = sleepSeries.reduce((s, p) => s + p.value, 0) / sleepSeries.length;
    parts.push(`Average sleep: ${avg.toFixed(1)} hours/night.`);
  }

  if (adherencePercent != null) {
    parts.push(`Medication adherence: ${Math.round(adherencePercent)}%.`);
  }

  return parts.join(' ');
}

function computeTrend(values: number[]): string {
  if (values.length < 2) return 'stable';
  const half = Math.floor(values.length / 2);
  const first = values.slice(0, Math.max(half, 1));
  const second = values.slice(-Math.max(half, 1));
  const firstAvg = first.reduce((s, v) => s + v, 0) / first.length;
  const secondAvg = second.reduce((s, v) => s + v, 0) / second.length;

  if (secondAvg > firstAvg + 0.3) return 'improving';
  if (secondAvg < firstAvg - 0.3) return 'declining';
  return 'stable';
}

export const reportService = new ReportService();
