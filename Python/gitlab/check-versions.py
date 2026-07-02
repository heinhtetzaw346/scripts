#!/usr/bin/env python3

import json
import csv
import os
import re
import sys
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime

GITLAB_BASE = "https://gitlab.com"
TOKEN = os.environ.get("BOT_ACCESS_TOKEN") or ""
JSON_FILE = "prod-images.json"
CSV_FILE = "version-check-results.csv"

SEMVER_RE = re.compile(r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')

NOW = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def log(msg):
    print(f"[{NOW}] {msg}", file=sys.stderr)

def is_valid_semver(tag_name):
    return bool(SEMVER_RE.match(tag_name))

def parse_semver(tag_name):
    m = SEMVER_RE.match(tag_name)
    if not m:
        return None
    return tuple(int(g) for g in m.groups())

def latest_semver(tags):
    valid = []
    for t in tags:
        name = t.get("name", "")
        if is_valid_semver(name):
            valid.append(parse_semver(name))
    if not valid:
        return ""
    best = max(valid)
    return f"{best[0]}.{best[1]}.{best[2]}"

def gitlab_api(path, method="GET"):
    url = f"{GITLAB_BASE}/api/v4{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("PRIVATE-TOKEN", TOKEN)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        log(f"HTTP {e.code} for {url}: {body}")
        return None
    except Exception as e:
        log(f"Error fetching {url}: {e}")
        return None

def main():
    if not TOKEN:
        log("BOT_ACCESS_TOKEN not set. Export it first.")
        sys.exit(1)

    if not os.path.exists(JSON_FILE):
        log(f"{JSON_FILE} not found in current directory.")
        sys.exit(1)

    try:
        with open(JSON_FILE) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        log(f"Invalid JSON in {JSON_FILE}: {e}")
        sys.exit(1)

    if not isinstance(data, list):
        log(f"{JSON_FILE} must be a JSON array.")
        sys.exit(1)

    results = []

    for i, entry in enumerate(data):
        name = entry.get("name", "") if isinstance(entry, dict) else ""
        path = entry.get("path", "") if isinstance(entry, dict) else ""
        cluster_tag = entry.get("tag", "") if isinstance(entry, dict) else ""

        name_str = str(name) if name else ""
        path_str = str(path) if path else ""
        cluster_tag_str = str(cluster_tag) if cluster_tag else ""

        if not isinstance(entry, dict):
            log(f"Entry {i}: not an object, skipping.")
            results.append([name_str, "", "", "no"])
            continue

        if not path_str:
            log(f"Entry {i} ({name_str}): missing path, skipping.")
            results.append([name_str, "", cluster_tag_str, "no"])
            continue

        encoded_path = urllib.parse.quote(path_str, safe='')
        proj_info = gitlab_api(f"/projects/{encoded_path}")

        if proj_info is None or "id" not in proj_info:
            log(f"Entry {i} ({name_str}): cannot resolve project path '{path_str}'.")
            results.append([name_str, "", cluster_tag_str, "no"])
            continue

        proj_id = proj_info["id"]
        log(f"Entry {i} ({name_str}): project id={proj_id}")

        tags = gitlab_api(f"/projects/{proj_id}/repository/tags?per_page=100&order_by=updated&sort=desc")
        if tags is None or not isinstance(tags, list):
            log(f"Entry {i} ({name_str}): cannot fetch tags.")
            results.append([name_str, "", cluster_tag_str, "no"])
            continue

        latest_tag = latest_semver(tags)

        synced = "yes" if latest_tag and latest_tag == cluster_tag_str else "no"
        log(f"Entry {i} ({name_str}): latest={latest_tag}, cluster={cluster_tag_str}, synced={synced}")

        results.append([name_str, latest_tag, cluster_tag_str, synced])

    with open(CSV_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Name", "Latest Version", "Cluster Version", "Synced"])
        writer.writerows(results)

    log(f"Results saved to {CSV_FILE}")
    print(f"\nDone. {len(results)} entries processed. Output: {CSV_FILE}")

if __name__ == "__main__":
    main()
