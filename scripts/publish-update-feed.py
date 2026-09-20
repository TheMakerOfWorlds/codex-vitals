#!/usr/bin/env python3
"""Publish a release feed without regressing its version or overwriting main."""
from pathlib import Path
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

NAMESPACE = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


def version(data: bytes) -> tuple[int, ...]:
    root = ET.fromstring(data)
    versions = [tuple(int(part) for part in item.text.split("."))
                for item in root.findall("./channel/item/sparkle:version", NAMESPACE)]
    return max(versions, default=())


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], check=check)


def main() -> None:
    feed = Path(sys.argv[1]).read_bytes()
    incoming = version(feed)
    if not incoming:
        raise SystemExit("Refusing to publish an empty release feed")
    git("config", "user.name", "github-actions[bot]")
    git("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    for attempt in range(3):
        git("fetch", "origin", "main")
        git("checkout", "-B", "update-feed", "origin/main")
        target = Path("updates/appcast.xml")
        if target.exists() and version(target.read_bytes()) >= incoming:
            print("The published feed already has this release or a newer one.")
            return
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(feed)
        git("add", str(target))
        git("commit", "-m", f"Publish update feed for {'.'.join(map(str, incoming))}")
        if git("push", "origin", "HEAD:main", check=False).returncode == 0:
            return
        if attempt < 2:
            time.sleep(2 ** attempt)
    raise SystemExit("Could not publish the feed after refreshing main three times")


if __name__ == "__main__":
    main()
