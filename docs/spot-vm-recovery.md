# Spot VM Auto-Recovery

DNSCloak runs on a GCP Spot VM to save costs (~60% cheaper). Spot VMs can be preempted at any time, so we use GitHub Actions to automatically restart the VM when this happens.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SPOT VM AUTO-RECOVERY FLOW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   GitHub Actions (every 5 minutes)                                           │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │  1. Authenticate to GCP using service account                      │    │
│   │  2. Check VM status via gcloud compute instances describe          │    │
│   │  3. If TERMINATED → gcloud compute instances start                 │    │
│   │  4. Check /health endpoint for service health                      │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                              │                                               │
│                              ▼                                               │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │                    GCP Spot VM (dnscloak)                          │    │
│   │  Zone: europe-west3-c                                              │    │
│   │  Machine: n2d-highcpu-8                                            │    │
│   │  IP: 34.185.221.241 (static)                                       │    │
│   │                                                                    │    │
│   │  Services:                                                         │    │
│   │  - Xray (Reality, WS, VRAY)                                       │    │
│   │  - DNSTT (DNS tunnel)                                             │    │
│   │  - WireGuard                                                       │    │
│   │  - Conduit (Psiphon relay)                                        │    │
│   │  - SOS Relay (emergency chat)                                     │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                              │                                               │
│                              │ POST /push (every 5 seconds)                 │
│                              ▼                                               │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │              Cloudflare Worker (stats.dnscloak.net)                │    │
│   │                                                                    │    │
│   │  GET /health  → Aggregated health status                          │    │
│   │  GET /current → Full stats JSON                                   │    │
│   │  WebSocket /  → Real-time stats stream                            │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                              │                                               │
│                              ▼                                               │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │              Website (dnscloak.net)                                │    │
│   │                                                                    │    │
│   │  Status popup shows:                                              │    │
│   │  - Overall health (up/degraded/down)                              │    │
│   │  - Per-service status                                             │    │
│   │  - VM specs and uptime                                            │    │
│   │  - Last update timestamp                                          │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Setup Instructions

### 1. Create GCP Service Account (Local)

Run these commands on your local machine:

```bash
# Create the service account
gcloud iam service-accounts create github-vm-manager \
  --project=noteefy-85339 \
  --display-name="GitHub Actions VM Manager"

# Grant compute admin permissions
gcloud projects add-iam-policy-binding noteefy-85339 \
  --member="serviceAccount:github-vm-manager@noteefy-85339.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

# Export JSON key
gcloud iam service-accounts keys create ~/github-gcp-key.json \
  --iam-account=github-vm-manager@noteefy-85339.iam.gserviceaccount.com

# View the key (copy this for GitHub Secrets)
cat ~/github-gcp-key.json
```

### 2. Add Secret to GitHub

1. Go to your repo: https://github.com/behnamkhorsandian/DNSCloak/settings/secrets/actions
2. Click **New repository secret**
3. Name: `GCP_SA_KEY`
4. Value: Paste the entire JSON key from step 1
5. Click **Add secret**

### 3. Workflow File

The workflow is already created at `.github/workflows/spot-vm-watchdog.yml`. It runs every 5 minutes and:

1. Authenticates to GCP using the service account
2. Checks VM status
3. Starts the VM if it's TERMINATED
4. Checks the health endpoint for service status

### 4. Update Health Pusher on VM

The VM runs a health pusher script that reports service status. To update it:

```bash
# Copy the updated script to VM
gcloud compute scp services/conduit/stats-pusher.sh \
  dnscloak:/tmp/stats-pusher.sh \
  --zone=europe-west3-c \
  --project=noteefy-85339

# Install and restart
gcloud compute ssh dnscloak \
  --zone=europe-west3-c \
  --project=noteefy-85339 \
  --command="sudo cp /tmp/stats-pusher.sh /opt/conduit/stats-pusher.sh && sudo systemctl restart conduit-stats"
```

### 5. Deploy Worker

Deploy the updated Cloudflare Worker with the `/health` endpoint:

```bash
cd workers
npm run deploy
```

## Testing

### Manual Workflow Trigger

```bash
# Trigger the watchdog manually
gh workflow run spot-vm-watchdog.yml
```

### Check Health Endpoint

```bash
# Check aggregated health
curl -s https://stats.dnscloak.net/health | jq .

# Expected response:
{
  "status": "up",
  "services": {
    "conduit": "up",
    "xray": "up",
    "dnstt": "up",
    "wireguard": "not_installed",
    "sos": "not_installed"
  },
  "system": {
    "machine": "n2d-highcpu-8",
    "vcpus": 8,
    "ram": "7.8G",
    "bandwidth": "16 Gbps"
  },
  "uptime": "12h 34m",
  "connected": 312,
  "last_update": 1738252800,
  "age_seconds": 5,
  "stale": false
}
```

### Simulate Preemption

To test the auto-recovery:

```bash
# Stop the VM (simulates preemption)
gcloud compute instances stop dnscloak \
  --zone=europe-west3-c \
  --project=noteefy-85339

# Watch the workflow logs - it should restart within 5 minutes
gh run watch
```

## Health Status Meanings

| Status | Meaning |
|--------|---------|
| `up` | All installed services are running |
| `degraded` | Some services are down |
| `down` | VM offline or stats stale > 60s |
| `unknown` | No stats received yet |

## Service Status Meanings

| Status | Meaning |
|--------|---------|
| `up` | Service is running |
| `down` | Service installed but not running |
| `not_installed` | Service not found on VM |
| `unknown` | Status check failed |

## Cost Analysis

| Component | Monthly Cost |
|-----------|-------------|
| n2d-highcpu-8 Spot VM | ~$37 |
| Static IP | $4 |
| Boot disk (10GB) | $1 |
| GitHub Actions | FREE (public repo) |
| **Total** | **~$42/month** |

Compare to standard VM: ~$100/month → **60% savings**

## Troubleshooting

### Workflow Fails to Authenticate

Check that:
1. `GCP_SA_KEY` secret is set correctly (valid JSON)
2. Service account has `compute.instanceAdmin.v1` role
3. Service account is not disabled

### VM Doesn't Start

1. Check VM quotas: `gcloud compute regions describe europe-west3`
2. Check Spot VM availability in the zone
3. Try a different zone if persistent failures

### Services Don't Start After Boot

All services are configured with `enable` in systemd. If they don't start:

```bash
# SSH to VM and check
gcloud compute ssh dnscloak --zone=europe-west3-c --project=noteefy-85339

# Check service status
sudo systemctl status xray dnstt wg-quick@wg0 conduit

# Check boot logs
journalctl -b -u xray
```

### Health Endpoint Returns Stale

1. Check if `conduit-stats` service is running on VM
2. Check if Cloudflare Worker is deployed correctly
3. Check firewall allows outbound HTTPS from VM
