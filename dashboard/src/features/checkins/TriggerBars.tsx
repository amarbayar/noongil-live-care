import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useT } from '@/lib/i18n';
import { useTriggers } from '@/lib/hooks';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts';

export function TriggerBars() {
  const t = useT();
  const { data, isLoading } = useTriggers();

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('triggers_title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-48 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!data?.length) return null;

  const sorted = [...data].sort((a, b) => b.count - a.count).slice(0, 10);

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('triggers_title')}</CardTitle>
        <CardDescription>{t('triggers_desc')}</CardDescription>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={Math.max(200, sorted.length * 36)}>
          <BarChart layout="vertical" data={sorted} margin={{ left: 80 }}>
            <XAxis type="number" tick={{ fontSize: 11 }} />
            <YAxis
              type="category"
              dataKey="trigger"
              tick={{ fontSize: 11 }}
              width={80}
            />
            <Tooltip
              contentStyle={{
                borderRadius: 12,
                border: '1px solid var(--color-border)',
                backgroundColor: 'var(--color-card)',
                color: 'var(--color-card-foreground)',
              }}
              formatter={(value, name) => {
                if (name === 'count') return [String(value), t('count')];
                return [Number(value).toFixed(1), t('avg_severity')];
              }}
            />
            <Bar dataKey="count" radius={[0, 6, 6, 0]}>
              {sorted.map((_, i) => (
                <Cell key={i} fill={`hsl(${35 + i * 5}, 90%, ${55 - i * 2}%)`} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}
