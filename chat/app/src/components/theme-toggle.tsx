import { Button } from '@/components/ui/button';
import { useTheme } from '@/components/theme-provider';

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();

  return (
    <Button variant="outline" size="sm" onClick={toggleTheme} aria-label="Toggle theme">
      {theme === 'dark' ? 'Light' : 'Dark'}
    </Button>
  );
}
