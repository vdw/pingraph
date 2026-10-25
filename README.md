# Pingraph

[![CI](https://github.com/vdw/pingraph/actions/workflows/ci.yml/badge.svg)](https://github.com/vdw/pingraph/actions/workflows/ci.yml)

**Network Latency & Uptime Monitoring for Self-Hosted Environments**

Pingraph is a modern, self-hosted monitoring tool that tracks network performance and service health. Built for network engineers and IT teams who need a lightweight, web-based alternative to legacy tools like SmokePing.

Monitor latency trends, packet loss, and service availability in real-time with beautiful dashboards and public status pages.

---

## Features

### Multi-Protocol Monitoring
- **ICMP (Ping)** — Classic latency and packet loss monitoring
- **HTTP** — Web service checks: expected status, keyword (or keyword must be absent), redirects, any method with headers, body and basic auth, configurable timeout, and certificate expiry warnings
- **TCP** — Port availability and connectivity checks
- **DNS** — Resolve a name (A, AAAA, CNAME, MX, NS or TXT) through your own resolver or the system's, optionally checking the answer
- **Push** — Cron jobs, backups and scripts call a URL when they run; the host goes down when the calls stop (same URL format as Uptime Kuma)
- **Docker** — Container is running and healthy, through the Docker socket or a socket proxy
- **Redis** — `PING` with optional password (also Valkey and KeyDB)

### Dashboards & Visualization
- **Live Dashboard** — Real-time host status with color-coded health indicators (up/degraded/down)
- **Latency Charts** — SmokePing-style visualization with min/avg/max trends over time
- **Public Status Pages** — Share service status with users without requiring login
- **Speed Tests** — On-demand throughput tests using iperf3

### Monitoring & Alerts
- **Notifications** — Slack, email, Telegram, ntfy and webhook alerts on status changes (Down, Degraded, and recovery), with per-host control and a built-in "Send test notification" button
- **Configurable Thresholds** — Set latency thresholds for degraded state (default: 350ms)
- **Health Status Tracking** — Automatic status transitions (up → degraded → down)
- **Historical Data** — 90-day retention with configurable cleanup (30/60/90 days)
- **Grouped Organization** — Organize hosts by service, location, or team

### Accounts
- **Several users** — Add and remove people from the Users page; new users get a temporary password
- **Two-factor authentication** — Codes from any authenticator app, with one-time recovery codes

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
  -e SOLID_QUEUE_IN_PUMA=true \
  -v pingraph_storage:/rails/storage \
  ghcr.io/vdw/pingraph:latest
```

Open [http://localhost:3000](http://localhost:3000) and sign in with:
- **Email:** `admin@pingraph.local`
- **Password:** `pingraph123`

You'll be asked to choose a new password straight away. To skip the default, set
`PINGRAPH_ADMIN_EMAIL` and `PINGRAPH_ADMIN_PASSWORD` on the first start instead.

No master key is needed: the session secret and the encryption key are generated on first boot
and kept in the `pingraph_storage` volume, next to the database. Keep that volume persistent.

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
| `SECRET_KEY_BASE` | auto-generated | *Optional.* Signs session cookies. If unset, one is generated on first boot and stored in `storage/secret_key_base`. |
| `PINGRAPH_ADMIN_EMAIL` / `PINGRAPH_ADMIN_PASSWORD` | `admin@pingraph.local` / `pingraph123` | *Optional.* The first admin account, created on first boot only. Without a password set here, the default must be changed at first sign-in. |
| `TIME_ZONE` | `UTC` | Set dashboard timezone (e.g., `Eastern Time (US & Canada)`, `Europe/London`, `Asia/Tokyo`) |
| `SOLID_QUEUE_IN_PUMA=true` | — | For single-container deployments (runs scheduler + worker together) |
| `JOB_THREADS` | `5` | Threads for the probe worker. Probes mostly wait on the network, so raise this if you monitor many hosts (see *Capacity* under [How It Works](#how-it-works)). Alerts always have their own worker. |
| `APP_HOST` | `localhost` | Host used in email links when no **Base URL** is set in Settings |
| `MAILER_FROM` | `pingraph@localhost` | Sender address for emails when no **From address** is set in Settings |
| `ACTIVE_RECORD_ENCRYPTION_*` | auto-generated | *Optional.* Supply your own keys for encrypting notification secrets (`PRIMARY_KEY`, `DETERMINISTIC_KEY`, `KEY_DERIVATION_SALT`). If unset, a key is generated and stored in `storage/`. |

### First Steps After Login

1. **Create Groups** — Organize hosts by service or location (e.g., "Web Servers", "Database Servers")
2. **Add Hosts** — Monitor services:
   - **Ping a host:** `1.1.1.1` (ICMP)
   - **Check a website:** `https://example.com` (HTTP)
   - **Monitor a port:** address `192.168.1.10`, port `443` (TCP)
   - **Check your Pi-hole answers:** name `nas.lan`, DNS server `192.168.1.2`, expected value `192.168.1.10` (DNS)
   - **Know your backup ran:** a Push host, then call its URL at the end of the backup script (Push)
   - **Watch a container:** `nextcloud` (Docker; see [Docker checks](#docker-checks))
3. **Set Thresholds** — Adjust latency thresholds (default 350ms) to match your needs
4. **Create Status Pages** — Enable public status page for each group to share with users
5. **Set Up Notifications** — Add a Telegram bot, ntfy topic, Slack webhook, SMTP details or your own webhook in Settings so you're alerted when a host goes down (see [Notifications](#notifications))

---

## Notifications

Get alerted the moment something breaks — no need to watch the dashboard. Configure channels in **Settings → Notifications**:

- **Base URL** — the address you use to reach Pingraph (e.g. `https://pingraph.mylan.home` or `http://192.168.1.50:3000`). Used to build the "View host" link inside each alert.
- **Slack** — paste an [Incoming Webhook](https://api.slack.com/messaging/webhooks) URL.
- **Email** — enter SMTP server details, credentials, and a recipient address.
- **Telegram** — create a bot with [@BotFather](https://t.me/BotFather) and paste its token. Send the bot a message, open `https://api.telegram.org/bot<token>/getUpdates` and copy `chat.id` as the Chat ID. To alert a group, add the bot to it (group IDs start with `-`).
- **ntfy** — enter your server and topic, e.g. `https://ntfy.sh/my-pingraph-alerts`, and subscribe to the same topic in the [ntfy app](https://ntfy.sh). Down alerts are sent at high priority. On the public ntfy.sh server anyone who knows a topic can read it, so use a long, hard-to-guess name, or your own server with an access token.
- **Webhook** — any URL that accepts a JSON POST: Home Assistant, n8n, Node-RED or your own script (see below).

Any combination of channels can be active at the same time. Click **Send test notification** to confirm your setup.

**Webhook body.** Each alert is POSTed with `Content-Type: application/json`:

```json
{
  "event": "down",
  "status": "down",
  "text": "Router is DOWN",
  "host": { "id": 12, "name": "Router", "group": "LAN", "url": "https://pingraph.mylan.home/hosts/12" },
  "error_message": "100% packet loss",
  "packet_loss": 100,
  "latency_ms": null,
  "status_code": null,
  "occurred_at": "2026-10-24T12:00:00Z",
  "certificate_expires_at": null
}
```

`event` is `down`, `degraded`, `recovery` or `cert_expiring`; `status` is the new state (`down`, `degraded` or `up`), or the current one for `cert_expiring`, which also sets `certificate_expires_at`. Fields that don't apply to the check are `null`. Any 2xx response counts as delivered.

**Delivery is retried.** Each alert is sent to each channel separately. If a channel fails, that channel is retried up to 5 times over about 6 minutes, without re-sending to channels that already worked. Every alert and its result is listed in the **Notification log** (linked from Settings). If an alert still can't be delivered, a red banner appears on every page until a later one succeeds, and you can retry it from the log.

**When alerts fire:** only on *status changes*, so a host that stays down produces one alert, not one per probe cycle.

- **Down** and **recovery** (back to Up) alerts are always sent.
- **Degraded** alerts are opt-in — enable *Also alert on Degraded* on a host.

Toggle alerting per host with **Send notifications for this host** on the host's edit page (on by default once a channel is configured).

**Security:** webhook URLs, ntfy topics and tokens, the Telegram bot token, SMTP passwords, and HTTP check headers, bodies and basic auth passwords are encrypted at rest. The encryption key is generated automatically on first boot and stored in `storage/` — keep that volume persistent (it already holds your database). To manage keys yourself, set the `ACTIVE_RECORD_ENCRYPTION_*` environment variables instead.

---

## Users and Two-Factor Authentication

**Users:** The Users page lists everyone who can sign in. *Add user* creates an account with a temporary password, shown once, which they replace at their first sign-in. Every user can change everything, including other users: there are no roles. You can reset another user's password (they're signed out everywhere), turn off their two-factor authentication, or remove them; your own account is changed on the Account page, and the last user can't be removed.

**Two-factor authentication:** On the Account page, choose *Set up*, scan the QR code with an authenticator app (2FAS, Aegis, Google Authenticator, 1Password, Bitwarden and others), and confirm with a code and your password. You then get 10 recovery codes: each signs you in once if you lose your phone, so store them somewhere safe. From then on, signing in asks for a code after your password. A code can't be used twice, and both turning two-factor off and replacing the recovery codes need your password. The secret is encrypted at rest like the notification secrets.

---

## How It Works

**Polling:** Every minute, Pingraph schedules each host's checks for the coming minute on exact slots, so a host set to 30 seconds is checked every 30 seconds (minimum 10 seconds). If the queue falls behind, late checks are skipped rather than piling up.

**HTTP checks:** A check passes when the final response (after following up to 10 redirects; set 0 to check the redirect itself) has the expected status and, if set, contains the keyword (or doesn't, when inverted). The keyword is case-sensitive and matched against the first 1 MB of the body. Custom headers and basic auth are sent only to the monitored URL's host, never to a host a redirect points to. The timeout (default 5 seconds) applies to connecting and to each read, and also to TCP checks. Hosts created before redirects were supported keep not following them until you change it.

**DNS checks:** The name is resolved through the DNS server you enter (an IP address such as `1.1.1.1` or your Pi-hole), or the resolver of the machine Pingraph runs on when left blank. The check fails when there's no record of the chosen type, or none equals the expected value when one is set (names compare without case or a trailing dot; for MX, enter the mail server's name). The resolve time is charted as latency.

**Push checks:** Saving a Push host creates a URL like `https://pingraph.example.com/api/push/<token>`. Call it with GET or POST whenever the job runs, for example `curl -fsS -m 10 "<url>"` at the end of a script. If no call arrives for one interval (plus 10 seconds), the check fails; with the default *Confirm after 2*, the host goes Down after two intervals. Add `?status=down&msg=...` to report a failure right away, and `ping=<ms>` to chart a duration. These are Uptime Kuma's push parameters, so existing scripts only need the new URL. The token is the only secret: anyone with the URL can report for that host. *New URL* on the host page replaces it. The URL uses the Base URL from Settings when set.

**Docker checks:** See [Docker checks](#docker-checks) for giving Pingraph access. A container passes when it is running, not paused and, if it has a health check, not *unhealthy* (a health check that is still *starting* passes). Exited containers fail with their exit code.

**Redis checks:** Sends `PING` and expects `PONG`, after `AUTH` when a password is set (leave the username blank for `requirepass`, or fill in both for an ACL user). The port defaults to 6379. TLS connections aren't supported.

**Certificate expiry:** HTTPS checks record when the server's certificate expires; the host page shows it. When it is within the host's warning window (default 14 days, blank to turn off), each notification channel gets one *certificate expires in N days* alert. A renewed certificate starts over. With *Verify SSL certificate* on, an expired certificate also fails the check.

**Latency & Loss:** Probes capture min/average/max latency, jitter (ICMP) and packet loss percentage. Failed checks have no latency, so timeouts don't show up as spikes on the chart.

**Status Calculation:** Status changes only on a streak, so one dropped packet doesn't raise an alert. The streak length is each host's **Confirm after N checks in a row** setting (default 2; Uptime Kuma's *Retries* plus one):
- **Up** — The latest check was clean
- **Degraded** — N problem checks in a row: slow (above the latency threshold), lossy (2 or more of 5 ping packets lost) or failed
- **Down** — N failed checks in a row
- **Unknown** — Never probed, or fewer than N checks so far and they had problems

**Capacity:** Each worker thread runs one check at a time, so roughly *hosts ≈ `JOB_THREADS` × interval ÷ check time*. A ping check takes about 1 second (3 seconds when the host doesn't answer); an HTTP, TCP, DNS, Docker or Redis check takes its response time, up to its timeout, and push checks cost almost nothing. With the default 5 threads and 60-second intervals that is about 300 ping hosts, or 100 if they could all be down at once. Size for the worst case: hosts are slowest to check exactly when they're down. The amber "checks are running late" banner tells you when to raise `JOB_THREADS`.

**Uptime %:** Measured over the time Pingraph was actually monitoring. If Pingraph itself was stopped, that time isn't counted as uptime; the status page shows how much of the day was monitored.

**Alerting:** When a host changes state, Pingraph sends notifications to every configured channel. Alerts fire on transitions only — a host that stays down produces a single alert, not one per probe cycle.

**Data Retention:** Results are kept for 90 days by default, configurable in Settings.

---

## Deployment

### Docker Compose Example

```yaml
services:
  pingraph:
    image: ghcr.io/vdw/pingraph:latest
    ports:
      - "3000:80"
    environment:
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
docker compose up -d
```

The image has a health check (`GET /health`), so `docker ps` shows the container as
*unhealthy* when checks stop running, not only when the web server is down.

### Docker checks

Docker hosts ask the Docker Engine API about a container. Pingraph needs access to it in one of two ways.

**Through a socket proxy (recommended).** Access to the Docker socket is equivalent to root on the machine, so give Pingraph a read-only proxy that only answers container queries, and set the host's *Docker host* to `tcp://docker-proxy:2375`:

```yaml
services:
  pingraph:
    # ... as above
  docker-proxy:
    image: tecnativa/docker-socket-proxy
    environment:
      CONTAINERS: 1   # allow /containers/... (read-only: POST is off by default)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
```

The same works for containers on another machine running such a proxy: `tcp://192.168.1.30:2375`.

**Through the socket directly.** Mount it and add the socket's group, since Pingraph doesn't run as root. Leave *Docker host* blank:

```yaml
    volumes:
      - pingraph_storage:/rails/storage
      - /var/run/docker.sock:/var/run/docker.sock
    group_add:
      - "999"   # the socket's group ID: stat -c %g /var/run/docker.sock
```

Pingraph itself only reads container status. With the socket mounted directly, though, a security hole in Pingraph would hand an attacker control of Docker, and with it the machine; the proxy limits that to reading container details.

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
Environment="SOLID_QUEUE_IN_PUMA=true"
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### Production Checklist

- [ ] Change the default admin password (you're prompted at first sign-in)
- [ ] Turn on two-factor authentication (Account page), especially if Pingraph is reachable from the internet
- [ ] Keep `storage/` persistent and back it up: it holds the database and the generated keys
- [ ] Configure TIME_ZONE for your location
- [ ] Set up persistent volume or backup strategy for database
- [ ] Use reverse proxy (nginx/HAProxy) with HTTPS
- [ ] Review network access controls
- [ ] Configure DNS or static IP for stability
- [ ] Set data retention policy (Settings → Ping Retention)

---

## Security Notice: Encryption Key in Older Docker Images

Docker images published between 2026-07-05 and 2026-10-24 (`sha-106faa7` through `sha-61dbd51`, and `latest` during that time) contained a pre-generated `storage/encryption.key`. Docker copies that file into a new named volume, so installs started from those images share an encryption key that anyone can extract from the public image. The key protects the Slack webhook URL and SMTP password stored in the database; on its own it gives no access to Pingraph, but it makes those secrets readable to anyone who also gets a copy of your database.

**What to do:** update to the current image and restart. On boot, Pingraph recognizes the published keys, generates a new one and re-encrypts your secrets, and logs a line starting with `[Pingraph]`. If your database (or a backup of it) has ever been copied somewhere you don't control, also regenerate your Slack webhook and change your SMTP password.

Installs that mount a host directory (`-v /some/path:/rails/storage`) instead of a named volume, or that set `ACTIVE_RECORD_ENCRYPTION_*`, are not affected. To rotate the key by hand at any time, run `bin/rails pingraph:rotate_encryption_key` and restart.

---

## Monitoring Your Monitors

A monitor that silently stops checking is worse than none, so Pingraph tells you:

- **Red banner** — "Hosts are not being checked" when the scheduler hasn't run for 3 minutes, usually because the background worker isn't running (set `SOLID_QUEUE_IN_PUMA=true` in a single container).
- **Amber banner** — "Checks are running late" when many checks start late or are skipped because the worker can't keep up. Raise `JOB_THREADS` or use longer intervals.
- **Stale badge** — a host with no check for 3 of its intervals (at least 3 minutes) shows *Stale* on the dashboard, and *No data* on the public status page, instead of its last status.
- **`GET /health`** — no login needed. Returns `200 {"status":"ok"}` while checks run and `503 {"status":"stalled"}` when they've stopped. Point another monitor at it, or rely on the Docker health check. (`/up` only says the web app booted.)
- **Heartbeat URL** — in **Settings → Monitoring health**, paste a ping URL from a service such as [healthchecks.io](https://healthchecks.io). Pingraph requests it every minute while checks are running, so you're alerted if Pingraph itself goes down. The URL is encrypted at rest.

Also keep an eye on database size: SQLite grows roughly 1 MB per 1000 hosts per month.

---

## Troubleshooting

### Locked out?
If email isn't set up, reset a password from the server. It prints a temporary password that must be changed at the next sign-in:
```bash
docker exec pingraph bin/rails pingraph:reset_password                      # when there's one user
docker exec pingraph bin/rails "pingraph:reset_password[you@example.com]"
```
With Email (SMTP) configured in Settings, the sign-in page also offers "Forgot password?".

Lost your phone and your recovery codes? Another user can turn off two-factor authentication for you on the Users page, or on the server:
```bash
docker exec pingraph bin/rails "pingraph:disable_two_factor[you@example.com]"
```

### Hosts not probing?
- Look for the red "Hosts are not being checked" banner: the background worker isn't running (`SOLID_QUEUE_IN_PUMA=true`)
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
- Mark as **Degraded** if latency exceeds threshold on 2 checks in a row (but still responding)
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

