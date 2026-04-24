"""refs/secret-scrubber.py — round-7 결정론적 시크릿 스크러버

Phase 2 에이전트 결과 수집 시, 각 finding의 code_snippet·evidence에 정규식 패스를
적용해 비밀값을 `[REDACTED]`로 치환한다. 기존 프롬프트 규약("발견한 시크릿은 [REDACTED]로")
은 에이전트가 지킬지 불확실하므로, 본 스크러버가 안전망.

사용:
    import sys
    sys.path.insert(0, "<SKILL_DIR>/refs")
    from secret_scrubber import scrub

    finding["code_snippet"] = scrub(finding["code_snippet"])
    finding["evidence"]     = scrub(finding["evidence"])

패턴은 발견 우선순위가 높은 것부터 적용 — 하나의 문자열이 여러 패턴에 매치되면
가장 긴 prefix가 이긴다 (regex engine greedy).
"""

from __future__ import annotations
import re
from typing import Iterable

# 각 패턴은 (정규식, 치환 대체물) 튜플. 대체물은 문자열 또는 lambda(match -> str).
# 보수적으로 prefix 일부는 보존 — 위치 진단 가능하면서 원문 완전 복원 불가.
#
# round-8 확장 (Codex finding 대응):
#   - Stripe sk_live_/rk_live_/pk_live_, Stripe restricted rk_
#   - Twilio AC/SK (32-hex), API key SK
#   - npm_ 토큰
#   - Azure storage AccountKey=… (base64 88 chars)
#   - DigitalOcean dop_v1_, GitLab glpat-
#   - assignment 패턴은 **큰따옴표·작은따옴표·고엔트로피 literal만** — 함수 호출 레퍼런스 보존
_PATTERNS: list[tuple[re.Pattern, object]] = [
    # AWS access key
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AKIA[REDACTED_AWS_ACCESS_KEY]"),
    # AWS secret key (after `:` or `=`, 40 base64-ish chars)
    (
        re.compile(r'(?i)(aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*["\']?)([A-Za-z0-9/+=]{40})(["\']?)'),
        r"\1[REDACTED_AWS_SECRET]\3",
    ),
    # GitHub PAT (classic + fine-grained)
    (re.compile(r"\bghp_[A-Za-z0-9]{20,255}\b"), "ghp_[REDACTED_GITHUB_PAT]"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{50,255}\b"), "github_pat_[REDACTED]"),
    (re.compile(r"\b(gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,255}\b"), lambda m: f"{m.group(1)}_[REDACTED]"),
    # GitLab PAT
    (re.compile(r"\bglpat-[A-Za-z0-9_\-]{20,100}\b"), "glpat-[REDACTED_GITLAB_PAT]"),
    # Anthropic API key — specific prefix first, then generic OpenAI-style
    (re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,200}\b"), "sk-ant-[REDACTED_ANTHROPIC]"),
    # Stripe keys — specific prefixes BEFORE generic sk-
    (re.compile(r"\b(sk|rk|pk)_live_[A-Za-z0-9]{24,}\b"), lambda m: f"{m.group(1)}_live_[REDACTED_STRIPE]"),
    (re.compile(r"\b(sk|rk|pk)_test_[A-Za-z0-9]{24,}\b"), lambda m: f"{m.group(1)}_test_[REDACTED_STRIPE]"),
    # OpenAI API key (Stripe 이후에 와야 함 — sk_live_ 먼저 잡힘)
    (re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_\-]{20,200}\b"), "sk-[REDACTED_OPENAI]"),
    # Twilio Account SID + API SID (32 hex, 대소문자 섞임 가능 — 실제는 AC/SK 뒤 32 lowercase hex)
    (re.compile(r"\b(AC|SK)[a-f0-9]{32}\b"), lambda m: f"{m.group(1)}[REDACTED_TWILIO]"),
    # npm 토큰 (fine-grained + legacy)
    (re.compile(r"\bnpm_[A-Za-z0-9]{36,}\b"), "npm_[REDACTED_NPM_TOKEN]"),
    # DigitalOcean PAT
    (re.compile(r"\bdop_v1_[A-Fa-f0-9]{60,70}\b"), "dop_v1_[REDACTED_DO_TOKEN]"),
    # Azure Storage connection string AccountKey (base64 88 chars including padding)
    (
        re.compile(r"(?i)(AccountKey\s*=\s*)([A-Za-z0-9+/]{86,88}={0,2})"),
        r"\1[REDACTED_AZURE_KEY]",
    ),
    # Google API key (common pattern)
    (re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"), "AIza[REDACTED_GOOGLE_API_KEY]"),
    # Slack tokens
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b"), "xox[REDACTED_SLACK]"),
    # JWT (header.payload.signature)
    (
        re.compile(r"\beyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b"),
        "eyJ[REDACTED_JWT]",
    ),
    # Generic bearer tokens (Authorization header values)
    (
        re.compile(r"(?i)\b([Bb]earer\s+)([A-Za-z0-9_\-\.~+/]{20,})"),
        r"\1[REDACTED_BEARER]",
    ),
    # password/secret/api_key/token assignments — **quoted literal만** 매칭
    # round-8: round-7 버전은 `password = options.get("password")`의 `options.get(...)`도
    # RHS로 매칭해 코드 레퍼런스를 [REDACTED_VALUE]로 치환하는 false-positive. 이제
    # quoted literal (`"..."` 또는 `'...'`)만 매치하고 unquoted 경로는 스킵. unquoted
    # secret은 위의 특정 prefix 패턴(AKIA/sk_live_/...)이 커버.
    (
        re.compile(
            r'(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|private[_-]?key)\s*([:=])\s*'
            r'(?:"([^"\s]{6,})"|\'([^\'\s]{6,})\')'
        ),
        lambda m: f"{m.group(1)}{m.group(2)} [REDACTED_VALUE]",
    ),
    # Connection strings (postgres/mysql/mongodb/redis/amqp)
    (
        re.compile(r"\b(postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp)://([^:/@\s]+):([^@\s]+)@"),
        lambda m: f"{m.group(1)}://{m.group(2)}:[REDACTED]@",
    ),
    # PEM-style private key headers — collapse whole block to marker
    (
        re.compile(
            r"-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----.*?-----END (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----",
            re.DOTALL,
        ),
        "[REDACTED_PRIVATE_KEY_PEM]",
    ),
]


def scrub(text: str | None) -> str | None:
    """입력 문자열에서 알려진 시크릿 패턴을 [REDACTED_*]로 치환한다.

    None은 그대로 반환. 빈 문자열은 그대로 반환. 비문자열은 str(...) 캐스팅 후 처리.
    """
    if text is None:
        return None
    if not isinstance(text, str):
        text = str(text)
    if not text:
        return text
    out = text
    for pat, repl in _PATTERNS:
        out = pat.sub(repl, out)
    return out


def scrub_finding(finding: dict) -> dict:
    """단일 finding dict의 **모든 string 필드를 재귀**로 스크러빙 (round-8 확장).

    round-7까지는 code_snippet+evidence만 처리했으나, title/action/rationale/ideas.detail/
    raw passthrough 등 다른 string 필드에도 유출 위험 있음. 이제 전수 재귀.

    dict를 mutate한 뒤 돌려준다. 입력이 dict 아니면 그대로 반환.
    list/dict는 재귀 내려감, primitive(str)는 scrub, 기타는 보존.
    """
    if not isinstance(finding, dict):
        return finding
    for k, v in list(finding.items()):
        finding[k] = _scrub_recursive(v)
    return finding


def _scrub_recursive(node):
    """str은 scrub, dict/list는 재귀 내려감, 기타는 보존."""
    if isinstance(node, str):
        return scrub(node)
    if isinstance(node, dict):
        return {k: _scrub_recursive(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_scrub_recursive(x) for x in node]
    return node


def scrub_findings(findings: Iterable[dict]) -> list[dict]:
    """finding 리스트 전수 스크러빙 (모든 필드 재귀)."""
    return [scrub_finding(f) for f in findings]


if __name__ == "__main__":
    # 자가 테스트 (python3 refs/secret-scrubber.py)
    samples = [
        ("AWS key: AKIAIOSFODNN7EXAMPLE", "AKIA[REDACTED_AWS_ACCESS_KEY]"),
        ("token: ghp_1234567890abcdefghijklmnopqrstuvwxyz", "ghp_[REDACTED_GITHUB_PAT]"),
        ('const key = "sk-ant-api03-abcdefghijklmnop"', "sk-ant-[REDACTED_ANTHROPIC]"),
        ("OpenAI sk-proj-ABCDEFGHIJKL1234567890abcdefg", "sk-[REDACTED_OPENAI]"),
        ("JWT: eyJhbGciOi.eyJzdWIi.SflKxwRJSM", "eyJ[REDACTED_JWT]"),
        ("postgres://admin:supersecret@db.example.com:5432/prod", "postgres://admin:[REDACTED]@"),
        ('password = "hunter2secret"', "password= [REDACTED_VALUE]"),
        ("Authorization: Bearer eyJabc.def.ghijkl12345", "Bearer [REDACTED_BEARER]"),
        # round-8 확장: 신규 패턴
        ("Stripe live: sk_live_" + "X" * 30, "sk_live_[REDACTED_STRIPE]"),
        ("Stripe restricted: rk_live_" + "X" * 26, "rk_live_[REDACTED_STRIPE]"),
        ("Twilio: ACaaaaaaaabbbbbbbbccccccccdddddddd", "AC[REDACTED_TWILIO]"),
        ("npm token: npm_abcdefghijklmnopqrstuvwxyz0123456789", "npm_[REDACTED_NPM_TOKEN]"),
        ("Azure: AccountKey=" + "A" * 87 + "=", "[REDACTED_AZURE_KEY]"),
        ("GitLab: glpat-abc123def456xyz789qwerty", "glpat-[REDACTED_GITLAB_PAT]"),
    ]
    failed = 0
    for src, expect_marker in samples:
        got = scrub(src)
        if expect_marker in got and src != got:
            print(f"OK  | {src!r} -> {got!r}")
        else:
            print(f"FAIL | {src!r} -> {got!r} (expected marker: {expect_marker})")
            failed += 1
    # round-8 false-positive 방어: 코드 레퍼런스 보존
    preserve_cases = [
        'password = options.get("password")',   # 함수 호출 RHS — 스킵되어야
        'token = getToken()',                     # 함수 호출 RHS
        'const secret = retrieveSecret(id)',      # 함수 호출 RHS
    ]
    for src in preserve_cases:
        got = scrub(src)
        if "[REDACTED_VALUE]" in got:
            print(f"FAIL(preserve) | {src!r} -> {got!r} (code reference should be preserved)")
            failed += 1
        else:
            print(f"OK(preserve)  | {src!r} preserved")
    # round-8: recursive scrub_finding — title/action도 스크러빙됨
    sample = {
        "severity": "High",
        "title": "Leaked key sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUV in README",
        "code_snippet": "const k = \"sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUV\"",
        "evidence": "See line",
        "action": "Rotate AKIAIOSFODNN7EXAMPLE immediately",
        "nested": {"raw": "ghp_1234567890abcdefghijklmnopqrstuvwxyz"},
    }
    out = scrub_finding(sample)
    recursive_ok = all([
        "sk-ant-[REDACTED_ANTHROPIC]" in out["title"],
        "AKIA[REDACTED_AWS_ACCESS_KEY]" in out["action"],
        "ghp_[REDACTED_GITHUB_PAT]" in out["nested"]["raw"],
    ])
    if recursive_ok:
        print(f"OK(recursive) | all fields scrubbed including title/action/nested")
    else:
        print(f"FAIL(recursive) | {out!r}")
        failed += 1
    import sys as _s
    _s.exit(1 if failed else 0)
