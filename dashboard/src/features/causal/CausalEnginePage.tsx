import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useT } from '@/lib/i18n';
import { useGraph } from '@/lib/hooks';
import { useStore } from '@/lib/store';
import { GraphCanvas } from './GraphCanvas';
import { GraphControls } from './GraphControls';
import { NodeDetailPanel } from './NodeDetailPanel';
import { CorrelationTable } from './CorrelationTable';
import type { GraphNode } from '@/lib/types';

export function CausalEnginePage() {
  const t = useT();
  const memberId = useStore((s) => s.selectedMemberId);
  const { data, isLoading } = useGraph();
  const [focusType, setFocusType] = useState<string | null>(null);
  const [selectedNode, setSelectedNode] = useState<GraphNode | null>(null);

  if (!memberId) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <p className="text-lg font-medium text-muted-foreground">{t('no_members')}</p>
        <p className="mt-1 text-sm text-muted-foreground">{t('no_members_desc')}</p>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>{t('graph_title')}</CardTitle>
          </CardHeader>
          <CardContent>
            <Skeleton className="h-[500px] w-full" />
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!data?.nodes?.length) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('graph_title')}</CardTitle>
          <CardDescription>{t('graph_no_data_desc')}</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">{t('graph_no_data')}</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>{t('graph_title')}</CardTitle>
          <CardDescription>{t('graph_desc')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <GraphControls focusType={focusType} onFocusChange={setFocusType} />
          <div className="relative">
            <GraphCanvas
              nodes={data.nodes}
              edges={data.edges}
              focusType={focusType}
              onNodeSelect={setSelectedNode}
            />
            {selectedNode && (
              <NodeDetailPanel
                node={selectedNode}
                edges={data.edges}
                nodes={data.nodes}
                onClose={() => setSelectedNode(null)}
              />
            )}
          </div>
        </CardContent>
      </Card>

      <CorrelationTable />
    </div>
  );
}
