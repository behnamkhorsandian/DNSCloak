# SOS Client + Relay Updates

## Summary
- Built a React/Vite SOS client app with shadcn/ui, Tailwind, and Capacitor scaffolding.
- Added SOS end-to-end encryption (argon2 + NaCl) and SOS relay API integration.
- Implemented fixed-PIN only flow and manual emoji selection for create/join.
- Added theme toggle, navbar, and lionsun banner.
- Updated relay to force fixed-mode rooms for consistency.

## Added
- `app/` Vite app scaffold (React + TypeScript)
- Tailwind + shadcn/ui utilities and base components
- SOS crypto module, API module, emoji picker, and config/types
- Theme provider + theme toggle + navbar
- Lionsun banner UI
- Capacitor config

## Updated
- `src/sos/relay.py` now forces fixed-mode room creation
- `app/src/App.tsx` wired for manual PIN + manual emoji selection (no rotation)
- `app/src/lib/sos-crypto.ts` fixed-mode crypto
- `app/src/index.css` banner interaction styles

## How to Run (Local)
### Relay
```bash
cd /home/pouria/projects/DNSCloak
python3 src/sos/relay.py --host 0.0.0.0 --port 8899
```

### App
```bash
cd /home/pouria/projects/DNSCloak/app
npm install
npm run dev -- --port 5175
```

## Notes
- Client defaults to relay: `http://relay.dnscloak.net:8899`
- For production, use HTTPS to avoid mixed-content issues.
- Web client in `src/sos/www/` remains unchanged (optional to align with fixed-PIN only).
