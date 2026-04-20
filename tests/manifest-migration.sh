#!/usr/bin/env bash
# tests/manifest-migration.sh
#
# Regression: manifest schema_version v1 → v5 마이그레이션 체인 smoke.
# SKILL.md 1143-1147 하위 호환 규칙을 Python 로직으로 재현하여 각 필드 주입 확인.

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  manifest schema_version migration smoke"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

python3 <<'PYEOF' || exit 1
import json, sys

# SKILL.md 1143-1147 마이그레이션 규칙을 함수로 재현
def v1_to_v2(m):
    m.setdefault("schema_version", 2)
    m.setdefault("diff_base", None)
    m.setdefault("diff_target_files", None)
    m["schema_version"] = 2
    return m

def v2_to_v3(m):
    m.setdefault("gemini_mode", None)
    m.setdefault("cross_mode", False)
    m.setdefault("codemap_backend", None)
    m.setdefault("codemap_path", None)
    m.setdefault("verification", None)
    m["schema_version"] = 3
    return m

def v3_to_v4(m):
    m.setdefault("ultra_mode", False)
    m.setdefault("ultra_codex_avail", True)
    m.setdefault("ultra_gemini_avail", True)
    m.setdefault("agent_groups", None)
    m.setdefault("per_role_integration", None)
    m["schema_version"] = 4
    return m

def v4_to_v5(m):
    m.setdefault("meta_analysis", False)
    m["schema_version"] = 5
    return m

CHAIN = [v1_to_v2, v2_to_v3, v3_to_v4, v4_to_v5]
CURRENT = 5

def migrate(m):
    v = m.get("schema_version", 1)
    # CHAIN[i] takes version (i+1) → (i+2), i.e. v1→v2 is CHAIN[0]
    for i, fn in enumerate(CHAIN, start=1):
        if v < i + 1:  # if current version < target
            m = fn(m)
            v = m["schema_version"]
    return m

tests_passed = 0
tests_failed = 0

def test(name, assertion, detail=""):
    global tests_passed, tests_failed
    if assertion:
        print(f"  [PASS] {name}")
        tests_passed += 1
    else:
        print(f"  [FAIL] {name}: {detail}")
        tests_failed += 1

# M1. v1 (schema_version 없음) → v5
m = {"run_id": "test", "agents": [], "task_purpose": "t", "project_context": "c"}
m = migrate(m)
test("M1 — v1 (no version) → v5", m["schema_version"] == 5, f"got {m.get('schema_version')}")
test("M1a — v1→v5: diff_base 주입", "diff_base" in m)
test("M1b — v1→v5: meta_analysis 주입", m.get("meta_analysis") == False)
test("M1c — v1→v5: ultra_mode 주입", m.get("ultra_mode") == False)
test("M1d — v1→v5: codemap_path 주입", m.get("codemap_path") is None)

# M2. v2 → v5
m = {"schema_version": 2, "diff_base": None, "diff_target_files": None}
m = migrate(m)
test("M2 — v2 → v5", m["schema_version"] == 5)
test("M2a — v2→v5: gemini_mode 주입", "gemini_mode" in m)
test("M2b — v2→v5: cross_mode 주입", m.get("cross_mode") == False)

# M3. v3 → v5
m = {"schema_version": 3, "gemini_mode": None, "cross_mode": False,
     "codemap_backend": None, "codemap_path": None, "verification": None}
m = migrate(m)
test("M3 — v3 → v5", m["schema_version"] == 5)
test("M3a — v3→v5: ultra_mode 주입", m.get("ultra_mode") == False)
test("M3b — v3→v5: agent_groups 주입", m.get("agent_groups") is None)

# M4. v4 → v5
m = {"schema_version": 4, "ultra_mode": True, "ultra_codex_avail": True,
     "ultra_gemini_avail": False, "agent_groups": {}, "per_role_integration": None}
m = migrate(m)
test("M4 — v4 → v5", m["schema_version"] == 5)
test("M4a — v4→v5: meta_analysis 주입 (기본 False)", m.get("meta_analysis") == False)
test("M4b — v4→v5: 기존 ultra_mode 보존", m.get("ultra_mode") == True)

# M5. v5 (이미 최신) → 변경 없음
m = {"schema_version": 5, "meta_analysis": True}
m = migrate(m)
test("M5 — v5 no-op", m["schema_version"] == 5 and m.get("meta_analysis") == True)

# M6. 기존 사용자 데이터 보존 (모든 단계에서)
m = {"run_id": "custom-run", "task_purpose": "중요한 목적", "agents": ["agent1"]}
m = migrate(m)
test("M6 — 기존 필드 보존 (run_id)", m.get("run_id") == "custom-run")
test("M6a — 기존 필드 보존 (task_purpose)", m.get("task_purpose") == "중요한 목적")
test("M6b — 기존 필드 보존 (agents)", m.get("agents") == ["agent1"])

# M7. CURRENT 상수 일치
test("M7 — CURRENT_SCHEMA_VERSION == 5", CURRENT == 5)

print()
print(f"tests_passed={tests_passed} tests_failed={tests_failed}")
if tests_failed > 0:
    sys.exit(1)
PYEOF
RC=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RC" -eq 0 ]; then
    echo -e "  ${GREEN}✅ manifest migration smoke 통과${NC}"
else
    echo -e "  ${RED}❌ 일부 실패${NC}"
    exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
