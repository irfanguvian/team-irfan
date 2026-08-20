# Agent memory — design and decision record

Per-agent, per-repository, persistent, deterministic. **Product and Lead
only** — QA persists its regression suite instead (see README §QA), and
executors get nothing: an executor's context is its task block and its
worktree, and memory there would be scope leak wearing a feature's name.

## Decision record — why not mem0

The mem0-style architecture (vector ANN + entity store + weighted score
fusion) is **rejected for v3**:

- **ANN is non-deterministic.** Team-irfan's trust model is "deterministic
  checks never delegated to prompts"; a retrieval layer that returns
  different rows on different days breaks every property the checks pin.
- **Anthropic has no embeddings API** — Haiku cannot embed. A vector store
  would smuggle in a second model vendor for the least-trusted layer.
- **Score fusion adds tuning knobs with no ground truth.** Nothing here can
  measure whether 0.7·semantic + 0.3·recency beats 0.6/0.4, so the knobs
  would be folklore within a week.

Retrieval is therefore **SQLite FTS5/BM25**: deterministic, zero new
dependencies, debuggable with one query. **Phase-2 (future, only if measured
misses justify it):** `sqlite-vec` + a local embedding model as an extra
signal — the log's zero-hit retrieval rate is the trigger, not taste. The
**entity store is dropped**; a `tags` column covers it. Kept from mem0:
metadata, hash-dedup, LLM extraction on ingest, and the
DECIDE/RETIRE/REFLECT maintenance loop.

## Layout

```
.team-irfan/memory/
  product.db    lead.db        # SQLite + FTS5
  product.md    lead.md        # compiled always-load views (generated only)
  memory.log                   # one line per operation — the only health signal
```

`.team-irfan/` is already gitignored; memory inherits that.

## Schema

```sql
CREATE TABLE memories (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL,                 -- one fact per row
  kind TEXT NOT NULL,                 -- domain_rule|convention|build_behavior|decision|gotcha|preference
  tags TEXT,                          -- comma list (replaces mem0's entity store)
  source TEXT NOT NULL,               -- run id + artifact, file:line, or 'init'
  commit_ref TEXT,                    -- HEAD when learned; staleness check like context maps
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  expires_at TEXT,                    -- NULL = durable
  status TEXT NOT NULL DEFAULT 'active',
  hash TEXT UNIQUE                    -- sha256(normalized text) — structural dedup
);
CREATE VIRTUAL TABLE memories_fts USING fts5(text, tags, content=memories);
-- plus ingest_log: the last 10 raw ingestion payloads, for debugging
```

## Ingestion — `memory.sh ingest`

Wired via Claude Code hooks (`hooks/hooks.json`), gated on `.tg-active`
exactly like the ledger — no marker, no effect:

- **SubagentStop** for `product` and `lead`: ingest the node's ARTIFACT
  (`plan.md`, the review report) — never raw transcripts.
- **Stop** (end of run): ingest the ship block + lessons from the newest
  handoff → decisions, gotchas.
- `--infer false`: direct script writes (init and structured facts), one
  fact per line as `kind|tags|source|text`.
- `--infer true`: ONE Haiku call (`claude -p --model haiku --output-format
  json`) with a fixed extraction prompt whose output contract is JSON ops
  only: `[{op: ADD|UPDATE|RETIRE|NOOP, kind, text, tags, expires_at?}]`.
  The script applies the ops — hash-dedup on ADD, UPDATE only rows whose
  source matches, RETIRE sets status. **Haiku proposes; the pipeline
  disposes.** Malformed JSON → logged and dropped.
- **Memory NEVER blocks a run.** Every failure path exits 0 after logging.

## Retrieval — deterministic injection at spawn

The orchestrator runs, before spawning Product or Lead:

```bash
hooks/memory.sh retrieve --agent <role> --query "<task text>" --k 12
```

and pastes the block into the spawn prompt:

```
## MEMORY (retrieved, read-only — distrust anything contradicted by code)
- [build_behavior] `npm run test` needs fixture db up first; bare vitest hangs (src: init)
```

Pipeline: simple deterministic stemming → FTS5 MATCH → BM25 rank → filter
active + unexpired → top-k (k=12 starting value), ties broken by row id.
Rows whose `commit_ref` predates changes to the file named in `source` get a
`[maybe-stale]` prefix — the same `git diff --name-only` trick as context
maps. `memory.sh compile` regenerates `product.md`/`lead.md` (top ~40
durable rows by kind priority) after every ingest; the SessionStart hook
loads them for resumed sessions.

## Init onboarding

- **Product seed (the agent reads):** domain map from README/docs,
  routes/modules, business rules found in validation code — each with
  `file:line`, kind `domain_rule|decision`, ingested with `--infer false`.
- **Lead seed (the script runs):** `memory.sh init-lead` EXECUTES the
  detected typecheck/test/lint/build commands once and records real
  behavior — durations, exit codes, warning noise — as
  `kind=build_behavior, source=init`. Learned by running, never by reading
  `package.json`.
- Re-running init: `memory.sh refresh` bumps `commit_ref` on init rows and
  retires rows whose sources vanished.

## Maintenance

`expires_at` + `commit_ref` staleness (RETIRE); `memory.sh compact` at the
end-of-run retro step — exact-hash dedup is structural (UNIQUE hash), expired
rows retire, and the optional Haiku pass (`TG_MEM_REFLECT=1`) proposes merges
of near-duplicates, applied only as ops (REFLECT). Cap: **500 active rows per
db** (starting value); compact triggers automatically when crossed.

## Logging and observability

Every `memory.sh` operation appends one line to
`.team-irfan/memory/memory.log`:

```
<ts> <op:ingest|retrieve|compile|compact> <agent> <result:ok|error> adds=<n> updates=<n> retires=<n> hits=<n> stale=<n> ms=<n> [err=<msg>]
```

This log is the ONLY way to know memory is working, since failures never
block. `/team-irfan-evaluation` reads it and reports ingest error rate,
malformed-JSON rate, retrieval hit counts, stale-flag frequency, rows added
vs retired, and a plain verdict — "memory hooks healthy" or "memory broken
since <ts>: <evidence>". A run of zero-hit retrievals or all-error ingests
is a finding, proposed as a concrete diff like any other.
