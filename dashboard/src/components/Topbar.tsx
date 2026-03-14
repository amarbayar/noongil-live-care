import { useStore } from '@/lib/store';
import { useT } from '@/lib/i18n';
import { Button } from '@/components/ui/button';
import { DateRangePicker } from './DateRangePicker';
import { Menu, Moon, Sun, Globe } from 'lucide-react';

const pageTitles: Record<string, string> = {
  checkins: 'nav_checkins',
  causal: 'nav_causal',
  'care-plan': 'nav_care_plan',
  messages: 'nav_messages',
};

export function Topbar() {
  const t = useT();
  const page = useStore((s) => s.page);
  const theme = useStore((s) => s.theme);
  const locale = useStore((s) => s.locale);
  const toggleTheme = useStore((s) => s.toggleTheme);
  const setLocale = useStore((s) => s.setLocale);
  const setSidebarOpen = useStore((s) => s.setSidebarOpen);

  return (
    <header className="sticky top-0 z-30 flex items-center justify-between border-b border-border bg-background/80 px-4 py-3 backdrop-blur-md lg:px-6">
      <div className="flex items-center gap-3">
        <Button
          variant="ghost"
          size="icon"
          className="lg:hidden"
          onClick={() => setSidebarOpen(true)}
        >
          <Menu className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-lg font-semibold">{t(pageTitles[page] || 'caregiver_dashboard')}</h1>
        </div>
      </div>

      <div className="flex items-center gap-2">
        <DateRangePicker />

        <Button
          variant="ghost"
          size="icon"
          onClick={() => setLocale(locale === 'en' ? 'mn' : 'en')}
          title={locale === 'en' ? 'Монгол' : 'English'}
        >
          <Globe className="h-4 w-4" />
        </Button>

        <Button
          variant="ghost"
          size="icon"
          onClick={toggleTheme}
        >
          {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
        </Button>
      </div>
    </header>
  );
}
