#!/usr/bin/env python3
# tests/_sanitizer_shim.py — Step 1-2 TASK_PURPOSE sanitizer를 재현한 단일 파일 shim.
# e2e-preamble.sh + sanitizer-regression.sh에서 공용. SKILL.md Step 1-2와 100% 동일 로직.
import re, unicodedata, sys

def sanitize_user(raw: str, max_len: int = 500) -> str:
    raw = unicodedata.normalize('NFKD', raw)
    raw = re.sub(r'[‐-―­−]', '-', raw)
    raw = re.sub(r'[\x00-\x09\x0b-\x1f\x7f]', '', raw)
    raw = raw.replace('\n', ' ').replace('\r', ' ')
    for seq in ['---BEGIN_USER_INPUT---', '---END_USER_INPUT---',
                '---BEGIN_PROJECT_CONTEXT---', '---END_PROJECT_CONTEXT---',
                '<task_input>', '</task_input>']:
        raw = re.sub(re.escape(seq), '', raw, flags=re.IGNORECASE)
    raw = unicodedata.normalize('NFC', raw)
    raw = re.sub(r'[^a-zA-Z0-9\s\-_.,:()!\'\"?가-힣]', '', raw)
    return raw[:max_len]

if __name__ == '__main__':
    # stdin → sanitize → stdout. argv로 길이 지정 가능 (default 500).
    max_len = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    raw = sys.stdin.read()
    sys.stdout.write(sanitize_user(raw, max_len))
