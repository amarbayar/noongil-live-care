import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { useT } from '@/lib/i18n';
import { useCausal } from '@/lib/hooks';

export function CausalSummary() {
  const t = useT();
  const { data, isLoading } = useCausal();

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('causal_title')}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!data?.length) return null;

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('causal_title')}</CardTitle>
        <CardDescription>{t('causal_desc')}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {data.map((item, i) => {
          // API returns {symptom, severity, causes[]} or {explanation, confidence, factors[]}
          const symptom = item.symptom ?? item.explanation ?? '';
          const causes = item.causes ?? item.factors ?? [];
          const severity = item.severity;
          const confidence = item.confidence;

          return (
            <div
              key={i}
              className="rounded-xl border border-border bg-muted/50 p-4"
            >
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold text-destructive">{symptom}</span>
                {severity != null && (
                  <Badge variant="outline" className="text-xs">
                    severity {severity}
                  </Badge>
                )}
                {confidence != null && (
                  <Badge variant="outline" className="text-xs">
                    {Math.round(confidence * 100)}% confidence
                  </Badge>
                )}
              </div>
              {causes.length > 0 && (
                <div className="mt-2 flex flex-wrap gap-2">
                  {causes.map((cause: string, j: number) => (
                    <Badge key={j} variant="secondary" className="text-xs">
                      {cause}
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}
