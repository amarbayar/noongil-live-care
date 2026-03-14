export interface Member {
  memberId: string;
  memberName?: string;
  permissions: string[];
}

export interface MeResponse {
  members: Member[];
  selfId: string | null;
}

export interface GraphNode {
  id: string;
  label: string;
  type: string;
  data: Record<string, unknown>;
}

export interface GraphEdge {
  source: string;
  target: string;
  type: string;
  data: Record<string, unknown>;
}

// API returns {symptom, severity, causes[]}
export interface CausalExplanation {
  symptom?: string;
  severity?: number;
  causes?: string[];
  // Fallback fields
  explanation?: string;
  confidence?: number;
  factors?: string[];
}

export interface GraphResponse {
  nodes: GraphNode[];
  edges: GraphEdge[];
  causalExplanations: CausalExplanation[];
}

export interface TimeSeriesResponse {
  dates: string[];
  moodSeries: (number | null)[];
  sleepHoursSeries: (number | null)[];
  sleepQualitySeries: (number | null)[];
  medAdherenceSeries: (number | null)[];
  symptomSeries: Record<string, (number | null)[]>;
}

export interface Correlation {
  sourceLabel: string;
  targetLabel: string;
  correlation: number;
  lag: number;
  pValue: number;
  sampleSize: number;
}

export interface TriggerData {
  trigger: string;
  count: number;
  avgSeverity: number;
}

// Reminders API returns this wrapper, not a plain array
export interface RemindersResponse {
  medications: MedicationItem[];
  customReminders: CustomReminder[];
  checkInSchedule: Record<string, unknown> | null;
}

export interface MedicationItem {
  id: string;
  type: 'medication';
  name?: string;
  dosage?: string;
  schedule?: string[];
  [key: string]: unknown;
}

export interface CustomReminder {
  id: string;
  type: 'custom';
  title: string;
  note?: string | null;
  schedule?: string[];
  isEnabled: boolean;
  createdBy?: {
    userId: string;
    name: string | null;
    role: string;
  };
  createdAt?: string;
}

export interface ReminderFormData {
  title: string;
  note?: string;
  schedule: string[];
  isEnabled: boolean;
}

export type Page = 'checkins' | 'causal' | 'care-plan' | 'messages';
