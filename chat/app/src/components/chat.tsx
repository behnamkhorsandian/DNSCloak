import * as React from 'react';
import { cn } from '@/lib/utils';

export type ChatSubmitEvent = {
  message: string;
  nativeEvent: React.FormEvent<HTMLFormElement>;
};

type ChatContextValue = {
  onSubmit?: (event: ChatSubmitEvent) => void;
};

const ChatContext = React.createContext<ChatContextValue | null>(null);

export function Chat({
  onSubmit,
  className,
  children
}: React.PropsWithChildren<{ onSubmit?: (event: ChatSubmitEvent) => void; className?: string }>) {
  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    if (!onSubmit) return;
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);
    const message = String(data.get('message') || '').trim();
    if (!message) return;
    onSubmit({ message, nativeEvent: event });
  };

  return (
    <ChatContext.Provider value={{ onSubmit }}>
      <form onSubmit={handleSubmit} className={cn('flex w-full flex-col', className)}>
        {children}
      </form>
    </ChatContext.Provider>
  );
}

export function ChatViewport({ className, children }: React.PropsWithChildren<{ className?: string }>) {
  return (
    <div className={cn('flex flex-col overflow-y-auto rounded-xl border border-border bg-card', className)}>
      {children}
    </div>
  );
}

export function ChatMessages({ className, children }: React.PropsWithChildren<{ className?: string }>) {
  return <div className={cn('flex w-full flex-col gap-3 px-4', className)}>{children}</div>;
}

export function ChatMessageRow({
  variant,
  className,
  children
}: React.PropsWithChildren<{ variant: 'self' | 'peer' | 'system'; className?: string }>) {
  return (
    <div
      data-variant={variant}
      className={cn(
        'group/message-row flex w-full items-start gap-2',
        variant === 'self' && 'justify-end',
        variant === 'peer' && 'justify-start',
        variant === 'system' && 'justify-center',
        className
      )}
    >
      {children}
    </div>
  );
}

export function ChatMessageAvatar({
  src,
  fallback,
  alt,
  className
}: {
  src?: string;
  fallback?: string;
  alt?: string;
  className?: string;
}) {
  if (!src && !fallback) {
    return null;
  }

  return (
    <div
      className={cn(
        'flex size-8 items-center justify-center overflow-hidden rounded-full border border-border bg-muted text-xs font-semibold text-muted-foreground',
        className
      )}
    >
      {src ? <img src={src} alt={alt || 'avatar'} className="h-full w-full object-cover" /> : fallback?.[0]}
    </div>
  );
}

export function ChatMessageBubble({ className, children }: React.PropsWithChildren<{ className?: string }>) {
  return (
    <div
      className={cn(
        'rounded-xl border border-border bg-background px-3 py-2 text-sm leading-relaxed',
        'group-data-[variant=self]/message-row:bg-primary/10 group-data-[variant=self]/message-row:border-primary/20',
        'group-data-[variant=system]/message-row:border-none group-data-[variant=system]/message-row:bg-transparent group-data-[variant=system]/message-row:text-xs group-data-[variant=system]/message-row:text-muted-foreground',
        className
      )}
    >
      {children}
    </div>
  );
}

export function ChatMessageTime({
  dateTime,
  className
}: {
  dateTime: Date;
  className?: string;
}) {
  return (
    <time className={cn('text-[10px] text-muted-foreground', className)} dateTime={dateTime.toISOString()}>
      {dateTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
    </time>
  );
}

export function ChatInputArea({ className, children }: React.PropsWithChildren<{ className?: string }>) {
  return (
    <div className={cn('flex items-end gap-2 rounded-xl border border-border bg-card px-3 py-2', className)}>
      {children}
    </div>
  );
}

export function ChatInputField({
  multiline = true,
  className,
  ...props
}: React.TextareaHTMLAttributes<HTMLTextAreaElement> &
  React.InputHTMLAttributes<HTMLInputElement> & { multiline?: boolean }) {
  const sharedClassName = cn(
    'flex-1 resize-none bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground',
    className
  );

  if (multiline) {
    return <textarea name="message" rows={2} className={sharedClassName} {...props} />;
  }

  return <input name="message" className={sharedClassName} {...props} />;
}

export function ChatInputSubmit({
  className,
  children,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="submit"
      className={cn(
        'inline-flex h-9 min-w-[3.5rem] items-center justify-center rounded-md bg-primary px-3 text-sm font-medium text-primary-foreground transition hover:opacity-90 disabled:opacity-50',
        className
      )}
      {...props}
    >
      {children || 'Send'}
    </button>
  );
}
