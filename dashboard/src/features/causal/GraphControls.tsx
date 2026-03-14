import { Badge } from '@/components/ui/badge';
import { useT } from '@/lib/i18n';
import { cn } from '@/lib/utils';

const NODE_TYPES = ['Symptom', 'Sleep', 'Medication', 'Trigger', 'Activity'];

const TYPE_COLORS: Record<string, string> = {
  Symptom: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  Sleep: 'bg-violet-100 text-violet-700 dark:bg-violet-900/30 dark:text-violet-400',
  Medication: 'bg-teal-100 text-teal-700 dark:bg-teal-900/30 dark:text-teal-400',
  Trigger: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  Activity: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-900/30 dark:text-cyan-400',
};

interface GraphControlsProps {
  focusType: string | null;
  onFocusChange: (type: string | null) => void;
}

export function GraphControls({ focusType, onFocusChange }: GraphControlsProps) {
  const t = useT();

  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="text-sm text-muted-foreground">{t('graph_focus')}:</span>
      <Badge
        variant={focusType === null ? 'default' : 'outline'}
        className="cursor-pointer"
        onClick={() => onFocusChange(null)}
      >
        All
      </Badge>
      {NODE_TYPES.map((type) => (
        <Badge
          key={type}
          variant="outline"
          className={cn(
            'cursor-pointer transition-colors',
            focusType === type
              ? TYPE_COLORS[type]
              : 'hover:bg-muted'
          )}
          onClick={() => onFocusChange(focusType === type ? null : type)}
        >
          {t(`legend_${type.toLowerCase()}` as string) || type}
        </Badge>
      ))}
    </div>
  );
}
