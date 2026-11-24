#!/usr/bin/env python3
"""Download the latest unsigned IPA from GitHub Releases.

Usage:
    python3 scripts/download_ipa.py
    python3 scripts/download_ipa.py --out /path/to/ADBHelper.ipa
    python3 scripts/download_ipa.py --repo someone/fork --tag v1.1.4-b25

Credentials: uses GITHUB_TOKEN env var if set, otherwise the first
github.com entry in ~/.git-credentials. Never writes the token to disk.
Public repositories work without any credentials.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

REPO = os.environ.get("ADB_REPO", "YK191/ios-adb-helper")
ASSET = "ADBHelper.ipa"


def github_token():
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    cred = os.path.expanduser("~/.git-credentials")
    if os.path.exists(cred):
        with open(cred, encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                match = re.match(r"[^:]+://([^:]+):([^@]+)@github\.com", line)
                if match:
                    return match.group(2)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=REPO, help="owner/repo (default: %s)" % REPO)
    parser.add_argument("--tag", default=None, help="Release tag (default: latest release)")
    parser.add_argument("--out", default=ASSET, help="Output .ipa path")
    args = parser.parse_args()

    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "adb-helper-ios",
    }
    token = github_token()
    if token:
        # Public repositories work anonymously; a token simply avoids rate limits.
        headers["Authorization"] = "Bearer " + token

    if args.tag:
        url = "https://api.github.com/repos/%s/releases/tags/%s" % (args.repo, args.tag)
    else:
        url = "https://api.github.com/repos/%s/releases/latest" % args.repo
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        release = json.load(response)
    print("release: %s (%s)" % (release["tag_name"], release["name"]))

    asset = next((a for a in release["assets"] if a["name"] == ASSET), None)
    if asset is None:
        print("ERROR: %s not found in release %s" % (ASSET, args.tag))
        sys.exit(1)

    binary_headers = dict(headers)
    binary_headers["Accept"] = "application/octet-stream"
    with urllib.request.urlopen(
        urllib.request.Request(asset["url"], headers=binary_headers), timeout=180
    ) as response:
        data = response.read()

    destination = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(destination) or ".", exist_ok=True)
    with open(destination, "wb") as handle:
        handle.write(data)

    print("saved: %s" % destination)
    print("bytes: %d" % len(data))
    print("release updated: %s" % release["updated_at"])


if __name__ == "__main__":
    main()
