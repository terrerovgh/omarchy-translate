#!/usr/bin/env python3
"""Translate text with Google's keyless endpoint and print JSON.

Usage: translate.py [--to es] [--alt en] [TEXT]   (TEXT may also come on stdin)
       translate.py --stdin    one JSON request line on stdin (used by the overlay):
                               {"text": "..."} or {"source": "selection"}, plus optional "to"/"alt"
       translate.py --copy     {"text": "..."} on stdin -> wl-copy
--alt: when the text is already in the --to language, translate it to this one.
Output: {"ok": true, "source": "en", "target": "es", "text": "..."}
     or {"ok": false, "error": "..."} with exit code 1.
     With --stdin the output also carries "original", the text that was translated.

The overlay never puts text in a process argument, where other local
accounts could read it from /proc: requests and copies go through stdin, and
the selection is read here with wl-paste through a pipe.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

# The Chrome-extension endpoint is tried first; translate.googleapis.com
# ("gtx") often answers 429 with a captcha page, so it is only a fallback.
DICT_ENDPOINT = "https://clients5.google.com/translate_a/t"
GTX_ENDPOINT = "https://translate.googleapis.com/translate_a/single"
MAX_INPUT = 5000
MAX_RESPONSE = 1024 * 1024
TIMEOUT = 8


EXTRA = {}  # fields added to every output line (the --stdin "original")


def fail(message):
    print(json.dumps({"ok": False, "error": message, **EXTRA}, ensure_ascii=False))
    sys.exit(1)


def read_request():
    line = sys.stdin.readline(MAX_INPUT * 8)
    try:
        req = json.loads(line or "{}")
    except ValueError:
        fail("invalid request")
    return req if isinstance(req, dict) else {}


def read_selection():
    """Primary selection, falling back to the clipboard, read through a pipe."""
    for cmd in (["wl-paste", "--primary", "--no-newline"], ["wl-paste", "--no-newline", "--type", "text"]):
        try:
            out = subprocess.run(cmd, capture_output=True, timeout=3).stdout.decode("utf-8", "replace")
        except (OSError, subprocess.TimeoutExpired):
            continue
        if out.strip():
            return out
    return ""


def copy_from_stdin():
    req = read_request()
    text = req.get("text") if isinstance(req.get("text"), str) else ""
    if not text:
        fail("empty text")
    try:
        subprocess.run(["wl-copy"], input=text.encode("utf-8"), timeout=5, check=True)
    except (OSError, subprocess.SubprocessError) as e:
        fail(f"wl-copy: {e}")
    print(json.dumps({"ok": True}))


def post(url, params, text):
    req = urllib.request.Request(
        f"{url}?{urllib.parse.urlencode(params)}",
        data=urllib.parse.urlencode({"q": text}).encode(),
        headers={
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
            "User-Agent": "Mozilla/5.0",
        },
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read(MAX_RESPONSE + 1)
    if len(raw) > MAX_RESPONSE:
        raise ValueError("response too large")
    return json.loads(raw.decode("utf-8"))


def translate_dict(text, target):
    # Response: [["translated", "src"]] (or ["translated"] when sl is fixed).
    data = post(DICT_ENDPOINT, [("client", "dict-chrome-ex"), ("sl", "auto"), ("tl", target)], text)
    first = data[0]
    if isinstance(first, list):
        return str(first[0]), str(first[1]) if len(first) > 1 else ""
    return str(first), ""


def translate_gtx(text, target):
    # Response: [[["seg", "orig", ...], ...], null, "src", ...]
    data = post(GTX_ENDPOINT, [("client", "gtx"), ("sl", "auto"), ("tl", target), ("dt", "t")], text)
    segments = data[0] or []
    translated = "".join(s[0] for s in segments if isinstance(s, list) and isinstance(s[0], str))
    source = data[2] if len(data) > 2 and isinstance(data[2], str) else ""
    return translated, source


def translate(text, target):
    try:
        translated, source = translate_dict(text, target)
        if translated:
            return translated, source[:16]
    except (urllib.error.HTTPError, ValueError, IndexError, TypeError, KeyError):
        pass
    translated, source = translate_gtx(text, target)
    return translated, source[:16]


def main(argv):
    if argv[:1] == ["--copy"]:
        copy_from_stdin()
        return
    opts = {"--to": "es", "--alt": ""}
    args = list(argv)
    from_stdin = bool(args) and args[0] == "--stdin"
    if from_stdin:
        args = args[1:]
    while len(args) >= 2 and args[0] in opts:
        opts[args[0]] = args[1]
        args = args[2:]
    if from_stdin:
        req = read_request()
        for key in ("to", "alt"):
            if isinstance(req.get(key), str):
                opts["--" + key] = req[key]
        if req.get("source") == "selection":
            args = [read_selection()]
        else:
            args = [req["text"] if isinstance(req.get("text"), str) else ""]
        EXTRA["original"] = args[0].strip()[:MAX_INPUT]
    target, alt = opts["--to"], opts["--alt"]
    for lang in (target, alt):
        if lang and (not lang.replace("-", "").isalnum() or len(lang) > 10):
            fail("invalid language code")

    text = " ".join(args) if args else sys.stdin.read()
    text = text.strip()[:MAX_INPUT]
    if not text:
        fail("empty text")

    try:
        translated, source = translate(text, target)
    except urllib.error.HTTPError as e:
        fail(f"HTTP {e.code}")
    except urllib.error.URLError as e:
        fail(f"network: {e.reason}")
    except TimeoutError:
        fail("timeout")
    except (ValueError, IndexError, TypeError, KeyError) as e:
        fail(f"bad response: {e}")

    if alt and source and source.split("-")[0] == target.split("-")[0] and alt != target:
        target = alt
        try:
            translated, source = translate(text, target)
        except (urllib.error.URLError, TimeoutError, ValueError, IndexError, TypeError, KeyError) as e:
            fail(f"alt translation failed: {e}")

    if not translated:
        fail("empty translation")
    print(json.dumps({"ok": True, "source": source, "target": target, "text": translated, **EXTRA}, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
