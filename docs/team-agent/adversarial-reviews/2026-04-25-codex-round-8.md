[CRITICAL] Ultra consolidator schema contract is internally contradictory  
Evidence: `SKILL.md:2240`, `SKILL.md:2244-2284`, `refs/ultra-consolidation-schema.json:7`, `refs/ultra-consolidation-schema.json:40-55`  
Scenario: Prompt says top-level keys include `replicas`, but schema has `additionalProperties:false` and no `replicas`. The example omits required `status`. An Opus output can obey one part and fail another, then downstream Phase 4 consumes missing/invalid `consensus_findings` as if Ultra succeeded.  
Fix: Make prompt/example/schema identical, then validate consolidator output with `jsonschema` before writing `manifest.per_role_integration`.

[HIGH] Ultra schema validation is prose-only, no runtime rejection loop  
Evidence: `SKILL.md:2177-2185`, `SKILL.md:2240-2242`, `SKILL.md:2320`, `tests/bash-runtime-validation.sh:313-319`  
Scenario: Round-7 “findings/ideas 금지” is only prompt text. Tests only grep that text. If Opus emits `findings`, `ideas`, stale `error`, or missing `status`, there is no shown `ValidationError -> retry -> fail shape` path. User gets silently wrong aggregation.  
Fix: Add executable parser/validator after each consolidator response: parse JSON, validate `refs/ultra-consolidation-schema.json`, retry once, then write `status:"consolidator_failed"` fallback.

[HIGH] Scope TOCTOU defense is documented but not implemented  
Evidence: `SKILL.md:531-548`, `SKILL.md:553`, `SKILL.md:760-762`, `SKILL.md:1557`, `SKILL.md:1878`  
Scenario: Step 1.5 verifies `SCOPE_PATH` once, then Phase 0.3/1 still use `SCOPE_PATH`, not `_SCOPE_PATH_VERIFIED`, and there is no actual pre-spawn recheck. A scoped symlink/directory can be swapped after approval so Codex/Gemini scan outside the intended repo.  
Fix: Immediately before every backend launch, re-resolve scope, reject symlink/current realpath drift, and use only `_SCOPE_PATH_VERIFIED`.

[HIGH] Predictable `/tmp/ta-${_RUN_ID}-*` files are symlink-raceable  
Evidence: `SKILL.md:484`, `SKILL.md:1466`, `SKILL.md:1564`, `SKILL.md:1618-1619`, `SKILL.md:1876`, `SKILL.md:1969-1970`, `refs/cross-verification.md:132-140`, `refs/cross-verification.md:254`  
Scenario: `_RUN_ID` is second-granularity (`SKILL.md:27-29`). On a multi-user box, an attacker can pre-create `/tmp/ta-YYYY-MM-DD-HHMMSS-...` symlinks before Write/`: >` opens them. Logs/prompts/verdict metadata can overwrite or read attacker-controlled targets.  
Fix: Create a private `mktemp -d` run directory with `0700`, store every run artifact inside it, and use `O_NOFOLLOW`/exclusive creation for fixed names.

[HIGH] Persistent cfg.env path is predictable and non-atomic  
Evidence: `SKILL.md:56-63`, `SKILL.md:67-77`, `SKILL.md:167-169`, `SKILL.md:211`  
Scenario: `$HOME/.cache/team-agent/cfg-${_RUN_ID}.env` collides for two runs in the same second. The `[ -L ]` check happens before `: > "$_TA_CFG_FILE"`, so a symlink swap between check and open is still followed. Parent directory symlink/swap is not rechecked.  
Fix: Use `mktemp` under a private run dir, persist the generated path in the manifest/session state, open with exclusive no-follow semantics, and include PID/randomness in run IDs.

[HIGH] Gemini model probing can hang outside the timeout wrapper  
Evidence: `refs/gemini-helper.sh:83`, `refs/gemini-helper.sh:89-91`, `SKILL.md:706-714`  
Scenario: `_pick_gemini_model` runs `gemini -m "$_m" -p ping` directly. If the CLI blocks on expired auth, browser login, keychain, or network wedge, the Phase never reaches `_run_with_timeout`; the whole skill stalls before the protected backend call.  
Fix: Wrap probes and `gemini --help` detection with `_run_with_timeout` using a small probe timeout.

[HIGH] TASK_PURPOSE sanitizer silently falls back instead of fail-closed  
Evidence: `SKILL.md:488-513`, `SKILL.md:52`, `tests/bash-runtime-validation.sh:157-172`  
Scenario: The sanitizer Bash block does not source cfg.env and uses `os.environ.get("_CFG_TASK_PURPOSE_CHARS", "500")`. In Claude Code’s new-shell model this silently reverts to 500, violating the no-fallback rule. R8 misses it because it looks for `$_CFG_`, not `_CFG_` inside Python.  
Fix: Source cfg.env at block start and use `os.environ["_CFG_TASK_PURPOSE_CHARS"]`; extend tests to execute the actual sanitizer block.

[HIGH] PROJECT_CONTEXT sanitizer is not an executable contract  
Evidence: `SKILL.md:822-841`, `SKILL.md:1115-1118`, `tests/bash-runtime-validation.sh:261-268`  
Scenario: The README/CLAUDE.md supply-chain boundary is protected by pseudocode. There is no concrete function invoked on collected context, while tests only grep for `_CFG_PROJECT_CONTEXT_CHARS`. A crafted context can survive if the LLM forgets any sanitizer step before placing it inside `---BEGIN_PROJECT_CONTEXT---`.  
Fix: Move sanitizer into `refs/sanitize_context.py`, call it for both TASK_PURPOSE and PROJECT_CONTEXT, and test hostile delimiter/Unicode fixtures through that exact script.

[MEDIUM] Secret scrubber misses common production secret classes and scrubs code references  
Evidence: `refs/secret-scrubber.py:25-76`, `refs/secret-scrubber.py:96-105`  
Scenario: Live probe showed Stripe `sk_live_`, Stripe restricted `rk_live_`, Twilio `SK...`, npm `npm_...`, and Azure `AccountKey=...` were unchanged. It also rewrote `password = options.get("password")` to `password= [REDACTED_VALUE])`, corrupting benign code evidence.  
Fix: Add missing provider patterns, restrict assignment scrubbing to quoted/high-entropy literals, and preserve code structure where the RHS is a function call/reference.

[HIGH] Secret scrubbing only covers `code_snippet` and `evidence`  
Evidence: `refs/secret-scrubber.py:103-105`, `SKILL.md:2118-2125`, `SKILL.md:2129-2130`  
Scenario: Secrets in `title`, `action`, `ideas.detail`, verifier rationale, parse-failure raw output, or report sections bypass the scrubber. A malicious README can induce an agent to put a token in a title or raw malformed output and leak it to report/history.  
Fix: Scrub every string field recursively before report/history persistence, including failed raw outputs.

[MEDIUM] Codex `-c` value is shell-quoted, not TOML-escaped  
Evidence: `SKILL.md:122`, `SKILL.md:155-158`, `SKILL.md:1886-1889`, `refs/codex-verification.md:136-141`, `refs/cross-verification.md:150-154`  
Scenario: `refs/config.local.json` can set `reasoning_effort_agent` to a value containing `"`, backslash, or newline. `shlex.quote` protects the env file, but later `-c "model_reasoning_effort=\"$_CFG_CODEX_REASONING_AGENT\""` builds invalid or injected TOML config.  
Fix: Validate model/effort against strict enums and generate `-c` snippets with a TOML string encoder, not shell quoting.

[MEDIUM] `docs/team-agent/.runs` symlink checks are one-shot TOCTOU checks  
Evidence: `SKILL.md:1321-1334`, `SKILL.md:1341-1345`  
Scenario: The code checks `docs/team-agent` and `.runs` before/around `mkdir -p`, but does not revalidate after creation or before manifest writes. A local attacker or concurrent process can swap the directory after checks; `.gitignore` is also modified immediately after.  
Fix: Resolve and verify each path component after mkdir, reject symlinks with `find -L`/`stat`, and write manifests with exclusive no-follow opens.

[MEDIUM] Phase 5 cleanup is not guaranteed and can itself fail-closed  
Evidence: `SKILL.md:2578-2584`  
Scenario: The text says cleanup failure is nonfatal, but the block first sources cfg.env and exits 1 if missing. Any earlier phase abort, LLM stop, or skipped Phase 5 leaves cfg.env behind; cleanup is not an EXIT trap because each Bash block is independent.  
Fix: Make cleanup best-effort without sourcing cfg.env, and add stale-file cleanup keyed by age plus random run dirs.

[MEDIUM] Fail-closed assumes Bash exit stops the skill, but Claude may continue  
Evidence: `SKILL.md:52`, `SKILL.md:175-178`, `SKILL.md:181-185`, `SKILL.md:227-230`  
Scenario: `exit 1` stops a Bash tool call, not necessarily the instruction-following session. The LLM can observe failure and continue to later phases, which then cascade with missing/partial cfg.env or fallback behavior.  
Fix: Add explicit skill-level stop instructions after any FATAL, and make every later phase check manifest/config readiness before doing work.

[LOW] Contradiction threshold is fuzzy and non-deterministic  
Evidence: `SKILL.md:2219-2223`, `refs/ultra-consolidation-schema.json:104-107`  
Scenario: “severity 차이가 2단계 이상” is underspecified over `Critical > High > Medium > Low > Info`; Critical vs Medium may or may not be a contradiction depending on interpretation. Different Opus runs will mark different rows.  
Fix: Define a numeric rank and exact rule: `abs(rank[a]-rank[b]) >= 2`.

[MEDIUM] Test gates miss entire bypass classes  
Evidence: `tests/bash-runtime-validation.sh:157-172`, `tests/bash-runtime-validation.sh:237-241`, `tests/smoke.sh:240-241`, `tests/config-cross-invocation.sh:55-83`, `tests/bash-runtime-validation.sh:285-294`  
Scenario: R8 ignores direct `codex exec` blocks without `_run_with_timeout`/`$_CFG_`; R13 explicitly skips bare codex by requiring `_run_with_timeout`; smoke Test 8 only scans four fixed files, not all `refs/*.md`; X5 manually writes cfg.env instead of executing Preamble 0.1; R17 accepts cleanup text inside the Phase 5 section.  
Fix: Extract executable snippets or helper scripts and test those directly; enumerate all markdown refs recursively for backend calls; fail on any unwrapped `codex exec`/`gemini -p` anywhere.