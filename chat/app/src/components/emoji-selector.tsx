import { EMOJI_PHONETICS, EMOJI_SET } from '@/lib/sos-crypto';

type Props = {
  selected: string[];
  onChange: (next: string[]) => void;
};

export default function EmojiSelector({ selected, onChange }: Props) {
  const addEmoji = (emoji: string) => {
    if (selected.length >= 6) return;
    onChange([...selected, emoji]);
  };

  const removeAt = (index: number) => {
    const next = [...selected];
    next.splice(index, 1);
    onChange(next);
  };

  const clearAll = () => onChange([]);

  return (
    <div className="space-y-3">
      <div className="rounded-lg border border-border bg-card p-3">
        <div className="flex flex-wrap gap-2">
          {selected.length === 0 ? (
            <span className="text-xs text-muted-foreground">Pick 6 emojis</span>
          ) : (
            selected.map((emoji, idx) => (
              <button
                key={`${emoji}-${idx}`}
                type="button"
                onClick={() => removeAt(idx)}
                className="rounded-md border border-border bg-background px-2 py-1 text-base"
                title="Tap to remove"
              >
                {emoji}
              </button>
            ))
          )}
          {selected.length > 0 && selected.length < 6 && (
            <span className="text-xs text-muted-foreground">{6 - selected.length} more</span>
          )}
        </div>
        {selected.length > 0 && (
          <div className="mt-2 text-xs text-muted-foreground">
            {selected.map((e) => EMOJI_PHONETICS[e]).join(' · ')}
          </div>
        )}
      </div>

      <div className="grid grid-cols-8 gap-1 rounded-xl border border-border bg-card p-2">
        {EMOJI_SET.map((emoji) => (
          <button
            key={emoji}
            type="button"
            onClick={() => addEmoji(emoji)}
            className="flex h-9 w-9 items-center justify-center rounded-md text-lg transition hover:bg-muted"
            title={EMOJI_PHONETICS[emoji]}
          >
            {emoji}
          </button>
        ))}
      </div>

      <div className="flex gap-2">
        <button
          type="button"
          onClick={clearAll}
          className="text-xs text-muted-foreground underline"
        >
          Clear
        </button>
      </div>
    </div>
  );
}
