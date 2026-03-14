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
} from 'recharts';

const SYMPTOM_COLORS = [
  '#ef4444', '#f97316', '#eab308', '#22c55e', '#06b6d4',
  '#8b5cf6', '#ec4899', '#64748b',
];

export function SymptomTrends() {
  const t = useT();
  const { data, isLoading } = useTimeSeries();

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('symptom_title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-48 w-full" />
        </CardContent>
      </Card>
    );
  }

  const symptomSeries = data?.symptomSeries;
  if (!symptomSeries || Object.keys(symptomSeries).length === 0) return null;

  const symptomNames = Object.keys(symptomSeries);
  const chartData = (data?.dates ?? []).map((date, i) => {
    const row: Record<string, unknown> = { date: date.slice(5) };
    for (const name of symptomNames) {
      row[name] = symptomSeries[name][i];
    }
    return row;
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('symptom_title')}</CardTitle>
        <CardDescription>{t('symptom_desc')}</CardDescription>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={220}>
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
            {symptomNames.map((name, idx) => (
              <Line
                key={name}
                type="monotone"
                dataKey={name}
                name={name}
                stroke={SYMPTOM_COLORS[idx % SYMPTOM_COLORS.length]}
                strokeWidth={2}
                dot={false}
                connectNulls
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}
