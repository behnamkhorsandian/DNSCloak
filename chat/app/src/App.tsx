import React from 'react';
import { Check, Home, Network, Plus, Search, PlugZap, X } from 'lucide-react';
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
const NODES_REFRESH_MS = 15000;
const ROOMS_REFRESH_MS = 10000;
const STORAGE_KEYS = {
  workers: 'sos_workers',
  relayUrl: 'sos_relay_url',
  hideInstallPrompt: 'sos_hide_install_prompt'
};

type Screen = 'home' | 'rooms' | 'nodes' | 'create' | 'join' | 'chat';
type TabScreen = 'home' | 'rooms' | 'nodes';
type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
};

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
  const [roomSearchEmojis, setRoomSearchEmojis] = React.useState<string[]>([]);

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
  const [installPromptEvent, setInstallPromptEvent] = React.useState<BeforeInstallPromptEvent | null>(null);
  const [showInstallModal, setShowInstallModal] = React.useState(false);
  const [installMessage, setInstallMessage] = React.useState('');
  const [installDismissClicks, setInstallDismissClicks] = React.useState(0);

  const lastMessageTsRef = React.useRef(0);
  const encryptionKeyRef = React.useRef<Uint8Array | null>(null);
  const messagesEndRef = React.useRef<HTMLDivElement | null>(null);
  const workersRef = React.useRef<WorkerStatus[]>([]);
  const installReminderTimerRef = React.useRef<number | null>(null);

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

  React.useEffect(() => {
    if (typeof window === 'undefined') return;

    const hidden = window.localStorage.getItem(STORAGE_KEYS.hideInstallPrompt) === '1';
    const standalone =
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as Navigator & { standalone?: boolean }).standalone === true;

    if (!hidden && !standalone) {
      setShowInstallModal(true);
    }

    const handleBeforeInstallPrompt = (event: Event) => {
      event.preventDefault();
      setInstallPromptEvent(event as BeforeInstallPromptEvent);
      setInstallMessage('');
    };

    const handleAppInstalled = () => {
      setShowInstallModal(false);
      window.localStorage.setItem(STORAGE_KEYS.hideInstallPrompt, '1');
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    window.addEventListener('appinstalled', handleAppInstalled);

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
      window.removeEventListener('appinstalled', handleAppInstalled);
    };
  }, []);

  React.useEffect(() => {
    if (typeof window === 'undefined') return;
    if (showInstallModal) return;
    if (window.localStorage.getItem(STORAGE_KEYS.hideInstallPrompt) === '1') return;

    const standalone =
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as Navigator & { standalone?: boolean }).standalone === true;
    if (standalone) return;

    const onClick = () => {
      setInstallDismissClicks((prev) => prev + 1);
    };

    window.addEventListener('click', onClick);
    return () => window.removeEventListener('click', onClick);
  }, [showInstallModal]);

  React.useEffect(() => {
    if (showInstallModal) return;
    if (installDismissClicks < 20) return;
    setInstallDismissClicks(0);
    setShowInstallModal(true);
  }, [installDismissClicks, showInstallModal]);

  React.useEffect(() => {
    return () => {
      if (installReminderTimerRef.current) {
        window.clearTimeout(installReminderTimerRef.current);
      }
    };
  }, []);

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
    if (screen === 'chat') return;
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
    const interval = setInterval(loadWorkers, NODES_REFRESH_MS);
    return () => {
      active = false;
      clearInterval(interval);
    };
  }, [screen, fetchWorkersFromGenesis, pingWorker]);

  React.useEffect(() => {
    if (screen === 'chat') return;
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
    if (screen === 'chat') return;
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
    if (screen === 'chat') return;
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

  const setTab = (tab: TabScreen) => {
    setStatus(null);
    setScreen(tab);
  };

  const hideInstallPromptForever = () => {
    if (installReminderTimerRef.current) {
      window.clearTimeout(installReminderTimerRef.current);
      installReminderTimerRef.current = null;
    }
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(STORAGE_KEYS.hideInstallPrompt, '1');
    }
    setShowInstallModal(false);
  };

  const dismissInstallPromptTemporarily = () => {
    setShowInstallModal(false);
    setInstallMessage('');
    setInstallDismissClicks(0);
    if (installReminderTimerRef.current) {
      window.clearTimeout(installReminderTimerRef.current);
    }
    installReminderTimerRef.current = window.setTimeout(() => {
      if (typeof window === 'undefined') return;
      if (window.localStorage.getItem(STORAGE_KEYS.hideInstallPrompt) === '1') return;
      const standalone =
        window.matchMedia('(display-mode: standalone)').matches ||
        (window.navigator as Navigator & { standalone?: boolean }).standalone === true;
      if (!standalone) {
        setShowInstallModal(true);
      }
    }, 10000);
  };

  const installPwa = async () => {
    if (!installPromptEvent) {
      setInstallMessage('Install is not available yet on this browser.');
      return;
    }
    await installPromptEvent.prompt();
    const choice = await installPromptEvent.userChoice;
    if (choice.outcome === 'accepted') {
      hideInstallPromptForever();
      return;
    }
    setInstallPromptEvent(null);
  };

  const expiresIn = expiresAt ? Math.max(0, Math.floor(expiresAt - Date.now() / 1000)) : null;

  const sortedRooms = React.useMemo(
    () => [...rooms].sort((a, b) => b.created_at - a.created_at),
    [rooms]
  );

  const latestRooms = React.useMemo(() => sortedRooms.slice(0, 4), [sortedRooms]);

  const filteredRooms = React.useMemo(() => {
    if (roomSearchEmojis.length === 0) return sortedRooms;
    return sortedRooms.filter((room) => {
      if (!room.emojis || room.emojis.length < roomSearchEmojis.length) return false;
      return roomSearchEmojis.every((emoji, index) => room.emojis?.[index] === emoji);
    });
  }, [sortedRooms, roomSearchEmojis]);

  const pageLabel =
    screen === 'create'
      ? 'Create Room'
      : screen === 'join'
        ? 'Join Room'
        : screen === 'rooms'
          ? 'Rooms'
          : screen === 'nodes'
            ? 'Nodes'
            : screen === 'chat'
              ? 'Chat'
              : 'Home';

  const showBottomTabs = screen !== 'chat';

  return (
    <ThemeProvider>
      <div className="min-h-screen bg-[radial-gradient(circle_at_top,_var(--tw-gradient-stops))] from-muted/40 via-background to-background text-foreground">
        <Navbar pageLabel={pageLabel} />
        <main className="mx-auto flex min-h-[calc(100vh-72px)] w-full max-w-md flex-col px-5 py-8 pb-28">
          {screen === 'home' && (
            <section className="space-y-6">
              <section className="rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="grid grid-cols-2 gap-2">
                  <Button onClick={startCreate}>Create room</Button>
                  <Button variant="outline" onClick={startJoin}>Join room</Button>
                </div>
              </section>

              <section className="rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="flex items-center justify-between">
                  <div className="text-[11px] uppercase tracking-[0.25em] text-muted-foreground">Latest rooms</div>
                  <span className="text-[10px] text-muted-foreground">
                    {loadingRooms ? 'Refreshing...' : `${rooms.length} listed`}
                  </span>
                </div>
                <div className="mt-4 space-y-3">
                  {latestRooms.length === 0 && !loadingRooms && (
                    <div className="text-xs text-muted-foreground">No active rooms shared yet.</div>
                  )}
                  {latestRooms.map((room) => {
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
            </section>
          )}

          {screen === 'create' && (
            <section className="space-y-6">
              <div className="rounded-xl border border-border bg-card p-4">
                <div className="text-xs text-muted-foreground">Room emojis</div>
                <div className="mt-3">
                  <EmojiSelector selected={selectedEmojis} onChange={setSelectedEmojis} />
                </div>
              </div>

              <div className="space-y-3 rounded-xl border border-border bg-card p-4">
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
                {selectedEmojis.length === 6 && (
                  <div className="text-xs text-muted-foreground">
                    {selectedEmojis.map((e) => EMOJI_PHONETICS[e]).join(' · ')}
                  </div>
                )}
              </div>

              <div className="grid gap-2">
                <Button onClick={handleCreateRoom}>Create room</Button>
                <Button variant="outline" onClick={() => setScreen('home')}>Back</Button>
              </div>
            </section>
          )}

          {screen === 'join' && (
            <section className="space-y-6">
              <div className="rounded-xl border border-border bg-card p-4 text-sm text-muted-foreground">
                {selectedRoomDescription ? selectedRoomDescription : 'No description provided.'}
              </div>

              <div className="rounded-xl border border-border bg-card p-4">
                <div className="text-xs text-muted-foreground">Room emojis</div>
                <div className="mt-3">
                  <EmojiSelector selected={selectedEmojis} onChange={setSelectedEmojis} />
                </div>
              </div>

              <div className="space-y-3 rounded-xl border border-border bg-card p-4">
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

              <div className="grid gap-2">
                <Button onClick={handleJoinRoom}>Join room</Button>
                <Button variant="outline" onClick={() => setScreen('home')}>Back</Button>
              </div>
            </section>
          )}

          {screen === 'rooms' && (
            <section className="space-y-6">
              <div className="rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="text-xs text-muted-foreground">Search by emoji ID</div>
                <div className="mt-3">
                  <EmojiSelector selected={roomSearchEmojis} onChange={setRoomSearchEmojis} compact />
                </div>
              </div>

              <section className="rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="flex items-center justify-between">
                  <div className="text-[11px] uppercase tracking-[0.25em] text-muted-foreground">All rooms</div>
                  <span className="text-[10px] text-muted-foreground">
                    {loadingRooms ? 'Refreshing...' : `${filteredRooms.length} match`}
                  </span>
                </div>
                <div className="mt-4 max-h-[460px] space-y-3 overflow-y-auto pr-1">
                  {filteredRooms.length === 0 && !loadingRooms && (
                    <div className="text-xs text-muted-foreground">No matching rooms right now.</div>
                  )}
                  {filteredRooms.map((room) => {
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
            </section>
          )}

          {screen === 'nodes' && (
            <section className="space-y-6">
              <section className="rounded-2xl border border-border/70 bg-card/90 p-5 shadow-lg shadow-black/5 backdrop-blur">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.2em] text-muted-foreground">Connected node</div>
                    <div className="mt-1 text-sm font-medium text-foreground/90">
                      {relayUrl.replace('http://', '').replace('https://', '')}
                    </div>
                  </div>
                  <span className="rounded-full border border-border px-2.5 py-1 text-[10px] uppercase tracking-[0.2em] text-muted-foreground">
                    {connected ? 'Ready' : 'Offline'}
                  </span>
                </div>

                <div className="mt-6 space-y-3 border-t border-border pt-4">
                  <div className="flex items-center justify-between">
                    <div className="text-[11px] uppercase tracking-[0.25em] text-muted-foreground">Nodes</div>
                    <Button size="sm" variant="outline" onClick={() => setShowAddWorker(true)}>
                      Add node
                    </Button>
                  </div>
                  {loadingWorkers && <div className="text-xs text-muted-foreground">Checking nodes...</div>}
                  {!loadingWorkers && workers.length === 0 && (
                    <div className="text-xs text-muted-foreground">
                      No nodes reachable from genesis. Add a node URL if you have one.
                    </div>
                  )}
                  <div className="max-h-[420px] space-y-2 overflow-y-auto pr-1">
                    {workers.map((worker) => (
                      <div key={worker.url} className="flex items-center justify-between gap-2 rounded-lg border border-border/70 bg-background/70 px-2.5 py-2">
                        <div className="min-w-0">
                          <div className="truncate text-xs font-medium text-foreground/90">
                            {worker.url.replace('http://', '').replace('https://', '')}
                          </div>
                          <div className="truncate text-[10px] text-muted-foreground">
                            {worker.is_genesis ? 'Genesis · ' : ''}
                            {worker.online ? 'Online' : 'Offline'}
                            {worker.latency_ms ? ` · ${worker.latency_ms}ms` : ''}
                            {worker.fail_count ? ` · fails ${worker.fail_count}` : ''}
                          </div>
                        </div>
                        <div className="flex shrink-0 items-center gap-1.5">
                          <div
                            className={`flex h-4 w-3 items-end justify-center gap-0.5 ${worker.online ? 'text-foreground' : 'text-muted-foreground'}`}
                            title={worker.latency_ms ? `${worker.latency_ms}ms` : worker.online ? 'Online' : 'Offline'}
                          >
                            <span className={`h-1 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 120 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                            <span className={`h-1.5 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 200 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                            <span className={`h-2 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 350 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                            <span className={`h-2.5 w-0.5 rounded-full ${worker.latency_ms && worker.latency_ms < 500 ? 'bg-emerald-400' : 'bg-muted-foreground/50'}`} />
                          </div>
                          <button
                            type="button"
                            onClick={() => setRelayUrl(worker.url)}
                            className={`inline-flex h-7 w-7 items-center justify-center rounded-md border transition ${
                              relayUrl === worker.url
                                ? 'border-primary/30 bg-primary/15 text-primary'
                                : 'border-border bg-background text-muted-foreground hover:bg-muted hover:text-foreground'
                            }`}
                            title={relayUrl === worker.url ? 'Connected node' : 'Connect node'}
                          >
                            {relayUrl === worker.url ? <Check className="h-3.5 w-3.5" /> : <PlugZap className="h-3.5 w-3.5" />}
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </section>

              <footer className="text-center text-xs text-muted-foreground">
                Node directory refresh:
                {' '}
                nodes in {lastWorkersRefresh ? Math.max(0, Math.ceil((NODES_REFRESH_MS - (nowTick - lastWorkersRefresh)) / 1000)) : '—'}s
                {' · '}
                rooms in {lastRoomsRefresh ? Math.max(0, Math.ceil((ROOMS_REFRESH_MS - (nowTick - lastRoomsRefresh)) / 1000)) : '—'}s
              </footer>
            </section>
          )}

          {screen === 'chat' && (
            <section className="flex flex-1 flex-col">
              <div className="mb-4 space-y-2">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-lg font-semibold">{roomEmojis.join(' ')}</div>
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

          {status && (
            <div className={`mt-4 rounded-md border px-3 py-2 text-sm ${status.type === 'error' ? 'border-red-500/50 text-red-500' : 'border-border text-muted-foreground'}`}>
              {status.message}
            </div>
          )}

          {showAddWorker && (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
              <div className="w-full max-w-sm rounded-xl border border-border bg-card p-4 shadow-lg">
                <div className="text-sm font-semibold">Add node</div>
                <p className="mt-1 text-xs text-muted-foreground">Paste a node URL and add it to your list.</p>
                <input
                  value={manualWorkerUrl}
                  onChange={(e) => setManualWorkerUrl(e.target.value)}
                  className="mt-3 h-10 w-full rounded-md border border-border bg-background px-3 text-sm"
                  placeholder="https://your-node.workers.dev"
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
                        return [...prev, { url: value, last_seen: 0, last_ok: 0, fail_count: 0 }];
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
        </main>

        {showBottomTabs && (
          <div className="fixed inset-x-0 bottom-0 z-40 px-5 pb-4">
            <nav className="mx-auto grid w-full max-w-md grid-cols-4 gap-2 rounded-2xl border border-border/70 bg-card/95 p-2 shadow-2xl shadow-black/10 backdrop-blur">
              {(['home', 'rooms', 'nodes'] as TabScreen[]).map((tab) => {
                const active = screen === tab;
                const Icon = tab === 'home' ? Home : tab === 'rooms' ? Search : Network;
                const label = tab === 'home' ? 'Home' : tab === 'rooms' ? 'Rooms' : 'Nodes';
                return (
                  <button
                    key={tab}
                    type="button"
                    onClick={() => setTab(tab)}
                    aria-label={label}
                    title={label}
                    className={[
                      'inline-flex h-11 items-center justify-center rounded-xl transition-all duration-200',
                      active
                        ? 'bg-primary text-primary-foreground shadow-md shadow-primary/25'
                        : 'bg-background/70 text-muted-foreground hover:bg-muted hover:text-foreground'
                    ].join(' ')}
                  >
                    <Icon className="h-4 w-4" />
                  </button>
                );
              })}
              <button
                type="button"
                onClick={startCreate}
                aria-label="Create room"
                title="Create room"
                className={[
                  'inline-flex h-11 items-center justify-center rounded-xl transition-all duration-200',
                  screen === 'create'
                    ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/25'
                    : 'bg-emerald-500 text-white hover:bg-emerald-600'
                ].join(' ')}
              >
                <Plus className="h-5 w-5" />
              </button>
            </nav>
          </div>
        )}

        {showInstallModal && (
          <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4">
            <div className="w-full max-w-sm rounded-2xl border border-border bg-card p-5 shadow-2xl">
              <div className="flex items-center justify-between gap-3">
                <div className="text-base font-semibold">Install this app</div>
                <button
                  type="button"
                  onClick={dismissInstallPromptTemporarily}
                  className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border bg-background text-muted-foreground hover:bg-muted hover:text-foreground"
                  aria-label="Close install prompt"
                  title="Close"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              <p className="mt-2 text-sm text-muted-foreground">
                Add DNSCloak Chat to your device for a faster, app-like experience.
              </p>
              {installMessage && <p className="mt-2 text-xs text-muted-foreground">{installMessage}</p>}
              <div className="mt-4 grid grid-cols-2 gap-2">
                <Button variant="outline" onClick={hideInstallPromptForever}>
                  Don&apos;t show again
                </Button>
                <Button onClick={installPwa}>
                  Install
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </ThemeProvider>
  );
}
