# Captain AI Rewrite Plan

Captain adalah fitur premium terakhir yang belum ditulis ulang. Ukurannya ±7× SLA:
**81 file spec MIT** di history (`git show develop:spec/enterprise/...`) — 31 services,
12 controllers, 12 jobs, 8 models, 11 lib, 4 builders, 2 listeners, 1 policy.

Aturan legal tetap: kerjakan clean-room dari spec MIT + schema + frontend MIT.
Jangan pernah membuka kode Ruby `enterprise/` upstream.

## Fondasi yang SUDAH tersedia (MIT, di tree)

- `lib/llm/` — config, feature_router, models, exception_trackable + `config/llm.yml`
- Gem `ruby_llm` + `ruby_llm-schema` di Gemfile
- 9 tabel `captain_*` di `db/schema.rb` (termasuk pgvector untuk embeddings)
- Seluruh factories: `spec/factories/captain/*`
- Seluruh frontend: `app/javascript/dashboard/routes/dashboard/captain/**` + 16 API client
- Routes API captain di `config/routes.rb`

## Fase (masing-masing: restore spec → RED → implement → GREEN → commit)

1. **C1 — Tools framework + model core**
   `Captain::Tools::{BaseTool?,HttpTool,FaqLookupTool,HandoffTool}` (dituntut spec assistant),
   concern `CaptainToolsHelpers`, model `Assistant` (validasi audience-tree, response_window,
   auto_resolve), `Document`, `AssistantResponse`, `CustomTool`, `Scenario`, `MessageReport`,
   `AgentSession`, join `Captain::Inbox`. Spec: `spec/enterprise/models/captain/*` (8 file, ±1.8k baris)
   + `spec/enterprise/lib/captain/tools/*`.
2. **C2 — LLM chat service layer**
   Chat completion via ruby_llm (endpoint OpenAI-compatible dapat dioverride lewat
   `CAPTAIN_OPEN_AI_ENDPOINT`), embeddings + pencarian vektor dokumen/response.
   Spec: `spec/enterprise/services/captain/llm/*`.
3. **C3 — Assistant runtime**
   Response builder jobs (jawab percakapan), FAQ suggestion mining, document crawl/sync.
   Spec: `spec/enterprise/jobs/captain/*`, `services/captain/*`.
4. **C4 — Copilot** (thread + message + response job untuk agent).
5. **C5 — API controllers + stats builders** (assistants, documents, responses, scenarios,
   tools, copilot, bulk actions, inboxes) — frontend MIT langsung menyala setelah ini.

## Catatan verifikasi

- Jalankan tiap fase di Docker (pgvector image sudah dipakai rig verifikasi).
- Embedding spec kemungkinan menstub OpenAI (webmock) — tidak butuh API key nyata.
- Feature flags terkait: `captain_integration`, `captain_integration_v2` (features.yml).
