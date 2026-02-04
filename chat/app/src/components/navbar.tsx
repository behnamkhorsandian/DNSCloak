import { ThemeToggle } from '@/components/theme-toggle';

type Props = {
  pageLabel?: string;
};

export default function Navbar({ pageLabel }: Props) {
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
        <ThemeToggle />
      </div>
    </nav>
  );
}
