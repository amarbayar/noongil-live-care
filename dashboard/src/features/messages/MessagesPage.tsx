import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { useT } from '@/lib/i18n';
import { useStore } from '@/lib/store';
import { useSendVoiceMessage } from '@/lib/hooks';
import { VoiceRecorder } from './VoiceRecorder';
import { CheckCircle } from 'lucide-react';

interface SentMessage {
  id: string;
  durationSeconds: number;
  sentAt: string;
}

export function MessagesPage() {
  const t = useT();
  const memberId = useStore((s) => s.selectedMemberId);
  const sendVoice = useSendVoiceMessage();
  const [sentMessages, setSentMessages] = useState<SentMessage[]>([]);
  const [sentSuccess, setSentSuccess] = useState(false);

  if (!memberId) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <p className="text-lg font-medium text-muted-foreground">{t('no_members')}</p>
        <p className="mt-1 text-sm text-muted-foreground">{t('no_members_desc')}</p>
      </div>
    );
  }

  const handleSend = (data: { audioBase64: string; durationSeconds: number }) => {
    sendVoice.mutate(data, {
      onSuccess: (result: unknown) => {
        const res = result as { id?: string };
        setSentMessages((prev) => [
          {
            id: res?.id || String(Date.now()),
            durationSeconds: data.durationSeconds,
            sentAt: new Date().toISOString(),
          },
          ...prev,
        ]);
        setSentSuccess(true);
        setTimeout(() => setSentSuccess(false), 3000);
      },
    });
  };

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <Card>
        <CardHeader className="text-center">
          <CardTitle>{t('voice_title')}</CardTitle>
          <CardDescription>{t('voice_desc')}</CardDescription>
        </CardHeader>
        <CardContent>
          <VoiceRecorder onSend={handleSend} sending={sendVoice.isPending} />

          {sentSuccess && (
            <div className="mt-4 rounded-xl bg-green-50 p-4 text-center text-sm text-green-700 dark:bg-green-900/20 dark:text-green-400">
              {t('sent_success')}
            </div>
          )}

          {sendVoice.isError && (
            <div className="mt-4 rounded-xl bg-red-50 p-4 text-center text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {t('error_load')}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Sent messages this session */}
      {sentMessages.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Sent this session</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {sentMessages.map((msg) => (
                <div
                  key={msg.id}
                  className="flex items-center justify-between rounded-lg bg-muted/50 px-4 py-3 text-sm"
                >
                  <div className="flex items-center gap-2">
                    <CheckCircle className="h-4 w-4 text-green-600" />
                    <span>{new Date(msg.sentAt).toLocaleTimeString()}</span>
                  </div>
                  <span className="text-xs text-muted-foreground">{msg.durationSeconds}s</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
