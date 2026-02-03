import React from 'react';
import Navbar from '@/components/navbar';
import { ThemeProvider } from '@/components/theme-provider';
import { Button } from '@/components/ui/button';
import EmojiSelector from '@/components/emoji-selector';
import {
  Chat,
  ChatInputArea,
  ChatInputField,
  ChatInputSubmit,
  ChatViewport,
  ChatMessages,
  ChatMessageRow,
  ChatMessageBubble,
  ChatMessageTime,
  type ChatSubmitEvent
} from '@/components/chat';
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
  createRoomWithDirectory,
  getRoomInfo,
  getRooms,
  getWorkers,
  joinRoom,
  leaveRoomApi,
  pollMessages,
  sendMessageApi
} from '@/lib/sos-api';

const RELAY_DEFAULT = SOS_CONFIG.RELAY_URL;
const FIXED_MODE: RoomMode = 'fixed';
const WORKERS_REFRESH_MS = 15000;
const ROOMS_REFRESH_MS = 10000;
const STORAGE_KEYS = {
  workers: 'sos_workers',
  relayUrl: 'sos_relay_url'
};

type Screen = 'home' | 'create' | 'join' | 'chat';

type Status = { type: 'info' | 'error' | 'success'; message: string } | null;

type WorkerStatus = {
  url: string;
  last_seen: number;
  last_ok: number;
  fail_count: number;
  is_genesis?: boolean;
  latency_ms?: number;
  online?: boolean;
};

type RoomDirectoryEntry = {
  room_hash: string;
  emojis?: string[];
  description?: string;
  created_at: number;
  expires_at: number;
  worker: string;
};

type StoredWorker = { url: string; is_genesis?: boolean };

const readStoredRelay = () => {
  if (typeof window === 'undefined') return null;
  try {
    const value = window.localStorage.getItem(STORAGE_KEYS.relayUrl);
    return value && value.startsWith('http') ? value : null;
  } catch {
    return null;
  }
};

const readStoredWorkers = (): WorkerStatus[] => {
  if (typeof window === 'undefined') return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEYS.workers);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as StoredWorker[];
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((entry) => entry && typeof entry.url === 'string')
      .map((entry) => ({
        url: entry.url,
        is_genesis: entry.is_genesis,
        last_seen: 0,
        last_ok: 0,
        fail_count: 0
      }));
  } catch {
    return [];
  }
};

const saveStoredWorkers = (workers: WorkerStatus[]) => {
  if (typeof window === 'undefined') return;
  try {
    const payload = workers.map((worker) => ({
      url: worker.url,
      is_genesis: worker.is_genesis
    }));
    window.localStorage.setItem(STORAGE_KEYS.workers, JSON.stringify(payload));
  } catch {
    // ignore storage failures
  }
};

const saveStoredRelay = (relayUrl: string) => {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEYS.relayUrl, relayUrl);
  } catch {
    // ignore storage failures
  }
};

const mergeWorkerLists = (primary: WorkerStatus[], fallback: WorkerStatus[]) => {
  const merged = new Map<string, WorkerStatus>();
  for (const worker of fallback) {
    merged.set(worker.url, worker);
  }
  for (const worker of primary) {
    const existing = merged.get(worker.url);
    merged.set(worker.url, { ...existing, ...worker, url: worker.url });
  }
  return Array.from(merged.values());
};

export default function App() {
  const [screen, setScreen] = React.useState<Screen>('home');
  const [status, setStatus] = React.useState<Status>(null);
  const [relayUrl, setRelayUrl] = React.useState(() => readStoredRelay() || RELAY_DEFAULT);
  const [workers, setWorkers] = React.useState<WorkerStatus[]>(() => readStoredWorkers());
  const [rooms, setRooms] = React.useState<RoomDirectoryEntry[]>([]);
  const [loadingWorkers, setLoadingWorkers] = React.useState(false);
  const [loadingRooms, setLoadingRooms] = React.useState(false);
  const [selectedRoomDescription, setSelectedRoomDescription] = React.useState<string | null>(null);
  const [lastWorkersRefresh, setLastWorkersRefresh] = React.useState<number | null>(null);
  const [lastRoomsRefresh, setLastRoomsRefresh] = React.useState<number | null>(null);
  const [nowTick, setNowTick] = React.useState(Date.now());
  const [showAddWorker, setShowAddWorker] = React.useState(false);
  const [manualWorkerUrl, setManualWorkerUrl] = React.useState('');

  const [selectedEmojis, setSelectedEmojis] = React.useState<string[]>([]);
  const [nickname, setNickname] = React.useState('');
  const [createPin, setCreatePin] = React.useState('');
  const [joinPin, setJoinPin] = React.useState('');
  const [roomDescription, setRoomDescription] = React.useState('');

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
  const workersRef = React.useRef<WorkerStatus[]>([]);

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
    saveStoredRelay(relayUrl);
  }, [relayUrl]);

  React.useEffect(() => {
    saveStoredWorkers(workers);
  }, [workers]);

  const fetchWorkersFromGenesis = React.useCallback(async () => {
    const genesis = SOS_CONFIG.GENESIS_WORKERS;
    for (const url of genesis) {
      try {
        const response = await getWorkers(url);
        return mergeWorkerLists(response.workers, readStoredWorkers());
      } catch {
        // try next genesis
      }
    }
    return readStoredWorkers();
  }, []);

  const pingWorker = React.useCallback(async (url: string) => {
    const start = performance.now();
    try {
      const response = await fetch(`${url}/health`, { cache: 'no-store' });
      const latency = Math.round(performance.now() - start);
      return { online: response.ok, latency };
    } catch {
      return { online: false, latency: null as number | null };
    }
  }, []);

  const pingAndUpdateWorker = React.useCallback(
    async (url: string) => {
      const result = await pingWorker(url);
      setWorkers((prev) =>
        prev.map((worker) =>
          worker.url === url
            ? {
                ...worker,
                online: result.online,
                latency_ms: result.latency ?? undefined
              }
            : worker
        )
      );
    },
    [pingWorker]
  );

  React.useEffect(() => {
    if (screen !== 'home') return;
    let active = true;
    const loadWorkers = async () => {
      setLoadingWorkers(true);
      const list = await fetchWorkersFromGenesis();
      if (!active) return;
      if (list.length === 0) {
        setWorkers([]);
        setLoadingWorkers(false);
        return;
      }
      const pinged = await Promise.all(
        list.map(async (worker) => {
          const result = await pingWorker(worker.url);
          return {
            ...worker,
            online: result.online,
            latency_ms: result.latency ?? undefined
          };
        })
      );
      if (!active) return;
      setWorkers(pinged);
      setLastWorkersRefresh(Date.now());
      setLoadingWorkers(false);
    };
    loadWorkers();
    const interval = setInterval(loadWorkers, WORKERS_REFRESH_MS);
    return () => {
      active = false;
      clearInterval(interval);
    };
  }, [screen, fetchWorkersFromGenesis, pingWorker]);

  React.useEffect(() => {
    if (screen !== 'home') return;
    const interval = setInterval(() => {
      const urls = workersRef.current.map((worker) => worker.url);
      urls.forEach((url) => {
        pingAndUpdateWorker(url);
      });
    }, 60000);
    return () => clearInterval(interval);
  }, [screen, pingAndUpdateWorker]);

  React.useEffect(() => {
    workersRef.current = workers;
  }, [workers]);

  React.useEffect(() => {
    if (screen !== 'home') return;
    let active = true;
    const loadRooms = async () => {
      setLoadingRooms(true);
      try {
        const response = await getRooms(relayUrl);
        if (!active) return;
        setRooms(response.rooms);
        setLastRoomsRefresh(Date.now());
      } catch {
        if (!active) return;
        setRooms([]);
      } finally {
        if (active) setLoadingRooms(false);
      }
    };
    loadRooms();
    const interval = setInterval(loadRooms, ROOMS_REFRESH_MS);
    return () => {
      active = false;
      clearInterval(interval);
    };
  }, [screen, relayUrl]);

  React.useEffect(() => {
    if (screen !== 'home') return;
    const interval = setInterval(() => setNowTick(Date.now()), 1000);
    return () => clearInterval(interval);
  }, [screen]);

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

  const generateNickname = React.useCallback(() => {
    const suffix = Math.random().toString(36).slice(2, 6);
    return `anon-${suffix}`;
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
    setRoomDescription('');
  };

  const startJoin = () => {
    setStatus(null);
    setScreen('join');
    setSelectedEmojis([]);
    setJoinPin('');
    setSelectedRoomDescription(null);
  };

  const joinFromDirectory = (room: RoomDirectoryEntry) => {
    setStatus(null);
    setScreen('join');
    setSelectedEmojis(room.emojis ? [...room.emojis] : []);
    setJoinPin('');
    setSelectedRoomDescription(room.description || null);
    if (!room.emojis || room.emojis.length !== 6) {
      setStatus({ type: 'error', message: 'Room listing missing emojis. Ask the creator for the 6-emoji ID.' });
    }
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
      const chosenName = nickname.trim() || generateNickname();
      const response = await createRoomWithDirectory(
        relayUrl,
        hash,
        FIXED_MODE,
        selectedEmojis,
        roomDescription.trim() || null,
        chosenName
      );

      const key = await getEncryptionKey(selectedEmojis, createPin, FIXED_MODE, response.created_at);

      setRoomHash(hash);
      setRoomEmojis([...selectedEmojis]);
      setMemberId(response.member_id);
      setCreatedAt(response.created_at);
      setExpiresAt(response.expires_at);
      setMembersCount(response.members.length);
      setNickname(chosenName);
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

      const chosenName = nickname.trim() || generateNickname();
      const response = await joinRoom(relayUrl, hash, chosenName);
      const key = await getEncryptionKey(selectedEmojis, joinPin, FIXED_MODE, response.created_at);

      setRoomHash(hash);
      setRoomEmojis([...selectedEmojis]);
      setMemberId(response.member_id);
      setCreatedAt(response.created_at);
      setExpiresAt(response.expires_at);
      setMembersCount(response.members.length);
      setNickname(chosenName);
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

  const sendMessage = async (content: string) => {
    const trimmed = content.trim();
    if (!trimmed || !roomHash || !encryptionKeyRef.current) return;
    if (trimmed.length > SOS_CONFIG.MAX_MESSAGE_LENGTH) {
      setStatus({ type: 'error', message: 'Message too long.' });
      return;
    }

    setSending(true);
    try {
      const encrypted = encryptMessage(trimmed, encryptionKeyRef.current);
      const encoded = base64FromBytes(encrypted);
      await sendMessageApi(relayUrl, roomHash, encoded, nickname || 'anon', memberId);
      setDraft('');
    } catch (err) {
      setStatus({ type: 'error', message: (err as Error).message || 'Send failed.' });
    } finally {
      setSending(false);
    }
  };

  const handleChatSubmit = (event: ChatSubmitEvent) => {
    sendMessage(event.message);
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

  const expiresIn = expiresAt ? Math.max(0, Math.floor(expiresAt - Date.now() / 1000)) : null;

  return (
    <ThemeProvider>
      <div className="min-h-screen bg-[radial-gradient(circle_at_top,_var(--tw-gradient-stops))] from-muted/40 via-background to-background text-foreground">
        <Navbar />
        <main className="mx-auto flex min-h-[calc(100vh-72px)] w-full max-w-md flex-col px-5 py-8">
          {screen === 'home' && (
            <>
              <header className="mb-10 text-center">
                <h1 className="text-2xl font-semibold tracking-tight">Uncensored and Decentralized</h1>
              </header>

              <section className="rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.2em] text-muted-foreground">Relay</div>
                    <div className="mt-1 text-sm font-medium text-foreground/90">
                      {relayUrl.replace('http://', '').replace('https://', '')}
                    </div>
                  </div>
                  <span className="rounded-full border border-border px-2.5 py-1 text-[10px] uppercase tracking-[0.2em] text-muted-foreground">
                    {connected ? 'Ready' : 'Offline'}
                  </span>
                </div>

                <div className="mt-4 grid gap-2">
                  <Button onClick={startCreate}>Create room</Button>
                  <Button variant="outline" onClick={startJoin}>Join room</Button>
                </div>

                <div className="mt-6 space-y-3 border-t border-border pt-4">
                  <div className="flex items-center justify-between">
                    <div className="text-[11px] uppercase tracking-[0.25em] text-muted-foreground">Workers</div>
                    <Button size="sm" variant="outline" onClick={() => setShowAddWorker(true)}>
                      Add worker
                    </Button>
                  </div>
                  {loadingWorkers && <div className="text-xs text-muted-foreground">Checking workers...</div>}
                  {!loadingWorkers && workers.length === 0 && (
                    <div className="text-xs text-muted-foreground">
                      No workers reachable from genesis. Add a worker URL if you have one.
                    </div>
                  )}
                  <div className="space-y-2 max-h-[260px] overflow-y-auto pr-1">
                    {workers.map((worker) => (
                      <div key={worker.url} className="flex items-center justify-between rounded-lg border border-border/70 bg-background/70 px-3 py-2">
                        <div>
                          <div className="text-[13px] font-medium text-foreground/90">
                            {worker.url.replace('http://', '').replace('https://', '')}
                          </div>
                          <div className="text-[10px] text-muted-foreground">
                            {worker.is_genesis ? 'Genesis · ' : ''}
                            {worker.online ? 'Online' : 'Offline'}
                            {worker.latency_ms ? ` · ${worker.latency_ms}ms` : ''}
                            {worker.fail_count ? ` · fails ${worker.fail_count}` : ''}
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <div
                            className={`flex h-4 w-3 items-end justify-center gap-0.5 ${worker.online ? 'text-foreground' : 'text-muted-foreground'}`}
                            title={worker.latency_ms ? `${worker.latency_ms}ms` : worker.online ? 'Online' : 'Offline'}
                          >
                            <span className={`h-1 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 120 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                            <span className={`h-1.5 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 200 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                            <span className={`h-2 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 350 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                            <span className={`h-2.5 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 500 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                          </div>
                          <Button
                            size="sm"
                            variant={relayUrl === worker.url ? 'default' : 'outline'}
                            onClick={() => setRelayUrl(worker.url)}
                          >
                            {relayUrl === worker.url ? 'Connected' : 'Use'}
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </section>

              <section className="mt-6 rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="flex items-center justify-between">
                  <div className="text-[11px] uppercase tracking-[0.25em] text-muted-foreground">Rooms</div>
                  <span className="text-[10px] text-muted-foreground">
                    {loadingRooms ? 'Refreshing...' : `${rooms.length} listed`}
                  </span>
                </div>
                <div className="mt-4 space-y-3 max-h-[300px] overflow-y-auto pr-1">
                  {rooms.length === 0 && !loadingRooms && (
                    <div className="text-xs text-muted-foreground">No active rooms shared yet.</div>
                  )}
                  {rooms.map((room) => {
                    const remaining = Math.max(0, Math.floor(room.expires_at - Date.now() / 1000));
                    return (
                      <div key={room.room_hash} className="rounded-lg border border-border/70 bg-background/70 px-3 py-2">
                        <div className="flex items-center justify-between gap-3">
                          <div>
                            <div className="text-[13px] font-medium text-foreground/90">
                              {room.emojis && room.emojis.length === 6 ? room.emojis.join(' ') : room.room_hash}
                            </div>
                            <div className="mt-1 text-[11px] text-muted-foreground">
                              {room.description ? room.description : 'No description provided.'}
                            </div>
                            <div className="text-[10px] text-muted-foreground">
                              {room.worker.replace('http://', '').replace('https://', '')}
                              {' · '}
                              {Math.floor(remaining / 60)}m {remaining % 60}s
                            </div>
                          </div>
                          <Button size="sm" variant="outline" onClick={() => joinFromDirectory(room)}>
                            Join
                          </Button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </section>

              <footer className="mt-10 text-center text-xs text-muted-foreground">
                Built for low-bandwidth, censorship-resistant chat.
                <div className="mt-2 text-[10px] text-muted-foreground">
                  Directory refresh:
                  {' '}
                  workers in {lastWorkersRefresh ? Math.max(0, Math.ceil((WORKERS_REFRESH_MS - (nowTick - lastWorkersRefresh)) / 1000)) : '—'}s
                  {' · '}
                  rooms in {lastRoomsRefresh ? Math.max(0, Math.ceil((ROOMS_REFRESH_MS - (nowTick - lastRoomsRefresh)) / 1000)) : '—'}s
                </div>
              </footer>

              {showAddWorker && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
                  <div className="w-full max-w-sm rounded-xl border border-border bg-card p-4 shadow-lg">
                    <div className="text-sm font-semibold">Add worker</div>
                    <p className="mt-1 text-xs text-muted-foreground">Paste a worker URL and add it to the list.</p>
                    <input
                      value={manualWorkerUrl}
                      onChange={(e) => setManualWorkerUrl(e.target.value)}
                      className="mt-3 h-10 w-full rounded-md border border-border bg-background px-3 text-sm"
                      placeholder="https://your-worker.workers.dev"
                    />
                    <div className="mt-4 flex justify-end gap-2">
                      <Button variant="outline" size="sm" onClick={() => setShowAddWorker(false)}>
                        Cancel
                      </Button>
                      <Button
                        size="sm"
                        onClick={() => {
                          const value = manualWorkerUrl.trim();
                          if (!value) return;
                          setWorkers((prev) => {
                            if (prev.some((w) => w.url === value)) return prev;
                            return [
                              ...prev,
                              { url: value, last_seen: 0, last_ok: 0, fail_count: 0 }
                            ];
                          });
                          setManualWorkerUrl('');
                          setShowAddWorker(false);
                          pingAndUpdateWorker(value);
                        }}
                      >
                        Add
                      </Button>
                    </div>
                  </div>
                </div>
              )}
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
                  <label className="text-xs text-muted-foreground">Username (optional)</label>
                  <input
                    value={nickname}
                    onChange={(e) => setNickname(e.target.value.slice(0, 20))}
                    className="mt-2 h-10 w-full rounded-md border border-border bg-background px-3 text-sm"
                    placeholder="Leave blank for random"
                  />
                </div>
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

              <div className="rounded-xl border border-border bg-card p-4 space-y-3">
                <div>
                  <label className="text-xs text-muted-foreground">Room description (optional)</label>
                  <textarea
                    value={roomDescription}
                    onChange={(e) => setRoomDescription(e.target.value.slice(0, 140))}
                    className="mt-2 min-h-[88px] w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                    placeholder="Short description, include PIN if you want it public"
                  />
                  <div className="mt-2 text-[10px] text-muted-foreground">{roomDescription.length}/140</div>
                </div>
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

              <div className="rounded-xl border border-border bg-card p-4 text-sm text-muted-foreground">
                {selectedRoomDescription ? selectedRoomDescription : 'No description provided.'}
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
                  <label className="text-xs text-muted-foreground">Username (optional)</label>
                  <input
                    value={nickname}
                    onChange={(e) => setNickname(e.target.value.slice(0, 20))}
                    className="mt-2 h-10 w-full rounded-md border border-border bg-background px-3 text-sm"
                    placeholder="Leave blank for random"
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

              <Chat onSubmit={handleChatSubmit}>
                <ChatViewport className="h-[460px]">
                  <ChatMessages className="py-4">
                    {messages.length === 0 && (
                      <div className="text-center text-xs text-muted-foreground">No messages yet</div>
                    )}
                    {messages.map((msg) => {
                      if (msg.system) {
                        return (
                          <ChatMessageRow key={msg.id} variant="system">
                            <ChatMessageBubble>{msg.content}</ChatMessageBubble>
                          </ChatMessageRow>
                        );
                      }

                      return (
                        <ChatMessageRow key={msg.id} variant={msg.own ? 'self' : 'peer'}>
                          <div className="flex w-full max-w-[75%] flex-col gap-1">
                            {!msg.own && (
                              <div className="text-[11px] font-medium text-muted-foreground">
                                {msg.sender}
                              </div>
                            )}
                            <ChatMessageBubble>{msg.content}</ChatMessageBubble>
                            <ChatMessageTime dateTime={new Date(msg.timestamp * 1000)} />
                          </div>
                        </ChatMessageRow>
                      );
                    })}
                    <div ref={messagesEndRef} />
                  </ChatMessages>
                </ChatViewport>

                <div className="mt-3">
                  <ChatInputArea>
                    <ChatInputField
                      multiline
                      placeholder="Type a message"
                      value={draft}
                      onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) => setDraft(e.target.value)}
                    />
                    <ChatInputSubmit disabled={sending || !draft.trim()}>
                      Send
                    </ChatInputSubmit>
                  </ChatInputArea>
                </div>
              </Chat>
            </section>
          )}
        </main>
      </div>
    </ThemeProvider>
  );
}
