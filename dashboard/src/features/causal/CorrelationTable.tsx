import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useT } from '@/lib/i18n';
import { useCorrelations } from '@/lib/hooks';
import { cn } from '@/lib/utils';
import type { Correlation } from '@/lib/types';

type SortKey = keyof Pick<Correlation, 'correlation' | 'pValue' | 'sampleSize'>;

export function CorrelationTable() {
  const t = useT();
  const { data, isLoading } = useCorrelations();
  const [sortKey, setSortKey] = useState<SortKey>('correlation');
  const [sortAsc, setSortAsc] = useState(false);

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('correlations')}</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-48 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!data?.length) return null;

  const sorted = [...data].sort((a, b) => {
    const diff = (a[sortKey] as number) - (b[sortKey] as number);
    return sortAsc ? diff : -diff;
  });

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortAsc(!sortAsc);
    } else {
      setSortKey(key);
      setSortAsc(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('correlations')}</CardTitle>
        <CardDescription>{t('correlation_table_desc')}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-left">
                <th className="py-2 pr-4 font-medium text-muted-foreground">{t('source')}</th>
                <th className="py-2 pr-4 font-medium text-muted-foreground">{t('target')}</th>
                <th
                  className="cursor-pointer py-2 pr-4 font-medium text-muted-foreground hover:text-foreground"
                  onClick={() => handleSort('correlation')}
                >
                  {t('correlation_val')} {sortKey === 'correlation' && (sortAsc ? '↑' : '↓')}
                </th>
                <th className="py-2 pr-4 font-medium text-muted-foreground">{t('lag')}</th>
                <th
                  className="cursor-pointer py-2 pr-4 font-medium text-muted-foreground hover:text-foreground"
                  onClick={() => handleSort('pValue')}
                >
                  {t('p_value')} {sortKey === 'pValue' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  className="cursor-pointer py-2 font-medium text-muted-foreground hover:text-foreground"
                  onClick={() => handleSort('sampleSize')}
                >
                  {t('sample_size')} {sortKey === 'sampleSize' && (sortAsc ? '↑' : '↓')}
                </th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((row, i) => (
                <tr key={i} className="border-b border-border/50 hover:bg-muted/50 transition-colors">
                  <td className="py-2 pr-4">{row.sourceLabel}</td>
                  <td className="py-2 pr-4">{row.targetLabel}</td>
                  <td className="py-2 pr-4">
                    <span
                      className={cn(
                        'font-mono font-medium',
                        row.correlation > 0 ? 'text-green-600' : 'text-red-600'
                      )}
                    >
                      {row.correlation > 0 ? '+' : ''}{row.correlation.toFixed(3)}
                    </span>
                  </td>
                  <td className="py-2 pr-4 text-muted-foreground">{row.lag}d</td>
                  <td className="py-2 pr-4 font-mono text-muted-foreground">
                    {row.pValue < 0.001 ? '<0.001' : row.pValue.toFixed(3)}
                  </td>
                  <td className="py-2 text-muted-foreground">{row.sampleSize}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  );
}
