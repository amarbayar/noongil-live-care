import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useT } from '@/lib/i18n';
import { useTimeSeries } from '@/lib/hooks';
import { cn } from '@/lib/utils';

export function ConsistencyHeatmap() {
  const t = useT();
  const { data, isLoading } = useTimeSeries();

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('consistency_title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-32 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!data?.dates?.length) return null;

  const daysWithData = data.dates.filter(
    (_, i) => data.moodSeries[i] !== null || data.sleepHoursSeries[i] !== null
  ).length;
  const totalDays = data.dates.length;
  const missingDays = totalDays - daysWithData;
  const coverage = totalDays > 0 ? Math.round((daysWithData / totalDays) * 100) : 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('consistency_title')}</CardTitle>
        <CardDescription>{t('consistency_desc')}</CardDescription>
      </CardHeader>
      <CardContent>
        {/* Stats row */}
        <div className="mb-4 grid grid-cols-4 gap-3 text-center">
          <div>
            <p className="text-2xl font-bold">{totalDays}</p>
            <p className="text-xs text-muted-foreground">{t('days_monitored')}</p>
          </div>
          <div>
            <p className="text-2xl font-bold text-mood">{daysWithData}</p>
            <p className="text-xs text-muted-foreground">{t('days_with_checkins')}</p>
          </div>
          <div>
            <p className="text-2xl font-bold text-destructive">{missingDays}</p>
            <p className="text-xs text-muted-foreground">{t('missing_days')}</p>
          </div>
          <div>
            <p className="text-2xl font-bold">{coverage}%</p>
            <p className="text-xs text-muted-foreground">{t('coverage')}</p>
          </div>
        </div>

        {/* Heatmap grid */}
        <div className="flex flex-wrap gap-1">
          {data.dates.map((date, i) => {
            const hasData = data.moodSeries[i] !== null || data.sleepHoursSeries[i] !== null;
            return (
              <div
                key={date}
                title={date}
                className={cn(
                  'h-4 w-4 rounded-sm transition-colors',
                  hasData ? 'bg-primary/80' : 'bg-muted'
                )}
              />
            );
          })}
        </div>

        {missingDays === 0 && (
          <p className="mt-3 text-sm text-green-600">{t('no_missed')}</p>
        )}
      </CardContent>
    </Card>
  );
}
