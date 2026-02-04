import { ThemeToggle } from '@/components/theme-toggle';

type Props = {
  pageLabel?: string;
  onGuideClick?: () => void;
  guideActive?: boolean;
};

export default function Navbar({ pageLabel, onGuideClick, guideActive }: Props) {
  return (
    <nav className="sticky top-0 z-10 border-b border-border/60 bg-background/80 backdrop-blur">
      <div className="mx-auto flex w-full max-w-md items-center justify-between px-5 py-4">
        <div className="flex min-w-0 items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full bg-primary" aria-hidden="true" />
          <div className="min-w-0">
            <div className="text-sm font-semibold uppercase tracking-[0.22em]">DNSCloak</div>
            <div className="truncate text-[10px] text-muted-foreground">
              {pageLabel ? `${pageLabel} · ` : ''}
              Uncensored and Decentralized
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
            Guide
          </button>
          <ThemeToggle />
        </div>
      </div>
    </nav>
  );
}
