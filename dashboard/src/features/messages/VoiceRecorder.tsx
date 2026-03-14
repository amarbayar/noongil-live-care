import { useState, useRef, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { useT } from '@/lib/i18n';
import { Mic, Square, Send, Trash2, Play, Pause } from 'lucide-react';

interface VoiceRecorderProps {
  onSend: (data: { audioBase64: string; durationSeconds: number }) => void;
  sending: boolean;
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const result = reader.result as string;
      // Strip the data URL prefix
      resolve(result.split(',')[1]);
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

export function VoiceRecorder({ onSend, sending }: VoiceRecorderProps) {
  const t = useT();
  const [recording, setRecording] = useState(false);
  const [audioBlob, setAudioBlob] = useState<Blob | null>(null);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [playing, setPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<number | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const startRecording = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });
      chunksRef.current = [];

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };

      mediaRecorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: 'audio/webm' });
        setAudioBlob(blob);
        setAudioUrl(URL.createObjectURL(blob));
        stream.getTracks().forEach((track) => track.stop());
      };

      mediaRecorderRef.current = mediaRecorder;
      mediaRecorder.start();
      setRecording(true);
      setDuration(0);
      setAudioBlob(null);
      setAudioUrl(null);

      timerRef.current = window.setInterval(() => {
        setDuration((d) => {
          if (d >= 20) {
            mediaRecorderRef.current?.stop();
            setRecording(false);
            if (timerRef.current) clearInterval(timerRef.current);
            return d;
          }
          return d + 1;
        });
      }, 1000);
    } catch {
      // Microphone access denied
    }
  }, []);

  const stopRecording = () => {
    mediaRecorderRef.current?.stop();
    setRecording(false);
    if (timerRef.current) clearInterval(timerRef.current);
  };

  const togglePlayback = () => {
    if (!audioUrl) return;
    if (!audioRef.current || audioRef.current.src !== audioUrl) {
      if (audioRef.current) audioRef.current.pause();
      audioRef.current = new Audio(audioUrl);
      audioRef.current.onended = () => setPlaying(false);
    }
    if (playing) {
      audioRef.current.pause();
      setPlaying(false);
    } else {
      audioRef.current.play().catch(() => {
        // Browser may block autoplay
        setPlaying(false);
      });
      setPlaying(true);
    }
  };

  const discard = () => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current = null;
    }
    if (audioUrl) URL.revokeObjectURL(audioUrl);
    setAudioBlob(null);
    setAudioUrl(null);
    setPlaying(false);
    setDuration(0);
  };

  const handleSend = async () => {
    if (!audioBlob) return;
    const audioBase64 = await blobToBase64(audioBlob);
    onSend({ audioBase64, durationSeconds: duration });
    discard();
  };

  return (
    <div className="flex flex-col items-center gap-4 py-8">
      {/* Recording visualizer */}
      <div className="relative flex h-24 w-24 items-center justify-center">
        {recording && (
          <div className="absolute inset-0 animate-ping rounded-full bg-destructive/20" />
        )}
        <div
          className={`flex h-20 w-20 items-center justify-center rounded-full transition-colors ${
            recording
              ? 'bg-destructive text-destructive-foreground'
              : audioBlob
                ? 'bg-green-600 text-white'
                : 'bg-primary text-primary-foreground'
          }`}
        >
          {recording ? (
            <div className="text-center">
              <Mic className="mx-auto h-6 w-6" />
              <span className="mt-1 block text-xs font-mono">{duration}s</span>
            </div>
          ) : (
            <Mic className="h-8 w-8" />
          )}
        </div>
      </div>

      {/* Controls */}
      <div className="flex items-center gap-3">
        {!recording && !audioBlob && (
          <Button onClick={startRecording} className="gap-2">
            <Mic className="h-4 w-4" />
            {t('start_recording')}
          </Button>
        )}

        {recording && (
          <Button variant="destructive" onClick={stopRecording} className="gap-2">
            <Square className="h-4 w-4" />
            {t('stop')}
          </Button>
        )}

        {audioBlob && !recording && (
          <>
            <Button variant="outline" onClick={togglePlayback} className="gap-2">
              {playing ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
              {playing ? t('stop') : 'Play'}
            </Button>
            <Button variant="outline" onClick={discard} className="gap-2">
              <Trash2 className="h-4 w-4" />
              {t('discard')}
            </Button>
            <Button onClick={handleSend} disabled={sending} className="gap-2">
              <Send className="h-4 w-4" />
              {sending ? t('sending') : t('send_to_member')}
            </Button>
          </>
        )}
      </div>

      {audioBlob && (
        <p className="text-xs text-muted-foreground">
          {t('duration_label')}: {duration}s
        </p>
      )}
    </div>
  );
}
