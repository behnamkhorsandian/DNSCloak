# Deploy SOS Chat Relay to Cloudflare Workers

This folder contains a Cloudflare Worker implementation of the SOS chat relay plus a React client copy.

## Prerequisites
- A Cloudflare account
- Wrangler installed (`npm install -g wrangler`) or use `npx wrangler`

## 1) Configure the Worker
- Worker code lives in `chat/worker/src/index.ts`
- Durable Object bindings are defined in `chat/worker/wrangler.toml`

If you want a different Worker name, update the `name` field in `chat/worker/wrangler.toml`.

## 2) Deploy the Worker
```bash
cd chat/worker
wrangler login
wrangler deploy
```

Wrangler will output a Worker URL like:
```
https://<your-worker>.<your-subdomain>.workers.dev
```

## 3) Point the React Client to the Worker
Update the relay URL in the chat React copy:
- File: `chat/react/src/lib/sos-config.ts`
- Field: `RELAY_URL`

Example:
```ts
RELAY_URL: 'https://<your-worker>.<your-subdomain>.workers.dev'
```

If you want to use the existing app instead, update:
- `app/src/lib/sos-config.ts`

## 4) Build and Serve the React Client
```bash
cd chat/react
npm install
npm run build
npm run preview
```

## Notes
- The Worker implements the same HTTP API as the Python relay in `src/sos/relay.py`.
- Room state is stored in Durable Objects. Rooms expire after 1 hour by default.
- The plain web client from `src/sos/www` is copied under `chat/sos/www` if you want a no-build option.
