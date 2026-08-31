# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

NCAA Planner is a Rails API + React SPA with two independent feature sets sharing one auth/user system — don't assume models from one relate to the other:

1. **Recruiting/roster planner**: `User -> Team -> Squad -> PositionBoard -> Player`, `RosterSlot`. Lets a coach build depth charts, track recruits, and flag players.
2. **Dynasty tracker**: `User -> Dynasty -> Coach` / `Season -> Week -> Game`, `College -> CollegeSeason -> StudentSeason`, `CollegeGameStat` / `StudentGameStat`. Tracks a multi-season college football dynasty. Only some colleges are "coached" by real users (`college_season.coach_id` is null for the rest, which still exist as opponents/league context). Includes:
   - An AI pipeline that reads uploaded box-score/player-stat screenshots and extracts game results for review before saving.
   - A public, unauthenticated "broadcast" API that formats season/week data as JSON or Markdown, meant to be fed into an LLM-based podcast generator (e.g. NotebookLM) to produce a recap/preview show.

## Commands

### Backend (`backend/`, Rails API)
- `bin/rails server -p 3001` — dev server (frontend expects it on port 3001 via `VITE_API_URL`)
- `bin/rubocop` / `bin/rubocop -A` — lint / autofix (rubocop-rails-omakase base)
- `bin/rails db:migrate`, `bin/rails db:schema:load`
- `bin/rails console`, `bin/rails runner <script>` — useful for one-off data checks/backfills
- **No automated test suite exists** (no `spec/` or `test/` directory). Changes are currently verified manually (curl against the running server, `bin/rails runner` scripts, or the browser). Don't assume `rspec`/`rails test` will work.

### Frontend (`frontend/`, Vite + React)
- `npm run dev` — dev server on port 5173
- `npm run lint` — eslint
- `npm run build` / `npm run preview`

Backend and frontend are two independent processes with no combined dev command — start both separately. There's no proxy between them; the frontend talks to `VITE_API_URL` (defaults to `http://localhost:3001`) directly.

## Backend architecture

- **Auth**: Devise + devise-jwt. JWT is returned in the `Authorization` response header on sign-in/sign-up and must be sent back as `Authorization: Bearer <token>`. The frontend persists it in `localStorage`.
- **Authorization**: Pundit throughout. `Api::V1::BaseController` sets `after_action :verify_authorized, except: :index` and `after_action :verify_policy_scoped, only: :index`. Rails 7.1+ raises if a callback's `only:`/`except:` references an action the controller doesn't define — so any controller with no `index` action (most nested resource controllers) must `skip_after_action` both and call `authorize`/`policy_scope` manually inside each action. See `RosterSlotsController`, `SeasonsController`, or `GamesController` for the pattern before adding a new controller.
- **API namespacing**: everything lives under `api/v1`, resource-scoped via `policy_scope`. The exception is `SeasonBroadcastsController` (`dynasties/:dynasty_id/seasons/:season_id/{preview,weeks}`), which is intentionally public/unauthenticated. CORS is opened to `*` specifically for those two paths in `config/initializers/cors.rb`; everything else stays locked to `FRONTEND_URL`.
- **Serializers vs. presenters**: `app/serializers/` build the JSON response shape. `app/presenters/` (`SeasonPreviewMarkdownPresenter`, `SeasonWeeksMarkdownPresenter`, shared `PodcastShow` module) render that *same* already-built hash as Markdown for the broadcast endpoints — Markdown is derived from the JSON data, not re-queried from models, so the two formats can't drift apart.
- **AI game-stat extraction** (`app/services/game_stats/`): uploads box-score/player-stat screenshots and runs them through `ruby_llm` (Claude vision) using `RubyLLM::Schema` structured output, returning a *proposed* (unsaved) set of `CollegeGameStat`/`StudentGameStat` rows for the user to review before `GameStats::CommitService` persists them.
  - **Empirically-discovered constraint**: Anthropic's structured-output grammar compiler rejects schemas well before its documented 24-optional-parameter cap — in practice it's reliable around 5-10 optional fields per call, and *worse* for a variable-length array (e.g. an unknown number of players) than a fixed-length one (e.g. always-2 teams). This is why extraction is split into many small calls (`ImageClassifier` → `BoxScoreExtractor` across 4 field-groups → `PlayerCategoryExtractor` across 2 sub-groups per stat category) instead of one large one. Read the class comments in that directory before changing field counts on any schema there.
  - `ruby_llm-schema` is a transitive dependency of `ruby_llm` and is **not** auto-required — `config/initializers/ruby_llm.rb` has an explicit `require "ruby_llm/schema"` that must stay in place.
- **Storage**: ActiveStorage with Cloudinary (`CLOUDINARY_URL`) in both development and production. Uploaded screenshots are turned into blobs immediately at analyze-time (before the user confirms anything), then referenced by `signed_id` between the analyze and commit steps so they aren't re-uploaded.
- **Env vars** (`backend/.env`, loaded via dotenv-rails): `ANTHROPIC_API_KEY`, `CLOUDINARY_URL`.

## Frontend architecture

- Vite + React Router, no meta-framework. Pages in `src/pages/`, shared UI in `src/components/`.
- `src/lib/apiClient.js` wraps axios: the request interceptor snake_cases outgoing JSON bodies and the response interceptor camelCases incoming ones. Write frontend code in camelCase and let this handle conversion — don't hand-convert keys. The request interceptor explicitly skips `FormData` bodies (multipart uploads) since snake-casing would silently empty them.
- Design tokens (colors: `charcoal`/`burnt`/`olive`/`warmgray`/`success`/`warning`/`danger`/...; fonts: `font-varsity`/`font-crayon`/`font-chalk`) are defined in `tailwind.config.js` — reuse them rather than introducing new ad hoc colors or fonts.
