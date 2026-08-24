#!/usr/bin/env python3
"""Generate or merge the fork Sparkle appcast. Independent from Caldis/Mos."""

import os
import re
import sys

DEFAULT = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mos Fork Updates</title>
    <link>https://github.com/ZHOUSJ6/Mos</link>
    <description>Independent updates for the ZHOUSJ6/Mos fork</description>
    <language>en</language>
  </channel>
</rss>
"""


def extract_version(item: str) -> str:
    match = re.search(r'sparkle:version="([^"]+)"', item)
    return match.group(1) if match else ""


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: generate-fork-appcast.py <base_appcast_or_-> <bundle_version>")

    base_path = sys.argv[1]
    new_version = sys.argv[2]
    new_item = os.environ.get("NEW_ITEM", "").strip()
    if not new_item:
        raise SystemExit("NEW_ITEM env var is required")

    if base_path not in ("", "-") and os.path.exists(base_path):
        text = open(base_path, "r", encoding="utf-8").read()
    else:
        text = DEFAULT

    item_re = re.compile(r"<item\b.*?</item>", flags=re.S)
    matches = list(item_re.finditer(text))
    if matches:
        prefix = text[: matches[0].start()]
        suffix = text[matches[-1].end() :]
        items = [match.group(0) for match in matches]
    else:
        insert_at = text.rfind("</channel>")
        if insert_at == -1:
            text = DEFAULT
            insert_at = text.rfind("</channel>")
        prefix = text[:insert_at]
        suffix = text[insert_at:]
        items = []

    filtered = []
    seen = set()
    for item in items:
        version = extract_version(item)
        if version == new_version or version in seen:
            continue
        if version:
            seen.add(version)
        filtered.append(item)

    all_items = [new_item] + filtered
    sep = "\n\n    "
    out = prefix + sep.join(item.strip() for item in all_items if item.strip()) + suffix
    sys.stdout.write(out if out.endswith("\n") else out + "\n")


if __name__ == "__main__":
    main()
