# Tuntas

Platform customer experience omnichannel yang berdaulat — self-hosted, data 100% di Indonesia, tanpa batasan jumlah agent.

Tuntas menyatukan seluruh percakapan pelanggan (WhatsApp, Instagram, Facebook, TikTok, Telegram, Line, SMS, email, dan live chat website) ke dalam satu inbox, lengkap dengan help center, automation, campaign, CSAT, laporan performa, dan dukungan multi-tenant untuk BPO.

## Fitur Utama

- **Omnichannel Inbox** — 12 channel dalam satu antarmuka, dengan penggabungan kontak lintas kanal.
- **Kolaborasi Tim** — private notes, @mention, auto-assignment, teams, capacity routing.
- **Automation & Produktivitas** — automation rules, macros, canned responses, business hours.
- **Help Center** — portal artikel self-service untuk mengurangi volume pertanyaan berulang.
- **Campaign** — proactive chat & broadcast terjadwal.
- **Laporan & CSAT** — laporan agent/inbox/team/label, survey kepuasan pelanggan otomatis.
- **Multi-tenant** — satu instance melayani banyak akun terisolasi (cocok untuk model BPO).
- **API & Webhook Lengkap** — Platform API untuk provisioning tenant, widget SDK untuk embed.

## Development

```bash
bundle install && pnpm install
pnpm dev            # atau: overmind start -f ./Procfile.dev
```

- Lint: `pnpm eslint` / `bundle exec rubocop -a`
- Test: `pnpm test` / `bundle exec rspec`
- Seed data: `bundle exec rails db:seed`

Lihat `AGENTS.md` untuk panduan development lengkap.

## Deployment

Stack produksi: Rails + Sidekiq + PostgreSQL (pgvector) + Redis. Referensi tersedia di `docker-compose.production.yaml` dan direktori `deployment/`.

Catatan: telemetry ke hub upstream **nonaktif secara default** — seluruh panggilan keluar di `lib/tuntas_hub.rb` hanya aktif jika env `ENABLE_HUB_TELEMETRY` diset.

## Lisensi & Atribusi

Tuntas dibangun di atas kode inti [Chatwoot](https://github.com/chatwoot/chatwoot) yang berlisensi MIT — lihat file `LICENSE` (notis copyright asli wajib dipertahankan sesuai ketentuan MIT). Direktori `enterprise/` upstream (berlisensi komersial terpisah) **telah dihapus seluruhnya** dari codebase ini; fitur premium (SLA, SAML SSO, audit logs, custom roles, AI assistant) akan ditulis ulang secara mandiri sebagai bagian dari roadmap internal.
