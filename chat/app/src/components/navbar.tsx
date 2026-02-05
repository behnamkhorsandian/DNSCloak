import { ThemeToggle } from '@/components/theme-toggle';

type Props = {
  pageLabel?: string;
  onGuideClick?: () => void;
  guideActive?: boolean;
  onLanguageToggle?: () => void;
  languageLabel?: string;
  appName?: string;
  tagline?: string;
  guideLabel?: string;
  themeToggleLabel?: string;
};

export default function Navbar({
  pageLabel,
  onGuideClick,
  guideActive,
  onLanguageToggle,
  languageLabel,
  appName,
  tagline,
  guideLabel,
  themeToggleLabel
}: Props) {
  return (
    <nav className="sticky top-0 z-10 border-b border-border/60 bg-background/80 backdrop-blur">
      <div className="mx-auto flex w-full max-w-md items-center justify-between px-5 py-4">
        <div className="flex min-w-0 items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full bg-primary" aria-hidden="true" />
          <div className="min-w-0">
            <div className="text-sm font-semibold uppercase tracking-[0.22em]">{appName ?? 'DNSCloak'}</div>
            <div className="truncate text-[10px] text-muted-foreground">
              {pageLabel ? `${pageLabel} · ` : ''}
              {tagline ?? 'Uncensored and Decentralized'}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onGuideClick}
            className={[
              'h-10 rounded-md border px-3 text-[11px] font-semibold uppercase tracking-[0.18em] transition',
              guideActive
                ? 'border-primary/40 bg-primary/15 text-primary'
                : 'border-border bg-background text-muted-foreground hover:bg-muted hover:text-foreground'
            ].join(' ')}
          >
            {guideLabel ?? 'Guide'}
          </button>
          <button
            type="button"
            onClick={onLanguageToggle}
            className="h-10 rounded-md border border-border bg-background px-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            {languageLabel}
          </button>
          <ThemeToggle label={themeToggleLabel} />
        </div>
      </div>
    </nav>
  );
}
