# Pingraph

[![CI](https://github.com/vdw/pingraph/actions/workflows/ci.yml/badge.svg)](https://github.com/vdw/pingraph/actions/workflows/ci.yml)

**Network Latency & Uptime Monitoring for Self-Hosted Environments**

Pingraph is a modern, self-hosted monitoring tool that tracks network performance and service health. Built for network engineers and IT teams who need a lightweight, web-based alternative to legacy tools like SmokePing.

Monitor latency trends, packet loss, and service availability in real-time with beautiful dashboards and public status pages.

---

## Features

### Multi-Protocol Monitoring
- **ICMP (Ping)** — Classic latency and packet loss monitoring
- **HTTP** — Web service health checks with custom status codes and SSL verification
- **TCP** — Port availability and connectivity checks

### Dashboards & Visualization
- **Live Dashboard** — Real-time host status with color-coded health indicators (up/degraded/down)
- **Latency Charts** — SmokePing-style visualization with min/avg/max trends over time
- **Public Status Pages** — Share service status with users without requiring login
- **Speed Tests** — On-demand throughput tests using iperf3

### Monitoring & Alerts
- **Configurable Thresholds** — Set latency thresholds for degraded state (default: 350ms)
- **Health Status Tracking** — Automatic status transitions (up → degraded → down)
- **Historical Data** — 90-day retention with configurable cleanup (30/60/90 days)
- **Grouped Organization** — Organize hosts by service, location, or team

---

## Use Cases

- **Uptime Monitoring** — Track availability of critical services and infrastructure
- **Latency Analysis** — Monitor network performance to identify congestion or issues
- **Service Health** — Check web services, APIs, and TCP ports from your network
- **Performance Trending** — Long-term latency trend analysis with 90-day historical data
- **Team Communication** — Public status pages to share uptime metrics with stakeholders

---

## Quick Start

### Requirements
- Docker & Docker Compose (recommended) or standalone server
- Linux, macOS, or Windows (WSL2)

### Docker (Simplest)

```bash
docker run -d \
  --name pingraph \
  -p 3000:80 \
  --cap-add=NET_RAW \
  -e RAILS_MASTER_KEY="$(openssl rand -base64 32)" \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v pingraph_storage:/rails/storage \
  ghcr.io/vdw/pingraph:latest
```

Open [http://localhost:3000](http://localhost:3000) and sign in with:
- **Email:** `admin@pingraph.local`
- **Password:** `pingraph123`

> **Important:** Change credentials after first login!

### Manual Setup (Development)

```bash
git clone https://github.com/vdw/pingraph.git
cd pingraph
bundle install
bin/rails db:prepare db:seed
bin/dev
```

Then open [http://localhost:3000](http://localhost:3000)

---

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `RAILS_MASTER_KEY` | — | **Required.** Encryption key for credentials. Generate with: `openssl rand -base64 32` |
| `TIME_ZONE` | `UTC` | Set dashboard timezone (e.g., `Eastern Time (US & Canada)`, `Europe/London`, `Asia/Tokyo`) |
| `SOLID_QUEUE_IN_PUMA=true` | — | For single-container deployments (runs scheduler + worker together) |

### First Steps After Login

1. **Create Groups** — Organize hosts by service or location (e.g., "Web Servers", "Database Servers")
2. **Add Hosts** — Monitor services:
   - **Ping a host:** `1.1.1.1` (ICMP)
   - **Check a website:** `https://example.com` (HTTP)
   - **Monitor a port:** `192.168.1.10:443` (TCP)
3. **Set Thresholds** — Adjust latency thresholds (default 350ms) to match your needs
4. **Create Status Pages** — Enable public status page for each group to share with users

---

## How It Works

**Polling:** Every minute, Pingraph checks each monitored host according to its configured interval (minimum 10 seconds).

**Latency & Loss:** Probes capture min/average/max latency and packet loss percentage.

**Status Calculation:** Hosts automatically transition between states:
- **Up** — Successful probe, latency within threshold
- **Degraded** — Successful probe but high latency, or 1-2 consecutive failures
- **Down** — 2+ consecutive probe failures
- **Unknown** — Never probed

**Data Retention:** Results are kept for 90 days by default, configurable in Settings.

---

## Deployment

### Docker Compose Example

```yaml
version: '3.8'
services:
  pingraph:
    image: ghcr.io/vdw/pingraph:latest
    ports:
      - "3000:80"
    environment:
      RAILS_MASTER_KEY: "${RAILS_MASTER_KEY}"
      TIME_ZONE: "UTC"
      SOLID_QUEUE_IN_PUMA: "true"
    volumes:
      - pingraph_storage:/rails/storage
    cap_add:
      - NET_RAW
    restart: unless-stopped

volumes:
  pingraph_storage:
```

Deploy with:
```bash
export RAILS_MASTER_KEY=$(openssl rand -base64 32)
docker-compose up -d
```

### Systemd Service

For bare-metal deployments, use systemd to manage the Rails process:

```ini
[Unit]
Description=Pingraph Network Monitor
After=network.target

[Service]
User=pingraph
WorkingDirectory=/opt/pingraph
ExecStart=/opt/pingraph/bin/rails server -p 3000
Environment="RAILS_ENV=production"
Environment="RAILS_MASTER_KEY=<your-key>"
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### Production Checklist

- [ ] Change default admin credentials
- [ ] Generate new `RAILS_MASTER_KEY` (never use the example)
- [ ] Configure TIME_ZONE for your location
- [ ] Set up persistent volume or backup strategy for database
- [ ] Use reverse proxy (nginx/HAProxy) with HTTPS
- [ ] Review network access controls
- [ ] Configure DNS or static IP for stability
- [ ] Set data retention policy (Settings → Ping Retention)

---

## Monitoring Your Monitors

To ensure probes are running:

1. **Check Dashboard** — All hosts should show "Last Seen" timestamps within their interval
2. **Verify Background Jobs** — Look for recent "Last Seen" updates (should be every 1-2 minutes)
3. **Monitor Database Size** — SQLite file growth (typically ~1 MB per 1000 hosts/month)

---

## Troubleshooting

### Hosts not probing?
- Check host interval is at least 10 seconds
- Verify network connectivity from Pingraph to target (can you ping it from the server?)
- Check logs: `docker logs pingraph` (or `tail -f log/production.log`)

### High CPU or Memory?
- Reduce polling interval (slower frequency) if you have many hosts
- Enable data retention cleanup (Settings page)
- For 1000+ hosts, consider distributing probes across multiple servers

### Docker permission error?
- Add `--cap-add=NET_RAW` to enable ICMP ping
- Verify container is not running as unprivileged user without capability

### Status page not showing?
- Ensure group is marked "Public status page" in group settings
- Check status_slug is valid (lowercase letters, numbers, hyphens only)

---

## Advanced Configuration

### Data Retention Policies
Default: 90 days. Change in Settings → Ping Retention.
- **30 days** — Lightweight monitoring, high retention for large deployments
- **60 days** — Balanced approach, 2-month trend analysis
- **90 days** — Full quarter trend analysis, uses more storage

### Latency Thresholds
Each host has a configurable latency threshold (default 350ms):
- Mark as **Degraded** if latency exceeds threshold (but still responding)
- Different expectations for ICMP (network latency) vs HTTP (app response time)
- Override per-host as needed

### Interval Configuration
Each host polls at its configured interval (minimum 10 seconds):
- **10-30s** — Critical services, rapid detection of failures
- **60s** — Standard monitoring, recommended for most services
- **300s** — Lightweight monitoring, useful for historical trend data

---

## Technical Stack

Built with modern, self-hosted-friendly technologies:

- **Framework** — Rails 8.1 (Ruby web framework)
- **Database** — SQLite 3 (zero-configuration, file-based)
- **Scheduler** — Solid Queue (built-in Rails job scheduler)
- **Interface** — Clean, responsive web UI with real-time updates
- **Deployment** — Docker containers for easy deployment

---

## Git Hooks

Commits can automatically run tests to catch issues early.

Enable hooks once per clone:

```bash
git config core.hooksPath .githooks
```

Or skip tests for an exceptional commit:

```bash
SKIP_TESTS=1 git commit -m "..."
```

---

## License

MIT

---

## Support

For issues, questions, or feature requests, see the GitHub repository:
https://github.com/vdw/pingraph

