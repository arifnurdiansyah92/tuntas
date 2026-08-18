# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Tuntas is a sovereign omnichannel customer-experience platform — a **hard fork of the Chatwoot MIT core** (no upstream merges planned). Style rules, lint/test commands, and PR conventions live in `AGENTS.md`; read it alongside this file.

## Fork Constraints (non-negotiable)

- The upstream `enterprise/` directory was **removed for licensing reasons** (proprietary Chatwoot Enterprise License). Never reintroduce, port, or copy from it. Premium features (SLA, SAML SSO, audit logs, custom roles, AI assistant, voice) must be **rewritten independently** — use the MIT-licensed specs from git history (`git show develop:spec/enterprise/...`) and the MIT frontend under `app/javascript` as the behavioral reference.
- Root `LICENSE` (MIT, Chatwoot Inc copyright) must be retained verbatim — an MIT requirement.
- Outbound telemetry in `lib/tuntas_hub.rb` is opt-in via `ENABLE_HUB_TELEMETRY`; keep every hub call behind that guard.
- The brand rename preserved these identifiers on purpose — do not "fix" them: the `@chatwoot/*` npm scope (real upstream packages we still depend on), `chatwoot.com` / `github.com/chatwoot` URLs in comments (upstream references), and `CW_EDITION`-style internals.

## Commands

```bash
bundle install && pnpm install     # setup
pnpm dev                           # run dev (or: overmind start -f ./Procfile.dev)
pnpm eslint / pnpm eslint:fix      # lint JS/Vue
bundle exec rubocop -a             # lint Ruby
pnpm test                          # JS tests (vitest)
bundle exec rspec spec/path/to/file_spec.rb[:LINE]   # Ruby test (single file/line)
bundle exec rails db:seed          # seed minimal data
```

Note: this Windows host has Node/pnpm and Docker but **no Ruby toolchain** — run Rails/RSpec work inside WSL or Docker.

## Architecture

Rails monolith + Vue 3 SPA, PostgreSQL (pgvector image), Redis, Sidekiq (priority queues defined in `config/sidekiq.yml`, cron in `config/schedule.yml`), ActionCable for realtime, Vite for frontend builds.

- **Multi-tenancy**: `Account` is the tenant root; users attach via `account_users`. Per-account feature flags are bitset columns mapped by position in `config/features.yml` — never reorder or remove entries; new flags append at the end with `column: feature_flags_ext_1`.
- **Channel layer**: each messaging channel is a `Channel::*` model (`app/models/channel/`) paired with an `Inbox`. Inbound provider events arrive at `app/controllers/webhooks/*`; outbound sends live in `app/services/`. Conversations hold Messages; contact identity is merged across channels via `ContactInbox`.
- **API surface** (`config/routes.rb`): `/api/v1` & `/api/v2` (dashboard), `/platform/api/v1` (instance-level provisioning of accounts/users/bots — the multi-tenant automation entry point), `/public/api/v1` (client-side), plus separate Vite entrypoints for the embeddable widget SDK (`window.$tuntas`), help-center portal, and CSAT survey pages.
- **Extension mechanism** (GitLab-style): `prepend_mod_with` / `include_mod_with` (see `config/initializers/01_inject_enterprise_edition_module.rb`) resolve overlay modules from the directories returned by `TuntasApp.extensions` — put new premium-feature rewrites in a `custom/` tree and inject through these hooks instead of editing core classes.
- **Frontend**: `app/javascript/dashboard` (agent app), `widget`, `portal`, `shared`. Message bubbles are being migrated to `components-next/`. Branding at runtime flows from `InstallationConfig` (`config/installation_config.yml`) through `shared/composables/useBranding` — user-visible product-name strings must come from there, never hardcoded.
- **i18n**: edit only `en.yml` (backend) / `en.json` (frontend). Other locales are a frozen snapshot from upstream (no Crowdin pipeline on this fork).
