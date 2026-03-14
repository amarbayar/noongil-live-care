import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from './api';
import { useStore } from './store';
import type {
  MeResponse,
  GraphResponse,
  TimeSeriesResponse,
  Correlation,
  TriggerData,
  CausalExplanation,
  RemindersResponse,
  ReminderFormData,
} from './types';

export function useMe() {
  return useQuery({
    queryKey: ['me'],
    queryFn: () => api.get<MeResponse>('/api/dashboard/me'),
  });
}

function useDateParams() {
  const memberId = useStore((s) => s.selectedMemberId);
  const dateRange = useStore((s) => s.dateRange);
  return { memberId, ...dateRange };
}

export function useTimeSeries() {
  const { memberId, start, end } = useDateParams();
  return useQuery({
    queryKey: ['timeSeries', memberId, start, end],
    queryFn: () =>
      api.get<TimeSeriesResponse>(
        `/api/dashboard/time-series?userId=${memberId}&start=${start}&end=${end}`
      ),
    enabled: !!memberId,
  });
}

export function useGraph() {
  const { memberId, start, end } = useDateParams();
  return useQuery({
    queryKey: ['graph', memberId, start, end],
    queryFn: () =>
      api.get<GraphResponse>(
        `/api/dashboard/graph?userId=${memberId}&start=${start}&end=${end}`
      ),
    enabled: !!memberId,
  });
}

export function useCorrelations() {
  const { memberId, start, end } = useDateParams();
  return useQuery({
    queryKey: ['correlations', memberId],
    queryFn: () =>
      api.get<Correlation[]>(
        `/api/dashboard/correlations?userId=${memberId}&start=${start}&end=${end}`
      ),
    enabled: !!memberId,
  });
}

export function useTriggers() {
  const { memberId, start, end } = useDateParams();
  return useQuery({
    queryKey: ['triggers', memberId, start, end],
    queryFn: () =>
      api.get<TriggerData[]>(
        `/api/dashboard/triggers?userId=${memberId}&start=${start}&end=${end}`
      ),
    enabled: !!memberId,
  });
}

export function useCausal() {
  const { memberId, start, end } = useDateParams();
  return useQuery({
    queryKey: ['causal', memberId, start, end],
    queryFn: () =>
      api.get<CausalExplanation[]>(
        `/api/dashboard/causal?userId=${memberId}&start=${start}&end=${end}`
      ),
    enabled: !!memberId,
  });
}

export function useReminders() {
  const memberId = useStore((s) => s.selectedMemberId);
  return useQuery({
    queryKey: ['reminders', memberId],
    queryFn: () =>
      api.get<RemindersResponse>(`/api/caregiver/members/${memberId}/reminders`),
    enabled: !!memberId,
  });
}

export function useCreateReminder() {
  const queryClient = useQueryClient();
  const memberId = useStore((s) => s.selectedMemberId);
  return useMutation({
    mutationFn: (data: ReminderFormData) =>
      api.post(`/api/caregiver/members/${memberId}/reminders`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reminders', memberId] });
    },
  });
}

export function useUpdateReminder() {
  const queryClient = useQueryClient();
  const memberId = useStore((s) => s.selectedMemberId);
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<ReminderFormData> }) =>
      api.put(`/api/caregiver/members/${memberId}/reminders/${id}`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reminders', memberId] });
    },
  });
}

export function useDeleteReminder() {
  const queryClient = useQueryClient();
  const memberId = useStore((s) => s.selectedMemberId);
  return useMutation({
    mutationFn: (id: string) =>
      api.delete(`/api/caregiver/members/${memberId}/reminders/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reminders', memberId] });
    },
  });
}

export function useSendVoiceMessage() {
  const memberId = useStore((s) => s.selectedMemberId);
  return useMutation({
    mutationFn: async ({ audioBase64, durationSeconds }: { audioBase64: string; durationSeconds: number }) => {
      return api.post(`/api/caregiver/members/${memberId}/voice-messages`, {
        audioBase64,
        mimeType: 'audio/webm',
        durationSeconds,
      });
    },
  });
}
