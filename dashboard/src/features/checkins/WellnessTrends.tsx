import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useT } from '@/lib/i18n';
import { useTimeSeries } from '@/lib/hooks';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts';

export function WellnessTrends() {
  const t = useT();
  const { data, isLoading } = useTimeSeries();

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('trends_title')}</CardTitle>
          <CardDescription>{t('trends_desc')}</CardDescription>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-64 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!data?.dates?.length) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('trends_title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">{t('no_data')}</p>
        </CardContent>
      </Card>
    );
  }

  const chartData = data.dates.map((date, i) => ({
    date: date.slice(5),
    mood: data.moodSeries[i],
    sleep: data.sleepHoursSeries[i],
    meds: data.medAdherenceSeries?.[i],
  }));

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('trends_title')}</CardTitle>
        <CardDescription>{t('trends_desc')}</CardDescription>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={280}>
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
            <XAxis dataKey="date" tick={{ fontSize: 11 }} />
            <YAxis tick={{ fontSize: 11 }} />
            <Tooltip
              contentStyle={{
                borderRadius: 12,
                border: '1px solid var(--color-border)',
                backgroundColor: 'var(--color-card)',
                color: 'var(--color-card-foreground)',
              }}
            />
            <Legend />
            <Line
              type="monotone"
              dataKey="mood"
              name={t('mood')}
              stroke="var(--color-mood)"
              strokeWidth={2}
              dot={false}
              connectNulls
            />
            <Line
              type="monotone"
              dataKey="sleep"
              name={t('sleep')}
              stroke="var(--color-sleep)"
              strokeWidth={2}
              dot={false}
              connectNulls
            />
            {data.medAdherenceSeries && (
              <Line
                type="monotone"
                dataKey="meds"
                name={t('meds')}
                stroke="var(--color-med)"
                strokeWidth={2}
                dot={false}
                connectNulls
              />
            )}
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}
