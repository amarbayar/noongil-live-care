import { useState } from 'react';
import { useT } from '@/lib/i18n';
import { useStore } from '@/lib/store';
import { useReminders, useCreateReminder, useUpdateReminder, useDeleteReminder } from '@/lib/hooks';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { ReminderDialog } from './ReminderDialog';
import { Plus, Clock, Pencil, Trash2, Pill } from 'lucide-react';
import type { CustomReminder, ReminderFormData } from '@/lib/types';

export function CarePlanPage() {
  const t = useT();
  const memberId = useStore((s) => s.selectedMemberId);
  const { data, isLoading } = useReminders();
  const createReminder = useCreateReminder();
  const updateReminder = useUpdateReminder();
  const deleteReminder = useDeleteReminder();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingReminder, setEditingReminder] = useState<CustomReminder | null>(null);

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
        <Skeleton className="h-10 w-48" />
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Skeleton className="h-64 w-full rounded-2xl" />
          <Skeleton className="h-64 w-full rounded-2xl" />
        </div>
      </div>
    );
  }

  const customReminders = data?.customReminders ?? [];
  const medications = data?.medications ?? [];

  const handleSubmit = (formData: ReminderFormData) => {
    if (editingReminder) {
      updateReminder.mutate(
        { id: editingReminder.id, data: formData },
        { onSuccess: () => { setDialogOpen(false); setEditingReminder(null); } }
      );
    } else {
      createReminder.mutate(formData, {
        onSuccess: () => setDialogOpen(false),
      });
    }
  };

  const handleEdit = (r: CustomReminder) => {
    setEditingReminder(r);
    setDialogOpen(true);
  };

  const handleToggle = (id: string, isEnabled: boolean) => {
    updateReminder.mutate({ id, data: { isEnabled } as Partial<ReminderFormData> });
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">{t('care_plan_title')}</h2>
          <p className="text-sm text-muted-foreground">{t('care_plan_desc')}</p>
        </div>
        <Button
          onClick={() => { setEditingReminder(null); setDialogOpen(true); }}
          className="gap-2"
        >
          <Plus className="h-4 w-4" />
          {t('add_reminder')}
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Custom Reminders */}
        <Card>
          <CardHeader>
            <CardTitle>{t('custom_reminders')}</CardTitle>
          </CardHeader>
          <CardContent>
            {customReminders.length === 0 ? (
              <p className="text-sm text-muted-foreground">{t('no_reminders')}</p>
            ) : (
              <div className="space-y-3">
                {customReminders.map((r) => (
                  <div
                    key={r.id}
                    className="flex items-center justify-between rounded-xl border border-border bg-muted/30 p-4 transition-colors hover:bg-muted/50"
                  >
                    <div className="flex items-center gap-3">
                      <Switch
                        checked={r.isEnabled}
                        onCheckedChange={(checked) => handleToggle(r.id, checked)}
                      />
                      <div>
                        <p className="text-sm font-medium">{r.title}</p>
                        <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
                          <Clock className="h-3 w-3" />
                          <span>{r.schedule?.join(', ') || '--'}</span>
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center gap-1">
                      <Badge variant={r.isEnabled ? 'secondary' : 'outline'} className="text-[10px]">
                        {r.isEnabled ? t('enabled') : t('paused')}
                      </Badge>
                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleEdit(r)}>
                        <Pencil className="h-3 w-3" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7 text-destructive"
                        onClick={() => deleteReminder.mutate(r.id)}
                      >
                        <Trash2 className="h-3 w-3" />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Medications */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Pill className="h-4 w-4" style={{ color: 'var(--color-med)' }} />
              {t('active_meds')}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {medications.length === 0 ? (
              <p className="text-sm text-muted-foreground">{t('no_meds')}</p>
            ) : (
              <div className="space-y-3">
                {medications.map((med) => (
                  <div key={med.id} className="rounded-xl border border-border bg-muted/30 p-4">
                    <p className="text-sm font-medium">{med.name || med.id}</p>
                    {med.dosage && (
                      <p className="mt-1 text-xs text-muted-foreground">{med.dosage}</p>
                    )}
                    {med.schedule && (
                      <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
                        <Clock className="h-3 w-3" />
                        <span>{med.schedule.join(', ')}</span>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <ReminderDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        reminder={editingReminder}
        onSubmit={handleSubmit}
        loading={createReminder.isPending || updateReminder.isPending}
      />
    </div>
  );
}
