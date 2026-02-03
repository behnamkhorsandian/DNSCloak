# DNSCloak SOS Chat: Decentralized Workers + Gossip

This document describes the current chat architecture, decentralized worker gossip, and the web app behavior.

## Overview

The SOS chat system is built on Cloudflare Workers with Durable Objects. It is decentralized at the worker level:

- Multiple Workers can serve the chat API.
- Workers gossip their URLs and room directories to each other.
- Each worker maintains a local directory of valid workers and active rooms.
- Rooms are owned by the worker that created them. Other workers forward room requests to the owner.

No extra dependencies are used for state coordination. The `SOSDirectory` Durable Object stores cluster metadata (workers + room directory) and gossips with other workers.

## Components

### 1) Chat Worker (API + Rooms)
Location: `chat/worker/src/index.ts`

Responsibilities:
- API endpoints for room creation, joining, sending messages, polling, and room info.
- Proxies room requests to the correct worker when the room is owned by another worker.
- Registers room metadata into the directory on creation.

### 2) SOSRoom Durable Object (per-room state)
Location: `chat/worker/src/index.ts` (`export class SOSRoom`)

Stores:
- Room metadata (hash, created_at, expires_at)
- Members
- Encrypted messages

Room TTL: 1 hour (room is deleted automatically after expiry).

### 3) SOSDirectory Durable Object (cluster metadata + gossip)
Location: `chat/worker/src/index.ts` (`export class SOSDirectory`)

Stores:
- Workers directory (URL, last_seen, last_ok, fail_count, is_genesis)
- Rooms directory (hash, emojis, description, worker, created_at, expires_at)
- Simple state summary (`directory_state`)

Gossip behavior:
- Each worker gossips to peers periodically (default ~30s).
- Each worker shares its known workers + room directory.
- Failed workers are removed after 5 failed gossips.
- New workers announce themselves to peers at startup.

## Genesis Workers

Genesis workers are the initial trusted seed list. They are always added to the local directory and tagged as `is_genesis`.

Configured in:
- `chat/worker/src/index.ts` → `GENESIS_WORKERS`
- `chat/app/src/lib/sos-config.ts` → `GENESIS_WORKERS`

Example:
```
https://dnscloak-sos-chat.pouriashy11.workers.dev
```

## Worker-to-Worker Gossip

Endpoints (handled by `SOSDirectory`):
- `POST /gossip` — Receive gossip from another worker.
- `GET /workers` — Local worker directory.
- `GET /rooms` — Local room directory.
- `POST /rooms/register` — Register room metadata after room creation.

Gossip payload includes:
- Worker list
- Room directory (hash, emojis, description, owner worker, expiration)

If a worker fails gossip more than 5 consecutive times, it is removed from the local directory.

## Room Directory (Decentralized)

When a room is created:
- The worker creates the room in `SOSRoom`
- It registers room metadata in `SOSDirectory`
- That metadata is gossiped to other workers

This enables:
- Listing available rooms across the network
- Joining a room from any worker (request is forwarded to the owner)

## API Summary

Public endpoints:
- `GET /health`
- `GET /workers`
- `GET /rooms`
- `POST /room` (create)
- `POST /room/<hash>/join`
- `POST /room/<hash>/send`
- `GET /room/<hash>/poll`
- `POST /room/<hash>/leave`
- `GET /room/<hash>/info`

Internal (directory/gossip):
- `POST /gossip`
- `POST /rooms/register`

## Web App

Location: `chat/app/src/App.tsx`

Key behaviors:
- Connects to genesis workers to load the worker list.
- Allows selecting a worker to use.
- Shows worker latency/health.
- Shows room list (including description).
- Joining a room requires the room emojis + PIN.

Room description:
- Created by the room creator (optional).
- Appears in room list and join page.
- Stored and gossiped via directory.

Usernames:
- Optional. If empty, a random `anon-xxxx` is generated.

## Deploying to Multiple Cloudflare Accounts

Use the same `chat/worker` config and deploy with different credentials:

Option A: Wrangler profiles
```
npx wrangler login --profile accountA
npx wrangler login --profile accountB

npx wrangler deploy --profile accountA
npx wrangler deploy --profile accountB
```

Option B: API tokens
```
CLOUDFLARE_API_TOKEN=... npx wrangler deploy
```

## Important Files

- Worker logic: `chat/worker/src/index.ts`
- Worker config: `chat/worker/wrangler.toml`
- Web app: `chat/app/src/App.tsx`
- App config: `chat/app/src/lib/sos-config.ts`
- API helpers: `chat/app/src/lib/sos-api.ts`

## Notes

- Rooms expire after 1 hour.
- Chat messages are end-to-end encrypted on the client.
- Directory is best-effort and eventually consistent via gossip.
