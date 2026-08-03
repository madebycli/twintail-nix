#!/usr/bin/env python3
"""Update flake.nix to the latest published x86_64 TwintailLauncher release."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API_URL = "https://api.github.com/repos/TwintailTeam/TwintailLauncher/releases/latest"
FLAKE_PATH = Path(__file__).resolve().parents[1] / "flake.nix"


def get_release() -> dict[str, Any]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "madebycli/twintail-nix updater",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(API_URL, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Could not read the latest upstream release: {error}") from error


def find_deb(assets: list[dict[str, Any]], suffixes: tuple[str, ...]) -> str:
    matches = []
    for asset in assets:
        name = str(asset.get("name", "")).lower()
        if any(name.endswith(suffix) for suffix in suffixes):
            url = asset.get("browser_download_url")
            if isinstance(url, str) and url:
                matches.append(url)

    if len(matches) != 1:
        available = ", ".join(str(asset.get("name", "")) for asset in assets)
        raise RuntimeError(
            f"Expected exactly one DEB matching {suffixes}, found {len(matches)}. "
            f"Available assets: {available}"
        )
    return matches[0]


def replace_input_url(text: str, input_name: str, url: str) -> str:
    pattern = re.compile(
        rf'({re.escape(input_name)}\s*=\s*\{{\s*url\s*=\s*")[^"]+(";)',
        re.DOTALL,
    )
    replacement = rf"\g<1>file+{url}\g<2>"
    updated, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"Could not update input {input_name} in {FLAKE_PATH}")
    return updated


def main() -> int:
    release = get_release()
    tag = str(release.get("tag_name", ""))
    if not tag.startswith("ttl-v"):
        raise RuntimeError(f"Unexpected upstream tag: {tag!r}")

    version = tag.removeprefix("ttl-v")
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise RuntimeError("The upstream release contains no asset list")

    x86_64_url = find_deb(assets, ("_amd64.deb", "_x86_64.deb"))

    text = FLAKE_PATH.read_text(encoding="utf-8")
    text, count = re.subn(
        r'(?m)^(\s*version\s*=\s*")[^"]+(";\s*)$',
        rf'\g<1>{version}\g<2>',
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"Could not update version in {FLAKE_PATH}")

    text = replace_input_url(text, "twintail_x86_64", x86_64_url)
    FLAKE_PATH.write_text(text, encoding="utf-8")

    print(f"TwintailLauncher {version}")
    print(f"x86_64: {x86_64_url}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
