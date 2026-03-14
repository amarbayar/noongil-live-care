import { useT } from '@/lib/i18n';
import { useTimeSeries, useTriggers } from '@/lib/hooks';
import { useStore } from '@/lib/store';
import { MetricCard } from '@/components/MetricCard';
import { WellnessTrends } from './WellnessTrends';
import { SymptomTrends } from './SymptomTrends';
import { ConsistencyHeatmap } from './ConsistencyHeatmap';
import { TriggerBars } from './TriggerBars';
import { CausalSummary } from './CausalSummary';
import { Activity, Moon, Pill, AlertTriangle } from 'lucide-react';

export function CheckInsPage() {
  const t = useT();
  const memberId = useStore((s) => s.selectedMemberId);
  const { data: ts, isLoading: tsLoading } = useTimeSeries();
  const { data: triggers, isLoading: trigLoading } = useTriggers();

  if (!memberId) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <p className="text-lg font-medium text-muted-foreground">{t('no_members')}</p>
        <p className="mt-1 text-sm text-muted-foreground">{t('no_members_desc')}</p>
      </div>
    );
  }

  const loading = tsLoading || trigLoading;

  // Compute metrics
  const validMoods = ts?.moodSeries.filter((v): v is number => v !== null) ?? [];
  const avgMood = validMoods.length > 0
    ? (validMoods.reduce((a, b) => a + b, 0) / validMoods.length).toFixed(1)
    : '--';

  const validSleep = ts?.sleepHoursSeries.filter((v): v is number => v !== null) ?? [];
  const avgSleep = validSleep.length > 0
    ? (validSleep.reduce((a, b) => a + b, 0) / validSleep.length).toFixed(1)
    : '--';

  const validMeds = ts?.medAdherenceSeries?.filter((v): v is number => v !== null) ?? [];
  const medAdherence = validMeds.length > 0
    ? Math.round((validMeds.reduce((a, b) => a + b, 0) / validMeds.length) * 100) + '%'
    : '--';

  const totalTriggers = triggers?.reduce((sum, t) => sum + t.count, 0) ?? 0;
  const daysInRange = ts?.dates?.length ?? 0;

  return (
    <div className="space-y-6">
      {/* Metric cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          label={t('avg_mood')}
          value={avgMood}
          accent="var(--color-mood)"
          accentBg="var(--color-mood-bg)"
          loading={loading}
          icon={<Activity className="h-5 w-5" style={{ color: 'var(--color-mood)' }} />}
        />
        <MetricCard
          label={t('avg_sleep')}
          value={avgSleep !== '--' ? `${avgSleep}h` : '--'}
          accent="var(--color-sleep)"
          accentBg="var(--color-sleep-bg)"
          loading={loading}
          icon={<Moon className="h-5 w-5" style={{ color: 'var(--color-sleep)' }} />}
        />
        <MetricCard
          label={t('med_adherence')}
          value={medAdherence}
          accent="var(--color-med)"
          accentBg="var(--color-med-bg)"
          loading={loading}
          icon={<Pill className="h-5 w-5" style={{ color: 'var(--color-med)' }} />}
        />
        <MetricCard
          label={`${t('days_in_range')}`}
          value={loading ? '--' : `${daysInRange}`}
          accent="var(--color-trigger)"
          accentBg="var(--color-trigger-bg)"
          loading={loading}
          icon={<AlertTriangle className="h-5 w-5" style={{ color: 'var(--color-trigger)' }} />}
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
        <WellnessTrends />
        <SymptomTrends />
      </div>

      <ConsistencyHeatmap />

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
        <TriggerBars />
        <CausalSummary />
      </div>
    </div>
  );
}
