import { ThemeToggle } from '@/components/theme-toggle';

export default function Navbar() {
  return (
    <nav className="sticky top-0 z-10 border-b border-border/60 bg-background/80 backdrop-blur">
      <div className="mx-auto flex w-full max-w-md items-center justify-between px-5 py-4">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-primary" aria-hidden="true" />
          <div className="text-sm font-semibold uppercase tracking-[0.25em]">DNSCloak</div>
        </div>
        <ThemeToggle />
      </div>
    </nav>
  );
}
