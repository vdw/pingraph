# Pingraph

[![CI](https://github.com/vdw/pingraph/actions/workflows/ci.yml/badge.svg)](https://github.com/vdw/pingraph/actions/workflows/ci.yml)

A modern, self-hosted network latency monitor for homelabs. Pingraph is a lightweight alternative to [SmokePing](https://oss.oetiker.ch/smokeping/) with a web-first configuration experience — no flat-file configs, no legacy CGI setup.

Organize hosts into groups, visualize latency trends with smoke-style charts (min/avg/max RTT over time), and monitor packet loss — all from a clean Tailwind UI.

---

## Stack

| Layer | Technology |
|---|---|
| Framework | Ruby on Rails 8.1 |
| Database | SQLite 3 (WAL mode) |
| Background jobs | Solid Queue (built-in Rails 8 scheduler) |
| Cache | Solid Cache |
| Asset pipeline | Propshaft + Importmaps |
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind CSS v4 |
| Charts | Chart.js 4 (ESM via esm.sh) |
| Auth | Rails 8 native authentication |
| Deployment | Docker + Kamal |

---

## Domain Model

- **Group** — logical container for hosts (e.g. "Internal Infrastructure", "External Services")
- **Host** — a monitored target (IP or hostname) with a configurable polling interval (minimum 10 s)
- **Ping** — a single probe result: `min_latency`, `latency` (avg), `max_latency` (ms), `packet_loss` (%), `recorded_at`

---

## Getting Started

**Requirements:** Ruby 4.x, `iputils-ping` (or equivalent), `NET_RAW` capability if running in Docker.

```bash
git clone git@github.com:vdw/pingraph.git
cd pingraph
bundle install
bin/rails db:prepare db:seed
bin/dev
```

Open [http://localhost:3000](http://localhost:3000) and sign in:

| Field | Value |
|---|---|
| Email | `admin@pingraph.local` |
| Password | `pingraph123` |

> Change these credentials after first login.

`bin/dev` starts three processes via `Procfile.dev`:
- `web` — Puma (Rails server)
- `css` — Tailwind CSS watcher
- `worker` — Solid Queue (runs `HostPollerJob` every minute)

---

## How It Works

`HostPollerJob` runs every minute via Solid Queue's built-in recurring scheduler. It checks each host's last probe time against its configured interval and enqueues a `PingJob` for any host that is due. `PingJob` calls `PingService`, which executes `ping -c 5 -q -W 2 <address>` and parses the summary output to extract min/avg/max RTT and packet loss percentage.

---

## Git Hooks

Commits can automatically run the test suite via a repository-managed `pre-commit` hook.

Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

This is also configured automatically when you run:

```bash
bin/setup --skip-server
```

To bypass the hook for an exceptional commit:

```bash
SKIP_TESTS=1 git commit -m "..."
```

---

## Docker

The included `Dockerfile` builds a production image.

Build and run locally:

```bash
docker build -t pingraph .
docker run -d \
  --name pingraph \
  -p 3000:80 \
  --cap-add=NET_RAW \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v pingraph_storage:/rails/storage \
  pingraph
```

Container requirements:

- `RAILS_MASTER_KEY` (production credentials)
- `SOLID_QUEUE_IN_PUMA=true` (runs recurring scheduler + queue worker in single-container mode)
- `NET_RAW` capability (required for ICMP ping)
- Persistent volume for `/rails/storage` (SQLite + Solid Queue/Cache/Cable databases)

Compose/Kamal capability setting:

```yaml
# docker-compose or Kamal config
cap_add:
  - NET_RAW
```

---

## License

MIT
