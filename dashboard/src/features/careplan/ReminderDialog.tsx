import { useState, useEffect } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useT } from '@/lib/i18n';
import type { CustomReminder, ReminderFormData } from '@/lib/types';

interface ReminderDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  reminder?: CustomReminder | null;
  onSubmit: (data: ReminderFormData) => void;
  loading?: boolean;
}

export function ReminderDialog({ open, onOpenChange, reminder, onSubmit, loading }: ReminderDialogProps) {
  const t = useT();
  const isEdit = !!reminder;

  const [title, setTitle] = useState('');
  const [time, setTime] = useState('09:00');
  const [note, setNote] = useState('');

  useEffect(() => {
    if (reminder) {
      setTitle(reminder.title);
      setTime(reminder.schedule?.[0] || '09:00');
      setNote(reminder.note || '');
    } else {
      setTitle('');
      setTime('09:00');
      setNote('');
    }
  }, [reminder, open]);

  const handleSubmit = () => {
    onSubmit({ title, schedule: [time], isEnabled: true, note: note || undefined });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? t('edit_reminder') : t('add_reminder')}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-4">
          <Input
            placeholder={t('reminder_placeholder')}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
          <Input
            type="time"
            value={time}
            onChange={(e) => setTime(e.target.value)}
          />
          <Input
            placeholder={t('note_placeholder')}
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            {t('cancel')}
          </Button>
          <Button onClick={handleSubmit} disabled={!title.trim() || loading}>
            {isEdit ? t('update_btn') : t('add_btn')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
