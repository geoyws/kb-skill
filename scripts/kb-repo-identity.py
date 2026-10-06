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
    path = args.pop("repo", None)
    explicit_key = args.get("repo-key")
    no_capture = args.get("no-repo-capture") is True
    if explicit_key is None and (path is not None or not no_capture):
        key = repo_key(path) if path is not None else (
            repo_key(os.getcwd()) if name != "heartbeat" else None
        )
        if key:
            args["repo-key"] = key
    args["no-repo-capture"] = True
    return True


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
        items = json.loads(original)
        changed = False
        if isinstance(items, list):
            for item in items:
                changed = rewrite_item(item) or changed
        with open(destination, "wb") as stream:
            stream.write((json.dumps(items, ensure_ascii=False) + "\n").encode("utf-8") if changed else original)
    else:
        raise ValueError("expected key PATH or items SOURCE DESTINATION")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError) as exc:
        sys.exit(f"kb-board: cannot prepare repository identity: {exc}")
