#!/usr/bin/env bash
# team-graph agent memory. Deterministic, per-agent, per-repository. SQLite +
# FTS5/BM25 — no vector store, no embeddings, no score fusion (decision record:
# docs/memory.md). Product and Lead only; QA and executors get none.
#
#   memory.sh ingest   --agent <product|lead> --artifact <path> [--infer true|false] [--source <s>]
#   memory.sh retrieve --agent <role> --query "<task text>" [--k 12]
#   memory.sh compile  [--agent <role>]     regenerate the always-load .md views
#   memory.sh compact  [--agent <role>]     dedup + cap enforcement (retro)
#   memory.sh refresh                       re-init: bump commit_ref, retire vanished sources
#   memory.sh init-lead                     run the repo's real commands once, record behavior
#   memory.sh hook <subagent-stop|stop|session-start>   Claude Code hook mode, inert without .tg-active
#
# MEMORY NEVER BLOCKS A RUN. Every operational failure logs one line to
# memory.log and exits 0. The log is the only way to know memory is working.
#
# Log line, one per operation:
#   <ts> <op> <agent> <result:ok|error> adds=<n> updates=<n> retires=<n> hits=<n> stale=<n> ms=<n> [err=<msg>]

set -uo pipefail

MEM_DIR="${TG_MEMORY_DIR:-.team-irfan/memory}"
SQLITE="${TG_SQLITE:-sqlite3}"
K_DEFAULT=12
COMPILE_ROWS=40
ROW_CAP=500

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_ms()  { perl -MTime::HiRes=time -e 'printf "%d", time()*1000' 2>/dev/null || echo $(($(date +%s)*1000)); }
T0=$(now_ms)

ADDS=0; UPDATES=0; RETIRES=0; HITS=0; STALE=0

log() { # log <op> <agent> <result> [err]
  mkdir -p "$MEM_DIR" 2>/dev/null || return 0
  local line
  line="$(now_iso) $1 $2 $3 adds=$ADDS updates=$UPDATES retires=$RETIRES hits=$HITS stale=$STALE ms=$(( $(now_ms) - T0 ))"
  [ -n "${4:-}" ] && line="$line err=$4"
  printf '%s\n' "$line" >> "$MEM_DIR/memory.log"
}

die_soft() { # log an error and exit 0 — memory never blocks
  log "${OP:-unknown}" "${AGENT:-'-'}" error "$(printf '%s' "$1" | tr ' ' '_' | cut -c1-120)"
  exit 0
}

norm_agent() {
  case "$1" in
    product) echo product ;;
    lead|lead-executor) echo lead ;;
    *) echo "" ;;
  esac
}

db_of() { echo "$MEM_DIR/$1.db"; }

# strip an optional --agent flag: agent_arg "--agent product" → "product"
agent_arg() {
  if [ "${1:-}" = "--agent" ]; then echo "${2:-}"; else echo "${1:-}"; fi
}

init_db() { # init_db <dbpath>
  "$SQLITE" "$1" <<'SQL' 2>/dev/null
CREATE TABLE IF NOT EXISTS memories (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL,
  kind TEXT NOT NULL,
  tags TEXT,
  source TEXT NOT NULL,
  commit_ref TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  hash TEXT UNIQUE
);
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(text, tags, content=memories, content_rowid=id);
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, text, tags) VALUES (new.id, new.text, new.tags);
END;
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, text, tags) VALUES ('delete', old.id, old.text, old.tags);
END;
CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, text, tags) VALUES ('delete', old.id, old.text, old.tags);
  INSERT INTO memories_fts(rowid, text, tags) VALUES (new.id, new.text, new.tags);
END;
CREATE TABLE IF NOT EXISTS ingest_log (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  payload TEXT
);
SQL
}

sq() { printf '%s' "$1" | sed "s/'/''/g"; }   # single-quote escape for SQL

hash_of() { # normalized text → sha256
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//' | shasum -a 256 | awk '{print $1}'
}

head_ref() { git rev-parse HEAD 2>/dev/null || echo ""; }

add_row() { # add_row <db> <kind> <tags> <source> <text> [expires_at]
  local db="$1" kind="$2" tags="$3" source="$4" text="$5" exp="${6:-}" h ts
  h=$(hash_of "$text"); ts=$(now_iso)
  local expsql="NULL"; [ -n "$exp" ] && expsql="'$(sq "$exp")'"
  local before after
  before=$("$SQLITE" "$db" "SELECT COUNT(*) FROM memories;" 2>/dev/null)
  "$SQLITE" "$db" "INSERT OR IGNORE INTO memories(text,kind,tags,source,commit_ref,created_at,updated_at,expires_at,hash)
    VALUES ('$(sq "$text")','$(sq "$kind")','$(sq "$tags")','$(sq "$source")','$(sq "$(head_ref)")','$ts','$ts',$expsql,'$h');" 2>/dev/null
  after=$("$SQLITE" "$db" "SELECT COUNT(*) FROM memories;" 2>/dev/null)
  [ "${after:-0}" -gt "${before:-0}" ] && ADDS=$((ADDS+1))
}

record_ingest_payload() { # record_ingest_payload <db> <payload> — keep last 10
  local db="$1"
  "$SQLITE" "$db" "INSERT INTO ingest_log(ts,payload) VALUES ('$(now_iso)','$(sq "$2")');
    DELETE FROM ingest_log WHERE id NOT IN (SELECT id FROM ingest_log ORDER BY id DESC LIMIT 10);" 2>/dev/null
}

# ---------------------------------------------------------------- ingest

# --infer false: the artifact is fact lines `kind|tags|source|text`, applied
# directly (init and structured facts). --infer true: ONE Haiku call proposes
# JSON ops; the pipeline disposes (hash-dedup, source-matched UPDATE, RETIRE).
do_ingest() {
  local agent="" artifact="" infer=false source=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="${2:-}"; shift 2 ;;
      --artifact) artifact="${2:-}"; shift 2 ;;
      --infer) infer="${2:-false}"; shift 2 ;;
      --source) source="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  AGENT=$(norm_agent "$agent"); [ -n "$AGENT" ] || die_soft "unknown agent $agent"
  [ -f "$artifact" ] || die_soft "artifact missing $artifact"
  mkdir -p "$MEM_DIR" || die_soft "cannot create $MEM_DIR"
  local db; db=$(db_of "$AGENT")
  init_db "$db" || die_soft "sqlite init failed"
  [ -n "$source" ] || source="$artifact"
  record_ingest_payload "$db" "$(head -c 4000 "$artifact")"

  if [ "$infer" = "true" ]; then
    ingest_infer "$db" "$artifact" "$source" || true
  else
    # direct fact lines: kind|tags|source|text — anything else is skipped
    while IFS='|' read -r kind tags src text; do
      case "$kind" in ''|'#'*) continue ;; esac
      case "$kind" in
        domain_rule|convention|build_behavior|decision|gotcha|preference) ;;
        *) continue ;;
      esac
      [ -n "$text" ] || continue
      [ -n "$src" ] || src="$source"
      add_row "$db" "$kind" "$tags" "$src" "$text"
    done < "$artifact"
  fi
  compile_agent "$AGENT" || true
  maybe_compact "$db" || true
  log ingest "$AGENT" ok
  exit 0
}

# One Haiku call with a fixed extraction prompt. Output contract: JSON ops only
# [{op:ADD|UPDATE|RETIRE|NOOP, kind, text, tags, expires_at?}]. Haiku proposes;
# the pipeline disposes: hash-dedup on ADD, UPDATE only rows whose source
# matches this run's source, RETIRE sets status. Malformed JSON → log and drop.
ingest_infer() {
  local db="$1" artifact="$2" source="$3"
  command -v claude >/dev/null 2>&1 || { log ingest "$AGENT" error claude-cli-missing; return 1; }
  local prompt out ops
  prompt="You extract durable facts from a workflow artifact for an agent memory.
Return ONLY a JSON array, no prose, no markdown fence. Each element:
{\"op\":\"ADD|UPDATE|RETIRE|NOOP\",\"kind\":\"domain_rule|convention|build_behavior|decision|gotcha|preference\",\"text\":\"one fact, one sentence\",\"tags\":\"comma,list\",\"expires_at\":\"ISO date or omit\"}
Extract only facts a FUTURE run needs: domain rules, conventions, build behavior, decisions with their why, gotchas. No task narration, no counts, no praise. Max 10 ops. Artifact follows.

$(head -c 8000 "$artifact")"
  out=$(printf '%s' "$prompt" | claude -p --model haiku --output-format json 2>/dev/null) || { log ingest "$AGENT" error haiku-call-failed; return 1; }
  # claude -p --output-format json wraps the text in {"result": "..."}
  ops=$(printf '%s' "$out" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try {
        const wrap = JSON.parse(s);
        let txt = typeof wrap === "string" ? wrap : (wrap.result ?? s);
        txt = String(txt).replace(/^```(json)?/m, "").replace(/```\s*$/m, "").trim();
        const arr = JSON.parse(txt);
        if (!Array.isArray(arr)) throw new Error("not an array");
        for (const o of arr) {
          if (!o || typeof o !== "object") continue;
          const op = String(o.op||"NOOP"), kind = String(o.kind||""), text = String(o.text||""), tags = String(o.tags||""), exp = String(o.expires_at||"");
          if (!/^(ADD|UPDATE|RETIRE|NOOP)$/.test(op)) continue;
          console.log([op,kind,tags,exp,text.replace(/[|\n]/g," ")].join("|"));
        }
      } catch (e) { process.exit(3); }
    });' 2>/dev/null) || { log ingest "$AGENT" error malformed-json-dropped; return 1; }
  while IFS='|' read -r op kind tags exp text; do
    [ -n "$op" ] || continue
    case "$kind" in
      domain_rule|convention|build_behavior|decision|gotcha|preference) ;;
      *) [ "$op" = "NOOP" ] || continue ;;
    esac
    case "$op" in
      ADD) [ -n "$text" ] && add_row "$db" "$kind" "$tags" "$source" "$text" "$exp" ;;
      UPDATE)
        [ -n "$text" ] || continue
        local n
        n=$("$SQLITE" "$db" "SELECT COUNT(*) FROM memories WHERE source='$(sq "$source")' AND kind='$(sq "$kind")' AND status='active';" 2>/dev/null)
        if [ "${n:-0}" -gt 0 ]; then
          "$SQLITE" "$db" "UPDATE memories SET text='$(sq "$text")', tags='$(sq "$tags")', updated_at='$(now_iso)', hash='$(hash_of "$text")'
            WHERE id=(SELECT id FROM memories WHERE source='$(sq "$source")' AND kind='$(sq "$kind")' AND status='active' ORDER BY updated_at DESC LIMIT 1);" 2>/dev/null \
            && UPDATES=$((UPDATES+1))
        else
          add_row "$db" "$kind" "$tags" "$source" "$text" "$exp"
        fi ;;
      RETIRE)
        [ -n "$text" ] || continue
        local r
        r=$("$SQLITE" "$db" "UPDATE memories SET status='retired', updated_at='$(now_iso)' WHERE status='active' AND text LIKE '%'||'$(sq "$text")'||'%'; SELECT changes();" 2>/dev/null)
        RETIRES=$((RETIRES + ${r:-0})) ;;
      NOOP) ;;
    esac
  done <<< "$ops"
  return 0
}

# -------------------------------------------------------------- retrieve

# Deterministic pipeline: simple stemming → FTS5 MATCH → BM25 rank → filter
# active + unexpired → top-k. Rows whose commit_ref predates changes to files
# named in source get a [maybe-stale] prefix (same git-diff trick as context
# maps). Ties broken by id so the same query always returns the same block.
stem() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' ' ' | tr -s ' ' '\n' | awk '
    length($0) < 3 { next }
    /^(the|and|for|with|that|this|from|are|was|were|has|have|had|not|but|its|it|is|of|in|on|to|a|an|or|as|at|by|be|do|does|into|when|then|than)$/ { next }
    {
      w = $0
      if (length(w) > 5 && w ~ /ing$/)      w = substr(w, 1, length(w)-3)
      else if (length(w) > 4 && w ~ /ed$/)  w = substr(w, 1, length(w)-2)
      else if (length(w) > 3 && w ~ /s$/ && w !~ /ss$/) w = substr(w, 1, length(w)-1)
      if (!seen[w]++) print w
    }'
}

do_retrieve() {
  local agent="" query="" k="$K_DEFAULT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="${2:-}"; shift 2 ;;
      --query) query="${2:-}"; shift 2 ;;
      --k) k="${2:-$K_DEFAULT}"; shift 2 ;;
      *) shift ;;
    esac
  done
  AGENT=$(norm_agent "$agent"); [ -n "$AGENT" ] || die_soft "unknown agent $agent"
  local db; db=$(db_of "$AGENT")
  echo "## MEMORY (retrieved, read-only — distrust anything contradicted by code)"
  [ -f "$db" ] || { log retrieve "$AGENT" ok; exit 0; }
  local terms match
  terms=$(stem "$query")
  [ -n "$terms" ] || { log retrieve "$AGENT" ok; exit 0; }
  # each stem as a prefix query, OR-joined: deterministic, injection-safe
  match=$(printf '%s\n' "$terms" | sed 's/.*/"&"*/' | paste -sd' ' - | sed 's/ / OR /g')
  local rows
  rows=$("$SQLITE" -separator $'\t' "$db" "
    SELECT m.kind, m.text, m.source, COALESCE(m.commit_ref,'')
    FROM memories_fts f JOIN memories m ON m.id = f.rowid
    WHERE memories_fts MATCH '$(sq "$match")'
      AND m.status = 'active'
      AND (m.expires_at IS NULL OR m.expires_at > datetime('now'))
    ORDER BY bm25(memories_fts), m.id
    LIMIT ${k};" 2>/dev/null) || { log retrieve "$AGENT" error fts-query-failed; exit 0; }
  local head_now changed=""
  head_now=$(head_ref)
  while IFS=$'\t' read -r kind text source cref; do
    [ -n "$kind" ] || continue
    HITS=$((HITS+1))
    local prefix=""
    # source names a file (path/with.ext or path:line) → stale when that file
    # changed since the row's commit_ref
    local fpath="${source%%:*}"
    if [ -n "$cref" ] && [ -n "$head_now" ] && [ "$cref" != "$head_now" ] && printf '%s' "$fpath" | grep -q '/'; then
      changed=$(git diff --name-only "$cref"..HEAD 2>/dev/null)
      if printf '%s\n' "$changed" | grep -qxF "$fpath"; then
        prefix="[maybe-stale] "; STALE=$((STALE+1))
      fi
    fi
    printf -- '- %s[%s] %s (src: %s)\n' "$prefix" "$kind" "$text" "$source"
  done <<< "$rows"
  log retrieve "$AGENT" ok
  exit 0
}

# --------------------------------------------------------------- compile

compile_agent() { # regenerate the always-load view for one agent
  local agent="$1" db out
  db=$(db_of "$agent"); out="$MEM_DIR/$agent.md"
  [ -f "$db" ] || return 0
  {
    echo "# $agent memory — compiled view (generated by memory.sh, do not edit)"
    echo
    "$SQLITE" -separator $'\t' "$db" "
      SELECT kind, text, source FROM memories
      WHERE status = 'active' AND expires_at IS NULL
      ORDER BY CASE kind
        WHEN 'domain_rule' THEN 1 WHEN 'decision' THEN 2 WHEN 'convention' THEN 3
        WHEN 'build_behavior' THEN 4 WHEN 'gotcha' THEN 5 ELSE 6 END,
        updated_at DESC, id
      LIMIT $COMPILE_ROWS;" 2>/dev/null | awk -F'\t' '{ printf "- [%s] %s (src: %s)\n", $1, $2, $3 }'
  } > "$out.tmp" && mv "$out.tmp" "$out"
}

do_compile() {
  local agent="${1:-}"
  OP=compile
  if [ -n "$agent" ]; then
    AGENT=$(norm_agent "$agent"); [ -n "$AGENT" ] || die_soft "unknown agent $agent"
    compile_agent "$AGENT" || die_soft "compile failed"
    log compile "$AGENT" ok
  else
    for a in product lead; do compile_agent "$a" || true; done
    log compile all ok
  fi
  exit 0
}

# --------------------------------------------------------------- compact

# Retro-time maintenance: exact-hash dedup is structural (UNIQUE hash), so
# compact enforces the row cap and clears expired rows. Crossing the cap
# retires the oldest lowest-priority rows first. The optional Haiku merge pass
# (REFLECT) proposes merges of near-duplicates, applied only as ops.
compact_db() { # compact_db <agent>
  local agent="$1" db; db=$(db_of "$agent")
  [ -f "$db" ] || return 0
  local expired
  expired=$("$SQLITE" "$db" "SELECT COUNT(*) FROM memories WHERE status='active' AND expires_at IS NOT NULL AND expires_at <= datetime('now');" 2>/dev/null)
  "$SQLITE" "$db" "UPDATE memories SET status='retired', updated_at='$(now_iso)'
    WHERE status='active' AND expires_at IS NOT NULL AND expires_at <= datetime('now');" 2>/dev/null
  RETIRES=$((RETIRES + ${expired:-0}))
  local active
  active=$("$SQLITE" "$db" "SELECT COUNT(*) FROM memories WHERE status='active';" 2>/dev/null)
  if [ "${active:-0}" -gt "$ROW_CAP" ]; then
    local excess=$((active - ROW_CAP))
    "$SQLITE" "$db" "UPDATE memories SET status='retired', updated_at='$(now_iso)' WHERE id IN (
      SELECT id FROM memories WHERE status='active'
      ORDER BY CASE kind
        WHEN 'preference' THEN 1 WHEN 'gotcha' THEN 2 WHEN 'build_behavior' THEN 3
        WHEN 'convention' THEN 4 WHEN 'decision' THEN 5 ELSE 6 END,
        updated_at ASC, id ASC
      LIMIT $excess);" 2>/dev/null
    RETIRES=$((RETIRES + excess))
  fi
  # optional REFLECT pass: one Haiku call proposing merges, applied as ops only
  if [ "${TG_MEM_REFLECT:-}" = "1" ] && command -v claude >/dev/null 2>&1; then
    local dump tmpf
    dump=$("$SQLITE" -separator $'\t' "$db" "SELECT id, kind, text FROM memories WHERE status='active' ORDER BY kind, text LIMIT 200;" 2>/dev/null)
    tmpf=$(mktemp "${TMPDIR:-/tmp}/tg-mem-reflect.XXXXXX")
    printf '%s\n' "$dump" > "$tmpf"
    AGENT="$agent" ingest_infer "$db" "$tmpf" "compact-reflect" || true
    rm -f "$tmpf"
  fi
  compile_agent "$agent" || true
}

maybe_compact() { # auto-trigger when the cap is crossed
  local db="$1" active
  active=$("$SQLITE" "$db" "SELECT COUNT(*) FROM memories WHERE status='active';" 2>/dev/null)
  [ "${active:-0}" -gt "$ROW_CAP" ] || return 0
  compact_db "$(basename "$db" .db)"
}

do_compact() {
  OP=compact
  local agent="${1:-}"
  if [ -n "$agent" ]; then
    AGENT=$(norm_agent "$agent"); [ -n "$AGENT" ] || die_soft "unknown agent $agent"
    compact_db "$AGENT"; log compact "$AGENT" ok
  else
    for a in product lead; do AGENT=$a; compact_db "$a"; done
    log compact all ok
  fi
  exit 0
}

# --------------------------------------------------------------- refresh

# Re-running init: bump commit_ref on init-sourced rows, retire rows whose
# source file vanished from the tree.
do_refresh() {
  OP=refresh
  local h; h=$(head_ref)
  for a in product lead; do
    local db; db=$(db_of "$a")
    [ -f "$db" ] || continue
    "$SQLITE" "$db" "UPDATE memories SET commit_ref='$(sq "$h")', updated_at='$(now_iso)' WHERE source='init' AND status='active';" 2>/dev/null
    "$SQLITE" -separator $'\t' "$db" "SELECT id, source FROM memories WHERE status='active' AND source LIKE '%/%';" 2>/dev/null |
    while IFS=$'\t' read -r id source; do
      local fpath="${source%%:*}"
      if [ -n "$fpath" ] && [ ! -e "$fpath" ]; then
        "$SQLITE" "$db" "UPDATE memories SET status='retired', updated_at='$(now_iso)' WHERE id=$id;" 2>/dev/null
      fi
    done
    compile_agent "$a" || true
  done
  log refresh all ok
  exit 0
}

# -------------------------------------------------------------- init-lead

# The Lead seed learns by RUNNING, not by reading package.json: execute each
# detected command once and record real behavior as build_behavior facts.
# ponytail: no per-command timeout — init is interactive; add one if a repo's
# test suite ever hangs the seeding.
do_init_lead() {
  OP=ingest; AGENT=lead
  mkdir -p "$MEM_DIR" || die_soft "cannot create $MEM_DIR"
  local db; db=$(db_of lead); init_db "$db" || die_soft "sqlite init failed"
  local cfg=".team-irfan/config.md"
  local names="typecheck test lint build"
  for name in $names; do
    local cmd=""
    if [ -f "$cfg" ]; then
      cmd=$(grep -E "^${name} *: " "$cfg" | head -1 | sed "s/^${name} *: *//")
    fi
    [ -n "$cmd" ] && [ "$cmd" != "none" ] || continue
    local t0 t1 rc out warns dur
    t0=$(now_ms)
    out=$(bash -c "$cmd" 2>&1); rc=$?
    t1=$(now_ms); dur=$(( (t1 - t0) / 1000 ))
    warns=$(printf '%s\n' "$out" | grep -ci 'warn' || true)
    add_row "$db" build_behavior "$name,init" init \
      "\`$cmd\` ($name) exits $rc in ~${dur}s with $warns warning line(s) on a clean tree"
  done
  compile_agent lead || true
  log ingest lead ok
  exit 0
}

# ------------------------------------------------------------------ hook

# Claude Code hook mode. Gated on .tg-active exactly like ledger.sh: no
# marker, no effect, and the tool result is never blocked (always exit 0).
do_hook() {
  local event="${1:-}"
  local input; input=$(cat 2>/dev/null)   # drain stdin even when inert
  [ -f .tg-active ] || exit 0
  local run; run=$(head -n1 .tg-active 2>/dev/null | tr -d '[:space:]')
  [ -n "$run" ] && [ -d "$run" ] || exit 0
  case "$event" in
    subagent-stop)
      local name=""
      if command -v jq >/dev/null 2>&1; then
        name=$(printf '%s' "$input" | jq -r '.agent_name // .subagent_type // empty' 2>/dev/null)
      fi
      case "$name" in
        product) [ -f "$run/plan.md" ]   && "$0" ingest --agent product --artifact "$run/plan.md"   --infer true --source "run:$(basename "$run")/plan.md" ;;
        lead|lead-executor) [ -f "$run/report.md" ] && "$0" ingest --agent lead --artifact "$run/report.md" --infer true --source "run:$(basename "$run")/report.md" ;;
      esac ;;
    stop)
      # end of run: the newest handoff carries the ship block + lessons
      local ho
      ho=$(ls -t .team-irfan/handoffs/*.md 2>/dev/null | head -1)
      [ -n "$ho" ] && "$0" ingest --agent product --artifact "$ho" --infer true --source "run:$(basename "$run")/handoff" ;;
    session-start)
      # resumed session inside a run → load the compiled views into context
      for a in product lead; do
        [ -f "$MEM_DIR/$a.md" ] && cat "$MEM_DIR/$a.md"
      done ;;
  esac
  exit 0
}

# ------------------------------------------------------------------ main

OP="${1:-}"
[ -n "$OP" ] || { echo "usage: memory.sh {ingest|retrieve|compile|compact|refresh|init-lead|hook} ..." >&2; exit 2; }
shift || true

case "$OP" in
  ingest)    do_ingest "$@" ;;
  retrieve)  do_retrieve "$@" ;;
  compile)   do_compile "$(agent_arg "$@")" ;;
  compact)   do_compact "$(agent_arg "$@")" ;;
  refresh)   do_refresh ;;
  init-lead) do_init_lead ;;
  hook)      do_hook "$@" ;;
  *)         echo "usage: memory.sh {ingest|retrieve|compile|compact|refresh|init-lead|hook} ..." >&2; exit 2 ;;
esac
