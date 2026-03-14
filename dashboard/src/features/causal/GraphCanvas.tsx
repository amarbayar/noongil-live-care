import { useEffect, useRef, useCallback } from 'react';
import cytoscape from 'cytoscape';
import dagre from 'cytoscape-dagre';
import type { GraphNode, GraphEdge } from '@/lib/types';
import { useStore } from '@/lib/store';
import '@/styles/graph.css';

cytoscape.use(dagre);

const TYPE_COLORS: Record<string, string> = {
  Symptom: '#dc2626',
  SymptomEntry: '#dc2626',
  Sleep: '#7c3aed',
  SleepEntry: '#7c3aed',
  Medication: '#0f766e',
  MedicationDose: '#0f766e',
  Trigger: '#d97706',
  Activity: '#14b8a6',
  Day: '#64748b',
  CheckIn: '#3b82f6',
  MoodEntry: '#3b82f6',
  Member: '#f97316',
  PatternMetric: '#8b5cf6',
};

function getNodeColor(type: string): string {
  return TYPE_COLORS[type] || '#64748b';
}

/** Maps display filter names to all matching node type labels. */
const TYPE_ALIASES: Record<string, string[]> = {
  Symptom: ['Symptom', 'SymptomEntry'],
  Sleep: ['Sleep', 'SleepEntry'],
  Medication: ['Medication', 'MedicationDose'],
  Trigger: ['Trigger'],
  Activity: ['Activity', 'ActivityEvent'],
};

function matchesFocusType(nodeType: string, focusType: string): boolean {
  const aliases = TYPE_ALIASES[focusType];
  return aliases ? aliases.includes(nodeType) : nodeType === focusType;
}

interface GraphCanvasProps {
  nodes: GraphNode[];
  edges: GraphEdge[];
  focusType: string | null;
  onNodeSelect: (node: GraphNode | null) => void;
}

export function GraphCanvas({ nodes, edges, focusType, onNodeSelect }: GraphCanvasProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const cyRef = useRef<cytoscape.Core | null>(null);
  const theme = useStore((s) => s.theme);

  // Deduplicate nodes by id
  const uniqueNodes = Array.from(new Map(nodes.map((n) => [n.id, n])).values());

  // Filter by focus type
  const filteredNodes = focusType
    ? uniqueNodes.filter((n) => {
        if (matchesFocusType(n.type, focusType)) return true;
        return edges.some(
          (e) =>
            (e.source === n.id && uniqueNodes.some((nn) => nn.id === e.target && matchesFocusType(nn.type, focusType))) ||
            (e.target === n.id && uniqueNodes.some((nn) => nn.id === e.source && matchesFocusType(nn.type, focusType)))
        );
      })
    : uniqueNodes;

  const filteredNodeIds = new Set(filteredNodes.map((n) => n.id));
  const filteredEdges = edges.filter(
    (e) => filteredNodeIds.has(e.source) && filteredNodeIds.has(e.target)
  );

  // Deduplicate edges
  const uniqueEdges = Array.from(
    new Map(filteredEdges.map((e) => [`${e.source}-${e.type}-${e.target}`, e])).values()
  );

  const buildGraph = useCallback(() => {
    if (!containerRef.current) return;

    const textColor = theme === 'dark' ? '#e2e8f0' : '#1e293b';
    const edgeColor = theme === 'dark' ? '#475569' : '#94a3b8';

    const cy = cytoscape({
      container: containerRef.current,
      elements: [
        ...filteredNodes.map((n) => ({
          data: {
            id: n.id,
            label: n.label || n.type,
            nodeData: n,
          },
        })),
        ...uniqueEdges.map((e, i) => ({
          data: {
            id: `e${i}`,
            source: e.source,
            target: e.target,
            label: (e.type || '').replace(/_/g, ' '),
          },
        })),
      ],
      style: [
        {
          selector: 'node',
          style: {
            label: 'data(label)',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': 9,
            'text-wrap': 'wrap',
            'text-max-width': '60px',
            color: '#fff',
            'text-outline-color': (ele: cytoscape.NodeSingular) => {
              const nd = ele.data('nodeData') as GraphNode;
              return getNodeColor(nd?.type);
            },
            'text-outline-width': 2,
            'background-color': (ele: cytoscape.NodeSingular) => {
              const nd = ele.data('nodeData') as GraphNode;
              return getNodeColor(nd?.type);
            },
            width: 50,
            height: 50,
            'border-width': 3,
            'border-color': theme === 'dark' ? '#1c2236' : '#ffffff',
          } as cytoscape.Css.Node,
        },
        {
          selector: 'edge',
          style: {
            label: 'data(label)',
            'font-size': 8,
            color: textColor,
            'text-rotation': 'autorotate',
            'text-margin-y': -8,
            width: 1.5,
            'line-color': edgeColor,
            'target-arrow-color': edgeColor,
            'target-arrow-shape': 'triangle',
            'curve-style': 'bezier',
            'arrow-scale': 0.8,
          } as cytoscape.Css.Edge,
        },
        {
          selector: 'node:selected',
          style: {
            'border-width': 4,
            'border-color': '#7c3aed',
          } as cytoscape.Css.Node,
        },
      ],
      layout: {
        name: 'dagre',
        rankDir: 'TB',
        nodeSep: 60,
        rankSep: 80,
        padding: 30,
      } as cytoscape.LayoutOptions,
      userZoomingEnabled: true,
      userPanningEnabled: true,
      boxSelectionEnabled: false,
    });

    cy.on('tap', 'node', (evt) => {
      const nodeData = evt.target.data('nodeData') as GraphNode;
      onNodeSelect(nodeData);
    });

    cy.on('tap', (evt) => {
      if (evt.target === cy) {
        onNodeSelect(null);
      }
    });

    cyRef.current = cy;
  }, [filteredNodes, uniqueEdges, theme, onNodeSelect]);

  useEffect(() => {
    buildGraph();
    return () => {
      cyRef.current?.destroy();
    };
  }, [buildGraph]);

  return <div ref={containerRef} className="graph-container bg-card rounded-xl border border-border" />;
}
