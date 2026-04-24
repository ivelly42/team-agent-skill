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
    # Anthropic API key — specific prefix first, then generic OpenAI-style
    (re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,200}\b"), "sk-ant-[REDACTED_ANTHROPIC]"),
    # OpenAI API key
    (re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_\-]{20,200}\b"), "sk-[REDACTED_OPENAI]"),
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
    # password/secret/api_key/token assignments (key=value / key: value)
    (
        re.compile(
            r'(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|private[_-]?key)\s*([:=])\s*'
            r'(?:"([^"\s]{6,})"|\'([^\'\s]{6,})\'|([^\s,;}\)]{6,}))'
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
    """단일 finding dict에서 code_snippet + evidence 필드를 제자리 스크러빙.

    dict를 mutate한 뒤 돌려준다. 입력이 dict 아니면 그대로 반환.
    """
    if not isinstance(finding, dict):
        return finding
    for key in ("code_snippet", "evidence"):
        if key in finding and finding[key] is not None:
            finding[key] = scrub(finding[key])
    return finding


def scrub_findings(findings: Iterable[dict]) -> list[dict]:
    """finding 리스트 전수 스크러빙."""
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
    ]
    failed = 0
    for src, expect_marker in samples:
        got = scrub(src)
        if expect_marker in got and src != got:
            print(f"OK  | {src!r} -> {got!r}")
        else:
            print(f"FAIL | {src!r} -> {got!r} (expected marker: {expect_marker})")
            failed += 1
    import sys as _s
    _s.exit(1 if failed else 0)
