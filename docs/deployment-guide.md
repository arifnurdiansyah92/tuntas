# Panduan Deploy Tuntas

Panduan ini mencakup **test deploy** (staging/uji internal) dan catatan pengerasan untuk
**production**. Tuntas adalah monolit Rails 7 + SPA Vue 3 dengan PostgreSQL (pgvector),
Redis, Sidekiq, dan ActionCable. Semua aset deploy sudah ada di repo — panduan ini hanya
merangkai urutannya.

## 1. Prasyarat

| Komponen | Versi / Image | Catatan |
|---|---|---|
| Docker + Docker Compose | terbaru | Jalur deploy yang direkomendasikan |
| PostgreSQL | `pgvector/pgvector:pg16` | Ekstensi **vector** wajib (embedding Captain) |
| Redis | `redis:alpine` | Cache, Sidekiq, ActionCable, lock Captain |
| Node | 24.x | Hanya jika build aset di luar Docker — `docker/Dockerfile` sudah memakai `node:24-alpine` di dalam image |
| Ruby | 3.4.4 | Hanya untuk deploy non-Docker |

## 2. Test deploy dengan Docker Compose (direkomendasikan)

Semua langkah dijalankan dari root repo pada host deploy.

### 2.1 Siapkan environment

```bash
cp .env.example .env
```

Minimal yang harus diisi di `.env`:

- `SECRET_KEY_BASE` — hex acak panjang (`openssl rand -hex 64`), alfanumerik saja.
- `FRONTEND_URL` — URL publik instance (mis. `https://staging.tuntas.id`).
- `POSTGRES_PASSWORD` — samakan dengan yang di `docker-compose.production.yaml`
  (service `postgres` → `POSTGRES_PASSWORD`).
- `REDIS_PASSWORD` — dipakai service redis (`--requirepass`) sekaligus dibaca aplikasi;
  biarkan `REDIS_URL=redis://redis:6379` apa adanya (password diambil dari variabel terpisah).
- `RAILS_ENV=production`, `INSTALLATION_ENV=docker` (sudah di-set compose).
- Opsional SMTP (`MAILER_SENDER_EMAIL`, `SMTP_*`) agar email undangan/reset berfungsi.

Telemetry hub **mati secara default** — hanya aktif jika `ENABLE_HUB_TELEMETRY` di-set.

### 2.2 Build image dan siapkan database

```bash
docker compose -f docker-compose.production.yaml build          # build image (aset frontend ikut ter-build via node:24 di dalam image)
docker compose -f docker-compose.production.yaml up -d postgres redis
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:tuntas_prepare
```

`db:tuntas_prepare` membuat database, memuat skema (termasuk ekstensi pgvector),
menjalankan migrasi, dan menanam data minimal. Untuk deploy ULANG (upgrade), cukup:

```bash
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:migrate
```

### 2.3 Jalankan aplikasi

```bash
docker compose -f docker-compose.production.yaml up -d rails sidekiq
```

- `rails` melayani web + API + ActionCable di port 3000 (pasang reverse proxy
  HTTPS — nginx/caddy — di depannya; WebSocket `/cable` ikut di-proxy).
- `sidekiq` memproses semua queue di `config/sidekiq.yml` **dan otomatis
  mendaftarkan cron** dari `config/schedule.yml` saat boot (termasuk cron Captain:
  auto-resolve tiap 30 menit dan re-sync dokumen tiap 6 jam). Tidak perlu crontab OS.

### 2.4 Bootstrap akun pertama

1. Buka `FRONTEND_URL` → wizard onboarding membuat akun + user pertama
   (user pertama otomatis menjadi super admin instalasi).
2. Panel super admin ada di `FRONTEND_URL/super_admin`.

## 3. Konfigurasi Captain AI

Captain butuh dua hal: **API key** di level instalasi dan **feature flags** per akun.

### 3.1 InstallationConfig (via super admin → App Config, atau console)

| Nama | Wajib? | Fungsi |
|---|---|---|
| `CAPTAIN_OPEN_AI_API_KEY` | **Wajib** | Semua fitur LLM: respons assistant, embedding FAQ, copilot, klasifikasi |
| `CAPTAIN_FIRECRAWL_API_KEY` | Opsional | Crawl website multi-halaman via Firecrawl (tanpa ini, crawl satu halaman tetap jalan) |
| `CAPTAIN_CLOUD_PLAN_LIMITS` | Opsional | JSON limit dokumen/respons per `plan_name` akun |
| `CAPTAIN_OPEN_AI_ENDPOINT` | Opsional | Override endpoint OpenAI-compatible (mis. proxy/self-hosted) |

Contoh via console:

```bash
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails runner \
  "InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').first_or_initialize.update!(value: 'sk-...')"
```

### 3.2 Feature flags per akun (super admin → Accounts → fitur)

| Flag | Fungsi |
|---|---|
| `captain_integration` | Mengaktifkan Captain di akun (UI + trigger balasan) |
| `captain_integration_v2` | Runtime V2: agent runner multi-skenario, sitasi, analitik outcome |
| `captain_tasks` | Auto-resolve mode *evaluated* (LLM menilai percakapan pending) |
| `custom_tools` | Custom HTTP tools untuk assistant |

### 3.3 Setup fungsional di dashboard

1. Buat **Assistant** (menu Captain) → hubungkan ke **Inbox**.
2. Isi pengetahuan: crawl dokumen / tulis FAQ / upload PDF.
3. Percakapan baru pada inbox tersebut berstatus **pending** — Captain membalas
   otomatis; handoff memindahkan ke agent (status open).

## 4. Smoke test setelah deploy

Urutan uji cepat (±15 menit):

1. **Boot**: `docker compose ... logs rails` bebas error; halaman login terbuka.
2. **Realtime**: buka dua browser, kirim pesan — percakapan muncul tanpa refresh (ActionCable OK).
3. **Widget**: pasang snippet widget di halaman uji; kirim pesan dari widget.
4. **Captain end-to-end**: inbox ber-assistant + `captain_integration` aktif → kirim
   pesan dari widget → balasan otomatis muncul; cek Sidekiq (`/sidekiq` super admin)
   queue `default/low` bergerak.
5. **Handoff**: minta "bicara dengan manusia" → status percakapan jadi open, template
   out-of-office terkirim bila di luar jam kerja.
6. **Copilot**: dari dashboard agent, buka panel Copilot → tanya sesuatu tentang
   percakapan yang sedang dibuka.
7. **Cron**: super admin → Sidekiq → Cron; pastikan entri `captain_*`, `sla`, dsb terdaftar.
8. **Email** (bila SMTP diisi): undang agent baru → email diterima.

## 5. Catatan pengerasan production

- **Backup**: volume `postgres_data` dan `storage_data` (lampiran ActiveStorage) wajib
  masuk jadwal backup. Untuk skala, arahkan ActiveStorage ke S3-compatible storage.
- **Skala**: `rails` dan `sidekiq` bisa direplikasi horizontal; keduanya stateless
  (state di Postgres/Redis).
- **Keamanan**: jangan expose port 5432/6379 keluar host; `docker-compose.production.yaml`
  sudah bind ke `127.0.0.1`. Aktifkan HTTPS di reverse proxy.
- **Observabilitas**: log JSON ke stdout (`docker logs`); exception tracker (Sentry
  DSN) via env bila tersedia.
- **Kuota Captain**: set `limits: { captain_responses: N }` per akun (super admin)
  bila ingin membatasi konsumsi LLM; saat habis, Captain otomatis handoff ke agent.
- **Belum tersedia di fork ini** (roadmap): fitur enterprise non-Captain upstream
  seperti voice/calls, agent capacity policies, companies CRM.

## 6. Verifikasi rilis (checklist CI sebelum tag)

1. `bundle exec rspec` — suite penuh hijau (di CI atau rig Docker; lihat
   `docs/captain-rewrite-plan.md` untuk konteks rewrite).
2. `bundle exec rails zeitwerk:check` — validasi eager-load produksi.
3. `bundle exec rubocop` dan `pnpm eslint`.
4. Build image Docker sukses (aset frontend ter-build di stage node:24).
