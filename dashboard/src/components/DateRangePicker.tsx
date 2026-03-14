import { useStore } from '@/lib/store';
import { useT } from '@/lib/i18n';
import { Input } from '@/components/ui/input';

export function DateRangePicker() {
  const t = useT();
  const dateRange = useStore((s) => s.dateRange);
  const setDateRange = useStore((s) => s.setDateRange);

  return (
    <div className="hidden items-center gap-2 sm:flex">
      <label className="text-xs text-muted-foreground">{t('from')}</label>
      <Input
        type="date"
        value={dateRange.start}
        onChange={(e) => setDateRange({ ...dateRange, start: e.target.value })}
        className="h-8 w-32 text-xs"
      />
      <label className="text-xs text-muted-foreground">{t('to')}</label>
      <Input
        type="date"
        value={dateRange.end}
        onChange={(e) => setDateRange({ ...dateRange, end: e.target.value })}
        className="h-8 w-32 text-xs"
      />
    </div>
  );
}
