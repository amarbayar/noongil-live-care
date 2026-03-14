import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { X } from 'lucide-react';
import type { GraphNode, GraphEdge } from '@/lib/types';

interface NodeDetailPanelProps {
  node: GraphNode;
  edges: GraphEdge[];
  nodes: GraphNode[];
  onClose: () => void;
}

export function NodeDetailPanel({ node, edges, nodes, onClose }: NodeDetailPanelProps) {
  const connectedEdges = edges.filter(
    (e) => e.source === node.id || e.target === node.id
  );

  const connectedNodes = connectedEdges.map((e) => {
    const otherId = e.source === node.id ? e.target : e.source;
    const otherNode = nodes.find((n) => n.id === otherId);
    return { edge: e, node: otherNode };
  });

  return (
    <Card className="absolute right-4 top-4 z-10 w-80 max-h-[calc(100%-2rem)] overflow-y-auto shadow-lg">
      <CardHeader className="flex flex-row items-start justify-between pb-3">
        <div>
          <CardTitle className="text-base">{node.label || node.type}</CardTitle>
          <Badge variant="secondary" className="mt-1 text-xs">
            {node.type}
          </Badge>
        </div>
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={onClose}>
          <X className="h-4 w-4" />
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* Data properties */}
        {node.data && Object.entries(node.data).length > 0 && (
          <div className="space-y-1.5">
            {Object.entries(node.data).map(([key, value]) => (
              <div key={key} className="flex justify-between text-xs">
                <span className="text-muted-foreground">{key}</span>
                <span className="font-medium">{String(value)}</span>
              </div>
            ))}
          </div>
        )}

        {/* Connected nodes */}
        {connectedNodes.length > 0 && (
          <div>
            <p className="mb-2 text-xs font-medium text-muted-foreground uppercase tracking-wider">
              Connected ({connectedNodes.length})
            </p>
            <div className="space-y-1.5">
              {connectedNodes.map(({ edge, node: other }, i) => (
                <div key={i} className="flex items-center gap-2 rounded-lg bg-muted/50 px-3 py-2 text-xs">
                  <Badge variant="outline" className="text-[10px] shrink-0">
                    {(edge.type || '').replace(/_/g, ' ')}
                  </Badge>
                  <span className="truncate">{other?.label || other?.type || '?'}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
