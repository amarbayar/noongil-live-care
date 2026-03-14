import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

interface MetricCardProps {
  label: string;
  value: string | number;
  accent?: string;
  accentBg?: string;
  loading?: boolean;
  icon?: React.ReactNode;
}

export function MetricCard({ label, value, accent, accentBg, loading, icon }: MetricCardProps) {
  if (loading) {
    return (
      <Card className="p-5">
        <Skeleton className="h-4 w-20 mb-3" />
        <Skeleton className="h-8 w-16" />
      </Card>
    );
  }

  return (
    <Card
      className={cn('p-5 transition-shadow hover:shadow-md')}
      style={{ borderLeftColor: accent, borderLeftWidth: accent ? 3 : undefined }}
    >
      <div className="flex items-start justify-between">
        <div>
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
            {label}
          </p>
          <p className="mt-2 text-3xl font-bold tracking-tight" style={{ color: accent }}>
            {value}
          </p>
        </div>
        {icon && (
          <div
            className="flex h-10 w-10 items-center justify-center rounded-xl"
            style={{ backgroundColor: accentBg }}
          >
            {icon}
          </div>
        )}
      </div>
    </Card>
  );
}
