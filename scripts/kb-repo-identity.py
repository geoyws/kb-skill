#!/usr/bin/env python3
"""Caller-side repository identity for routed claim writes and transact items."""

import hashlib
import json
import os
import subprocess
import sys


def host_id():
    if sys.platform == "darwin":
        try:
            output = subprocess.check_output(
                ["/usr/sbin/ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                stderr=subprocess.DEVNULL, text=True,
            )
            for line in output.splitlines():
                if '"IOPlatformUUID"' in line:
                    return line.split('=', 1)[1].strip().strip('"') or None
        except (OSError, subprocess.CalledProcessError, IndexError):
            return None
    elif sys.platform.startswith("linux"):
        for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
            try:
                with open(path, encoding="utf-8") as source:
                    value = source.read().strip()
                if value and value != "uninitialized":
                    return value
            except OSError:
                pass
    return None


def repo_key(path):
    identity = host_id()
    if not identity:
        return None
    try:
        common_dir = subprocess.check_output(
            ["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            stderr=subprocess.DEVNULL, text=True,
        ).strip()
        if not common_dir or not os.path.isdir(common_dir):
            return None
        common_dir = os.path.realpath(common_dir)
        if not os.path.isabs(common_dir):
            return None
    except (OSError, subprocess.CalledProcessError):
        return None
    digest = hashlib.sha256(b"git-common-dir-v1\0")
    for field in (identity, common_dir):
        encoded = field.encode("utf-8")
        digest.update(len(encoded).to_bytes(4, "big"))
        digest.update(encoded)
    return "git-common-dir-v1:" + digest.hexdigest()


def rewrite_item(item):
    if not isinstance(item, dict) or item.get("name") not in ("claim", "heartbeat", "handoff_accept"):
        return False
    args = item.get("arguments")
    if not isinstance(args, dict):
        return False
    name = item["name"]
    # Candidate inspection is a read, not a claim write.
    if name == "claim" and args.get("candidates") is True:
        return False
    no_capture = args.get("no-repo-capture") is True
    # The binary refuses this pair before any write (OV-16/A16); dropping
    # `repo` below would hide it, so the whole batch is refused here.
    if args.get("repo") is not None and no_capture:
        raise SelectorConflict("--repo and --no-repo-capture are mutually exclusive")
    path = args.pop("repo", None)
    explicit_key = args.get("repo-key")
    if explicit_key is None and (path is not None or not no_capture):
        key = repo_key(path) if path is not None else (
            repo_key(os.getcwd()) if name != "heartbeat" else None
        )
        if key:
            args["repo-key"] = key
    args["no-repo-capture"] = True
    return True


class SelectorConflict(Exception):
    pass


def element_spans(text):
    """Character spans of each top-level element of a JSON array text that
    `json.loads` already accepted. Only strings and nesting matter here."""
    spans = []
    index = text.index("[") + 1
    depth = 0
    start = None
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            if start is None:
                start = index
        elif char in "[{":
            depth += 1
            if start is None:
                start = index
        elif char in "]}":
            if depth == 0:
                if start is not None:
                    spans.append((start, len(text[:index].rstrip())))
                return spans
            depth -= 1
        elif char == "," and depth == 0:
            spans.append((start, len(text[:index].rstrip())))
            start = None
        elif not char.isspace() and start is None:
            start = index
        index += 1
    raise ValueError("unterminated items array")


def rewrite_items(original):
    """Inject identity into lease-write items only; every other item, and
    the text around them, keeps its original bytes (BA-07)."""
    items = json.loads(original)
    if not isinstance(items, list):
        return original
    text = original.decode("utf-8")
    spans = element_spans(text)
    if len(spans) != len(items):
        raise ValueError("items array could not be split into its elements")
    pieces = []
    cursor = 0
    for (start, end), item in zip(spans, items):
        if rewrite_item(item):
            pieces.append(text[cursor:start])
            pieces.append(json.dumps(item, ensure_ascii=False))
            cursor = end
    if not pieces:
        return original
    pieces.append(text[cursor:])
    return "".join(pieces).encode("utf-8")


def main():
    mode, *rest = sys.argv[1:]
    if mode == "key":
        key = repo_key(rest[0])
        if key:
            print(key)
    elif mode == "items":
        source, destination = rest
        with open(source, "rb") as stream:
            original = stream.read()
        rewritten = rewrite_items(original)
        with open(destination, "wb") as stream:
            stream.write(rewritten)
    else:
        raise ValueError("expected key PATH or items SOURCE DESTINATION")


if __name__ == "__main__":
    try:
        main()
    except SelectorConflict as exc:
        sys.exit(f"kb-board: {exc}")
    except (OSError, UnicodeError, ValueError) as exc:
        sys.exit(f"kb-board: cannot prepare repository identity: {exc}")
