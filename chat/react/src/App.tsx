import React from 'react';
import Navbar from '@/components/navbar';
import { ThemeProvider } from '@/components/theme-provider';
import { Button } from '@/components/ui/button';
import EmojiSelector from '@/components/emoji-selector';
import { SOS_CONFIG } from '@/lib/sos-config';
import {
  EMOJI_PHONETICS,
  base64FromBytes,
  bytesFromBase64,
  getEncryptionKey,
  roomIdToHash,
  tryDecrypt,
  encryptMessage
} from '@/lib/sos-crypto';
import type { ChatMessage, RoomMode } from '@/lib/sos-types';
import {
  createRoom,
  getRoomInfo,
  joinRoom,
  leaveRoomApi,
  pollMessages,
  sendMessageApi
} from '@/lib/sos-api';

const LIONSUN_BANNER = "                                               \n                 .    |     .                  \n                  \\   |    /                   \n      \\|\\||    .   \\  '   /   .'               \n     -- ||||/   `. .-*\"\"*-. .'                 \n    /7   |||||/._ /        \\ _.-*\"             \n   /    |||||||/.:          ;                  \n   \\-' |||||||||-----------------._            \n    -/||||||||\\                `` -`.          \n      /||||||\\             \\_  |   `\\\\         \n      -//|||\\|________...---'\\  \\    \\\\        \n         ||  |  \\ ``-.__--. | \\  |    ``-.__--.\n        / |  |\\  \\   ``---'/ / | |       ``---'\n     __/_/  / _|  )     __/ / _| |             \n    /,_/,__/_/,__/     /,__/ /,__/             ";

const RELAY_DEFAULT = SOS_CONFIG.RELAY_URL;
const FIXED_MODE: RoomMode = 'fixed';

type Screen = 'home' | 'create' | 'join' | 'chat';

type Status = { type: 'info' | 'error' | 'success'; message: string } | null;

export default function App() {
  const [screen, setScreen] = React.useState<Screen>('home');
  const [status, setStatus] = React.useState<Status>(null);
  const [relayUrl, setRelayUrl] = React.useState(RELAY_DEFAULT);

  const [selectedEmojis, setSelectedEmojis] = React.useState<string[]>([]);
  const [nickname, setNickname] = React.useState('anon');
  const [createPin, setCreatePin] = React.useState('');
  const [joinPin, setJoinPin] = React.useState('');

  const [roomHash, setRoomHash] = React.useState<string | null>(null);
  const [roomEmojis, setRoomEmojis] = React.useState<string[]>([]);
  const [memberId, setMemberId] = React.useState<string | null>(null);
  const [createdAt, setCreatedAt] = React.useState<number | null>(null);
  const [expiresAt, setExpiresAt] = React.useState<number | null>(null);
  const [membersCount, setMembersCount] = React.useState(0);

  const [messages, setMessages] = React.useState<ChatMessage[]>([]);
  const [draft, setDraft] = React.useState('');
  const [lastMessageTs, setLastMessageTs] = React.useState(0);
  const [encryptionKey, setEncryptionKey] = React.useState<Uint8Array | null>(null);
  const [connected, setConnected] = React.useState(true);
  const [sending, setSending] = React.useState(false);

  const lastMessageTsRef = React.useRef(0);
  const encryptionKeyRef = React.useRef<Uint8Array | null>(null);
  const messagesEndRef = React.useRef<HTMLDivElement | null>(null);

  React.useEffect(() => {
    lastMessageTsRef.current = lastMessageTs;
  }, [lastMessageTs]);

  React.useEffect(() => {
    encryptionKeyRef.current = encryptionKey;
  }, [encryptionKey]);

  React.useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  React.useEffect(() => {
    if (screen !== 'chat' || !roomHash || !createdAt || roomEmojis.length !== 6) return undefined;

    let active = true;
    const poll = async () => {
      try {
        const response = await pollMessages(relayUrl, roomHash, lastMessageTsRef.current, memberId);
        if (!active) return;
        if (!connected) setConnected(true);

        setExpiresAt(response.expires_at);
        setMembersCount(response.members.length);

        let maxTs = lastMessageTsRef.current;
        const newMessages: ChatMessage[] = [];

        for (const msg of response.messages) {
          if (msg.timestamp <= lastMessageTsRef.current) continue;
          const decrypted = await tryDecrypt(
            bytesFromBase64(msg.content),
            roomEmojis,
            FIXED_MODE,
            createdAt,
            screen === 'chat' ? (createPin || joinPin) : null
          );
          newMessages.push({
            id: msg.id,
            sender: msg.sender,
            content: decrypted ?? '[Could not decrypt]',
            timestamp: msg.timestamp,
            own: msg.sender === nickname
          });
          if (msg.timestamp > maxTs) maxTs = msg.timestamp;
        }

        if (newMessages.length > 0) {
          setMessages((prev) => [...prev, ...newMessages]);
        }
        if (maxTs !== lastMessageTsRef.current) {
          lastMessageTsRef.current = maxTs;
          setLastMessageTs(maxTs);
        }
      } catch {
        if (!active) return;
        setConnected(false);
      }
    };

    poll();
    const interval = setInterval(poll, SOS_CONFIG.POLL_INTERVAL);
    return () => {
      active = false;
      clearInterval(interval);
    };
  }, [screen, roomHash, createdAt, roomEmojis, relayUrl, memberId, nickname, connected, createPin, joinPin]);

  const addSystemMessage = React.useCallback((text: string) => {
    setMessages((prev) => [
      ...prev,
      { id: `system-${Date.now()}`, sender: 'system', content: text, timestamp: Date.now() / 1000, system: true }
    ]);
  }, []);

  const resetSession = React.useCallback(() => {
    setRoomHash(null);
    setRoomEmojis([]);
    setMemberId(null);
    setCreatedAt(null);
    setExpiresAt(null);
    setMembersCount(0);
    setMessages([]);
    setDraft('');
    setLastMessageTs(0);
    setEncryptionKey(null);
    setConnected(true);
    setStatus(null);
  }, []);

  const startCreate = () => {
    setStatus(null);
    setScreen('create');
    setSelectedEmojis([]);
    setCreatePin('');
  };

  const startJoin = () => {
    setStatus(null);
    setScreen('join');
    setSelectedEmojis([]);
    setJoinPin('');
  };

  const handleCreateRoom = async () => {
    if (selectedEmojis.length !== 6) {
      setStatus({ type: 'error', message: 'Pick all 6 emojis.' });
      return;
    }
    if (createPin.length !== 6) {
      setStatus({ type: 'error', message: 'Enter a 6-digit PIN.' });
      return;
    }

    setStatus({ type: 'info', message: 'Creating room...' });
    try {
      const hash = await roomIdToHash(selectedEmojis);
      const response = await createRoom(relayUrl, hash, FIXED_MODE);

      const key = await getEncryptionKey(selectedEmojis, createPin, FIXED_MODE, response.created_at);

      setRoomHash(hash);
      setRoomEmojis([...selectedEmojis]);
      setMemberId(response.member_id);
      setCreatedAt(response.created_at);
      setExpiresAt(response.expires_at);
      setMembersCount(response.members.length);
      setNickname('creator');
      setEncryptionKey(key);
      setMessages([]);
      setLastMessageTs(0);

      setScreen('chat');
      setStatus(null);
      addSystemMessage('Room created. Messages are end-to-end encrypted.');
    } catch (err) {
      setStatus({ type: 'error', message: (err as Error).message || 'Failed to create room.' });
    }
  };

  const handleJoinRoom = async () => {
    if (selectedEmojis.length !== 6) {
      setStatus({ type: 'error', message: 'Pick all 6 emojis.' });
      return;
    }
    if (joinPin.length !== 6) {
      setStatus({ type: 'error', message: 'Enter the 6-digit PIN.' });
      return;
    }

    setStatus({ type: 'info', message: 'Joining room...' });
    try {
      const hash = await roomIdToHash(selectedEmojis);
      await getRoomInfo(relayUrl, hash);

      const response = await joinRoom(relayUrl, hash, nickname || 'anon');
      const key = await getEncryptionKey(selectedEmojis, joinPin, FIXED_MODE, response.created_at);

      setRoomHash(hash);
      setRoomEmojis([...selectedEmojis]);
      setMemberId(response.member_id);
      setCreatedAt(response.created_at);
      setExpiresAt(response.expires_at);
      setMembersCount(response.members.length);
      setEncryptionKey(key);
      setMessages([]);
      setLastMessageTs(0);

      setScreen('chat');
      setStatus(null);
      addSystemMessage('You joined the room. Messages are end-to-end encrypted.');
    } catch (err) {
      setStatus({ type: 'error', message: (err as Error).message || 'Failed to join room.' });
    }
  };

  const handleSend = async () => {
    if (!draft.trim() || !roomHash || !encryptionKeyRef.current) return;
    if (draft.length > SOS_CONFIG.MAX_MESSAGE_LENGTH) {
      setStatus({ type: 'error', message: 'Message too long.' });
      return;
    }

    setSending(true);
    try {
      const encrypted = encryptMessage(draft.trim(), encryptionKeyRef.current);
      const encoded = base64FromBytes(encrypted);
      await sendMessageApi(relayUrl, roomHash, encoded, nickname || 'anon', memberId);
      setDraft('');
    } catch (err) {
      setStatus({ type: 'error', message: (err as Error).message || 'Send failed.' });
    } finally {
      setSending(false);
    }
  };

  const handleLeave = async () => {
    if (roomHash) {
      try {
        await leaveRoomApi(relayUrl, roomHash, memberId);
      } catch {
        // ignore leave failures
      }
    }
    resetSession();
    setScreen('home');
  };

  const formatTime = (ts: number) => {
    const date = new Date(ts * 1000);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const expiresIn = expiresAt ? Math.max(0, Math.floor(expiresAt - Date.now() / 1000)) : null;

  return (
    <ThemeProvider>
      <div className="min-h-screen bg-background text-foreground">
        <Navbar />
        <main className="mx-auto flex min-h-[calc(100vh-72px)] w-full max-w-md flex-col px-5 py-8">
          {screen === 'home' && (
            <>
              <div data-banner="lionsun" className="mb-6 mx-auto w-fit rounded-xl border border-border bg-card px-3 py-3 text-[9px] leading-[1.1] text-muted-foreground whitespace-pre select-none banner-sunlion" aria-label="Sunlion banner">
                {LIONSUN_BANNER}
              </div>
              <header className="mb-10">
                <div className="text-xs uppercase tracking-[0.3em] text-muted-foreground">SOS</div>
                <h1 className="mt-3 text-3xl font-semibold leading-tight">
                  Uncensored
                  <span className="block text-muted-foreground">chat</span>
                </h1>
              </header>

              <section className="rounded-xl border border-border bg-card p-5 shadow-sm">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-sm text-muted-foreground">Relay</div>
                    <div className="mt-1 text-base font-medium">{relayUrl.replace('http://', '').replace('https://', '')}</div>
                  </div>
                  <span className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
                    {connected ? 'Ready' : 'Offline'}
                  </span>
                </div>

                <div className="mt-4 grid gap-3">
                  <label className="text-xs text-muted-foreground">Custom relay URL</label>
                  <input
                    value={relayUrl}
                    onChange={(e) => setRelayUrl(e.target.value)}
                    className="h-10 rounded-md border border-border bg-background px-3 text-sm"
                    placeholder="http://relay.dnscloak.net:8899"
                  />
                  <div className="grid gap-2">
                    <Button onClick={startCreate}>Create room</Button>
                    <Button variant="outline" onClick={startJoin}>Join room</Button>
                  </div>
                </div>
              </section>

              <footer className="mt-10 text-center text-xs text-muted-foreground">
                Built for low-bandwidth, censorship-resistant chat.
              </footer>
            </>
          )}

          {screen === 'create' && (
            <section className="space-y-6">
              <div>
                <div className="text-xs uppercase tracking-[0.3em] text-muted-foreground">Create</div>
                <h2 className="mt-2 text-2xl font-semibold">New room</h2>
              </div>

              <div className="rounded-xl border border-border bg-card p-4">
                <div className="text-xs text-muted-foreground">Room emojis</div>
                <div className="mt-3">
                  <EmojiSelector selected={selectedEmojis} onChange={setSelectedEmojis} />
                </div>
              </div>

              <div className="rounded-xl border border-border bg-card p-4 space-y-3">
                <div>
                  <label className="text-xs text-muted-foreground">PIN</label>
                  <input
                    value={createPin}
                    onChange={(e) => setCreatePin(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    className="mt-2 h-10 w-full rounded-md border border-border bg-background px-3 text-sm tracking-[0.3em]"
                    placeholder="Enter 6-digit PIN"
                  />
                </div>
                {selectedEmojis.length === 6 && (
                  <div className="text-xs text-muted-foreground">
                    {selectedEmojis.map((e) => EMOJI_PHONETICS[e]).join(' · ')}
                  </div>
                )}
              </div>

              {status && (
                <div className={`rounded-md border px-3 py-2 text-sm ${status.type === 'error' ? 'border-red-500/50 text-red-500' : 'border-border text-muted-foreground'}`}>
                  {status.message}
                </div>
              )}

              <div className="grid gap-2">
                <Button onClick={handleCreateRoom}>Create room</Button>
                <Button variant="outline" onClick={() => setScreen('home')}>Back</Button>
              </div>
            </section>
          )}

          {screen === 'join' && (
            <section className="space-y-6">
              <div>
                <div className="text-xs uppercase tracking-[0.3em] text-muted-foreground">Join</div>
                <h2 className="mt-2 text-2xl font-semibold">Existing room</h2>
              </div>

              <div className="rounded-xl border border-border bg-card p-4">
                <div className="text-xs text-muted-foreground">Room emojis</div>
                <div className="mt-3">
                  <EmojiSelector selected={selectedEmojis} onChange={setSelectedEmojis} />
                </div>
              </div>

              <div className="rounded-xl border border-border bg-card p-4 space-y-3">
                <div>
                  <label className="text-xs text-muted-foreground">PIN</label>
                  <input
                    value={joinPin}
                    onChange={(e) => setJoinPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    className="mt-2 h-10 w-full rounded-md border border-border bg-background px-3 text-sm tracking-[0.3em]"
                    placeholder="••••••"
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">Nickname</label>
                  <input
                    value={nickname}
                    onChange={(e) => setNickname(e.target.value.slice(0, 20))}
                    className="mt-2 h-10 w-full rounded-md border border-border bg-background px-3 text-sm"
                    placeholder="anon"
                  />
                </div>
              </div>

              {status && (
                <div className={`rounded-md border px-3 py-2 text-sm ${status.type === 'error' ? 'border-red-500/50 text-red-500' : 'border-border text-muted-foreground'}`}>
                  {status.message}
                </div>
              )}

              <div className="grid gap-2">
                <Button onClick={handleJoinRoom}>Join room</Button>
                <Button variant="outline" onClick={() => setScreen('home')}>Back</Button>
              </div>
            </section>
          )}

          {screen === 'chat' && (
            <section className="flex flex-1 flex-col">
              <div className="mb-4 space-y-2">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-xs uppercase tracking-[0.3em] text-muted-foreground">Room</div>
                    <div className="mt-1 text-lg font-semibold">{roomEmojis.join(' ')}</div>
                    <div className="text-xs text-muted-foreground">{membersCount} online · {roomHash}</div>
                  </div>
                  <Button variant="outline" size="sm" onClick={handleLeave}>Leave</Button>
                </div>

                <div className="rounded-lg border border-border bg-card p-3 text-xs text-muted-foreground">
                  <div>Mode: fixed</div>
                  <div>PIN: {createPin || joinPin}</div>
                  {expiresIn !== null && <div>Expires in: {Math.floor(expiresIn / 60)}m {expiresIn % 60}s</div>}
                </div>

                {!connected && (
                  <div className="rounded-md border border-yellow-500/40 bg-yellow-500/10 px-3 py-2 text-xs text-yellow-500">
                    Connection lost. Retrying...
                  </div>
                )}
              </div>

              <div className="flex-1 space-y-2 overflow-y-auto rounded-xl border border-border bg-card p-4">
                {messages.length === 0 && (
                  <div className="text-center text-xs text-muted-foreground">No messages yet</div>
                )}
                {messages.map((msg) => (
                  <div
                    key={msg.id}
                    className={`rounded-lg px-3 py-2 text-sm ${msg.system ? 'bg-muted text-muted-foreground' : msg.own ? 'bg-primary/10 text-foreground' : 'bg-background text-foreground border border-border'}`}
                  >
                    {!msg.system && (
                      <div className="text-[10px] uppercase tracking-[0.2em] text-muted-foreground">{msg.sender}</div>
                    )}
                    <div className="mt-1 whitespace-pre-wrap break-words">{msg.content}</div>
                    <div className="mt-1 text-[10px] text-muted-foreground">{formatTime(msg.timestamp)}</div>
                  </div>
                ))}
                <div ref={messagesEndRef} />
              </div>

              <div className="mt-4 flex gap-2">
                <input
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleSend();
                  }}
                  className="h-11 flex-1 rounded-md border border-border bg-background px-3 text-sm"
                  placeholder="Type a message"
                />
                <Button onClick={handleSend} disabled={sending || !draft.trim()}>
                  Send
                </Button>
              </div>
            </section>
          )}
        </main>
      </div>
    </ThemeProvider>
  );
}
