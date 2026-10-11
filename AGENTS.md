# AGENTS.md

Guidance for AI coding agents working in this repository. Humans: see `README.md` and `docs/`.

## Project overview

**jbirdkerr.net** is a personal interactive website hosted on GitHub Pages. It has an interactive canvas (a dog photo with eye-tracking, snoot booping, treat showers, party mode), WebAudio sound synthesis, a particle engine, and a real-time analytics pipeline.

Three deployable parts live in this one repo:

| Part | Location | Runtime / host |
| --- | --- | --- |
| Static site | `index.html`, `css/`, `js/`, `img/` | GitHub Pages (custom domain via `CNAME`) |
| Metrics worker | `metrics-worker/` | Cloudflare Workers (Python) |
| Database schema | `supabase/` | Supabase (PostgreSQL) |

Analytics flow: browser (PostHog SDK) -> Cloudflare Worker proxy -> PostHog Cloud **and** Supabase (dual-write). A live stats modal in the site polls the worker with HTMX.

## Repository layout

```
.
├── index.html            # Semantic HTML skeleton
├── css/style.css         # Layout, animations, modals, retro styling
├── js/main.js            # Audio synthesis, particle engine, tracking, UI logic
├── img/                  # Dog photos (png for display, jpg high-res source)
├── docs/                 # architecture.md, metrics-pipeline.md, api.md
├── metrics-worker/
│   ├── worker.py         # Python Cloudflare Worker (PostHog proxy + Supabase metrics)
│   ├── pyproject.toml    # Worker runtime config
│   └── wrangler.toml     # Worker deployment settings
├── supabase/
│   ├── migrations/       # Schema + RPC migrations (timestamped SQL)
│   └── config.toml
├── .github/workflows/    # static.yml publishes the site to GitHub Pages
├── pyproject.toml, uv.lock          # Root Python tooling (uv)
├── wrangler.toml                    # Root Wrangler config
└── .pre-commit-config.yaml
```

## Setup and commands

- **Static site:** there is no build step. Open `index.html` in a browser or serve the repo root with any static server (e.g. `python -m http.server`). Pushes to `main` publish via GitHub Actions.
- **Python tooling:** the repo uses `uv` (`uv.lock`). Use `uv sync` to install dependencies.
- **Pre-commit:** `.pre-commit-config.yaml` is present. Run the hooks before committing (e.g. `uv run pre-commit run --all-files`) and fix anything they flag rather than bypassing them.
- **Deploy the worker:** `npx wrangler deploy --env production`
- **Set a worker secret:** `npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY --env production`
- **Database:** apply SQL in `supabase/migrations/` to the Supabase project (the initial schema defines the atomic RPC `record_site_events`).

Do not deploy, push secrets, or run migrations against production unless explicitly asked.

## Metrics worker (`metrics-worker/worker.py`)

Served at `metrics-api.jbirdkerr.net`. Endpoints:

| Route | Purpose |
| --- | --- |
| `GET /metrics` | Reads `site_metrics` and `site_event_counts` from Supabase, returns an HTML fragment for HTMX. Cache: `public, max-age=2, s-maxage=3`. Excludes internal PostHog `$*` events. Embeds ISO UTC times in `data-utc` attributes. |
| `POST /i/v0/e/`, `POST /batch` | Proxies events to `us.i.posthog.com`, then persists to Supabase in the background via `ctx.waitUntil` (calls `POST /rest/v1/rpc/record_site_events`). Payloads may be JSON, URL-encoded, base64, or gzipped. |
| `GET /static/*`, `GET /array/*` | Proxies PostHog SDK scripts from `us-assets.i.posthog.com`. 24h edge cache, CORS `*`. Exists to avoid ad-blocker interference. |
| `GET /health` | Liveness probe; returns `{"status": "ok", "timestamp": ...}` with `no-store`. |
| `OPTIONS *` | Dynamic CORS preflight. Echoes `Access-Control-Request-Headers`. |

Conventions to preserve:

- **Allowed origins** are `https://jbirdkerr.net`, `https://www.jbirdkerr.net`, `https://henry.jbirdkerr.net`, and `https://jbirdkerr.github.io`. Validate `Origin` against this list; never widen it to `*` for the dynamic endpoints.
- **Persistence must not block the proxy response.** Supabase writes happen in `ctx.waitUntil`; the client gets PostHog's response.
- **Config:** `POSTHOG_PROJECT_ID` and `SUPABASE_URL` are plain vars in `wrangler.toml`. `SUPABASE_SERVICE_ROLE_KEY` is a secret and must only be set through Wrangler.
- Keep the Worker compatible with Cloudflare's **Python Workers** runtime (check what packages and stdlib features are supported before adding dependencies).

## Frontend (`index.html`, `css/`, `js/`)

- Vanilla HTML/CSS/JS, no framework or bundler. Keep it that way unless asked.
- Keep `index.html` a clean semantic skeleton; styling goes in `css/style.css`, behavior in `js/main.js`.
- The stats modal uses HTMX with 5-second polling against `/metrics`. If you change the response shape in the worker, update the modal markup and keep the 3-second edge cache in mind.
- Audio is synthesized with WebAudio (no audio asset files). Browsers require a user gesture before audio starts; don't add autoplay.
- Analytics events are captured with the PostHog SDK routed through the worker proxy. New tracked events should be named consistently with existing ones in `js/main.js`.

## Database (`supabase/`)

- Add new schema changes as **new timestamped migration files** in `supabase/migrations/`. Never edit an already-applied migration.
- Multi-event writes go through the `record_site_events` RPC so they stay atomic. Don't replace it with per-row inserts from the worker.
- The worker uses the service-role key, so keep RLS and grants in migrations deliberate.

## Documentation

- `docs/architecture.md`: system architecture and components
- `docs/metrics-pipeline.md`: sequence diagrams for ingestion and dashboard rendering
- `docs/api.md`: worker endpoint reference

When you change worker routes, caching, CORS, env vars, or the schema, update the matching doc in the same change. `docs/` is also published with the static site.

## Security and privacy

- Never commit secrets, service-role keys, or `.env` files. Check `.gitignore` before adding new local config.
- This is a privacy-conscious personal site: don't add new third-party trackers or collect additional personal data without being asked.
- Treat anything that touches `SUPABASE_SERVICE_ROLE_KEY` as sensitive; keep it server-side in the worker only.

## Licensing

Licensed under **AGPL-3.0** (see `LICENSE`). Don't introduce code or dependencies with incompatible licenses.

## Working style for agents

- Make small, focused changes that match the existing style. Prefer editing existing files over adding new ones.
- Don't add a build system, framework, or heavy dependency to the static site without asking.
- Verify frontend changes in a browser (canvas, audio, and modal behavior can't be checked by reading code alone).
- Summarize what you changed and flag anything you couldn't test (e.g. worker behavior that needs a deployed Cloudflare environment).
