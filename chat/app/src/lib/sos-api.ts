import type { RoomMode } from '@/lib/sos-types';

async function apiRequest<T>(relayUrl: string, endpoint: string, method: 'GET' | 'POST' = 'GET', body?: unknown) {
  const url = `${relayUrl}${endpoint}`;
  const options: RequestInit = {
    method,
    headers: { 'Content-Type': 'application/json' }
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    const error = (data && data.error) || `HTTP ${response.status}`;
    throw new Error(error);
  }

  return data as T;
}

export async function createRoom(relayUrl: string, roomHash: string, mode: RoomMode) {
  return apiRequest<{
    room_hash: string;
    mode: RoomMode;
    created_at: number;
    expires_at: number;
    member_id: string;
    members: string[];
  }>(relayUrl, '/room', 'POST', { room_hash: roomHash, mode });
}

export async function createRoomWithDirectory(
  relayUrl: string,
  roomHash: string,
  mode: RoomMode,
  emojis: string[],
  description: string | null,
  nickname: string
) {
  return apiRequest<{
    room_hash: string;
    mode: RoomMode;
    created_at: number;
    expires_at: number;
    member_id: string;
    members: string[];
  }>(relayUrl, '/room', 'POST', { room_hash: roomHash, mode, emojis, description, nickname });
}

export async function joinRoom(relayUrl: string, roomHash: string, nickname: string) {
  return apiRequest<{
    room_hash: string;
    mode: RoomMode;
    created_at: number;
    expires_at: number;
    member_id: string;
    members: string[];
    message_count: number;
    last_message_ts: number;
  }>(relayUrl, `/room/${roomHash}/join`, 'POST', { nickname });
}

export async function sendMessageApi(
  relayUrl: string,
  roomHash: string,
  content: string,
  sender: string,
  memberId?: string | null
) {
  return apiRequest<{ id: string; timestamp: number }>(relayUrl, `/room/${roomHash}/send`, 'POST', {
    content,
    sender,
    member_id: memberId || undefined
  });
}

export async function pollMessages(relayUrl: string, roomHash: string, since: number, memberId?: string | null) {
  const params = new URLSearchParams({ since: since.toString() });
  if (memberId) params.append('member_id', memberId);
  return apiRequest<{
    messages: Array<{ id: string; sender: string; content: string; timestamp: number }>;
    members: string[];
    expires_at: number;
    message_count: number;
  }>(relayUrl, `/room/${roomHash}/poll?${params}`);
}

export async function leaveRoomApi(relayUrl: string, roomHash: string, memberId?: string | null) {
  return apiRequest<{ status: string }>(relayUrl, `/room/${roomHash}/leave`, 'POST', { member_id: memberId || undefined });
}

export async function getRoomInfo(relayUrl: string, roomHash: string) {
  return apiRequest<{
    room_hash: string;
    mode: RoomMode;
    created_at: number;
    expires_at: number;
    members: string[];
    message_count: number;
    time_remaining: number;
  }>(relayUrl, `/room/${roomHash}/info`);
}

export async function getWorkers(relayUrl: string) {
  return apiRequest<{
    workers: Array<{ url: string; last_seen: number; last_ok: number; fail_count: number; is_genesis?: boolean }>;
  }>(relayUrl, '/workers');
}

export async function getRooms(relayUrl: string) {
  return apiRequest<{
    rooms: Array<{
      room_hash: string;
      emojis?: string[];
      description?: string;
      created_at: number;
      expires_at: number;
      worker: string;
    }>;
  }>(relayUrl, '/rooms');
}
