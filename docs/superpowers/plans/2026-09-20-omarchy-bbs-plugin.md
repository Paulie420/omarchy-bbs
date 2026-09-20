# paulie420.bbs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working v1 of the `paulie420.bbs` Omarchy plugin — a bar-widget + dropdown panel that lets users search a curated/full directory of telnet/SSH BBSes and connect via SyncTERM.

**Architecture:** A bash fetch script (`bbs-fetch`) pulls Telnet BBS Guide's monthly CSV, normalizes it with a small Python script, and caches it under `~/.cache/omarchy-bbs/` behind a lock (same pattern as `akshar.radio-atlas`'s `radio-fetch`). A single `BarWidget.qml`, rooted as a `Panel` (same shape as `paulie420.vpn`'s `BarWidget.qml`), owns a bar icon and an embedded `KeyboardPanel` dropdown with two tabs: a searchable/filterable Directory and a static How-to-Connect guide. Pure data logic (filtering, sorting, tier lookup) lives in `BbsModel.js`, unit-tested with Node's `vm` module the same way `RadioModel.js` is tested. No backend, no accounts, no globe (v1).

**Tech Stack:** QML (Quickshell, `qs.Commons`/`qs.Ui`), bash, Python 3, `jq`, `curl`, `unzip`, `wl-copy`, `syncterm` (AUR).

**Spec:** `docs/superpowers/specs/2026-09-20-omarchy-bbs-design.md`

## Global Constraints

- Plugin id is `paulie420.bbs`; license MIT; homepage/repository both `https://github.com/Paulie420/omarchy-bbs`.
- No mention of any AI coding assistant anywhere in code, docs, or commit messages (this repo is public and in scope for that rule).
- No voting/ranking backend of any kind. Tiers come only from the static `assets/tiers.json`, hand-edited by the author.
- No BBS gets special-cased in code or UI, including `20forbeers.com` — it is tiered like any other entry via `assets/tiers.json`.
- v1 ships an empty/placeholder `assets/tiers.json` (`{"best": [], "great": [], "good": []}`) — the real seed list is a follow-up content task, not part of this build.
- Every QML file must pass `qmllint -I /usr/share/omarchy/shell` before it is committed.
- Every `Panel`-rooted bar widget must set explicit `implicitWidth`/`implicitHeight` (from its bar-icon button) or the bar slot renders 0×0.
- `bbslist.csv`'s `location` field contains quoted commas — it must be parsed with a real CSV parser (Python's `csv` module), never split on `,` directly.

---

## File Structure

```
paulie420.bbs/
  manifest.json
  LICENSE
  README.md
  .gitignore
  BarWidget.qml         # bar icon + embedded dropdown panel (Directory / How-to-Connect tabs)
  BbsService.qml        # owns the cache file (FileView) + fetch trigger (Process), exposes `entries`
  BbsModel.js           # pure JS: filtering, sorting, tier-join, distinct-value helpers
  bbs-fetch              # bash: resolve monthly zip URL, download, extract, cache, background refresh
  bbs-normalize.py       # python: bbslist.csv -> normalized JSON
  bbs-connect            # bash: launch syncterm via omarchy-launch-terminal, or report "not installed"
  assets/
    tiers.json           # author-curated {"best": [...], "great": [...], "good": [...]}
  tests/
    run                  # orchestrator, mirrors akshar.radio-atlas/tests/run
    model.test.mjs        # BbsModel.js unit tests (vm-sandboxed, no exports needed)
    normalize.test.py     # bbs-normalize.py unit tests
    fetch.test.sh          # bbs-fetch integration tests (fixture curl stub, cache/lock/fallback)
    fixtures/
      curl                 # stub curl understanding just bbs-fetch's URL shapes
```

---

## Task 1: Repo scaffold — manifest, license, ignores, tier placeholder

**Files:**
- Create: `manifest.json`
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `assets/tiers.json`

**Interfaces:**
- Produces: the manifest's `id` (`paulie420.bbs`), which every later QML file's `moduleName` must match exactly.

- [ ] **Step 1: Write the manifest**

```json
{
  "schemaVersion": 1,
  "id": "paulie420.bbs",
  "name": "BBS Guide",
  "version": "0.1.0",
  "author": "paulie420",
  "license": "MIT",
  "description": "Browse, search and connect to classic telnet/SSH Bulletin Board Systems from the Omarchy bar, with a curated Best/Great/Good directory and a built-in guide to BBS terminal clients.",
  "homepage": "https://github.com/Paulie420/omarchy-bbs",
  "repository": "https://github.com/Paulie420/omarchy-bbs",
  "keywords": ["bbs", "telnet", "ssh", "retro", "terminal"],
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "BBS Guide",
    "description": "Browse and connect to telnet/SSH BBSes",
    "category": "Utilities",
    "allowMultiple": false,
    "defaultSection": "right"
  }
}
```

- [ ] **Step 2: Write the license**

```
MIT License

Copyright (c) 2026 paulie420

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write `.gitignore`**

```
__pycache__/
*.pyc
/tests/tmp/
```

- [ ] **Step 4: Write the placeholder tier file**

```json
{
  "best": [],
  "great": [],
  "good": []
}
```

- [ ] **Step 5: Commit**

```bash
git add manifest.json LICENSE .gitignore assets/tiers.json
git commit -m "Scaffold plugin manifest, license, and placeholder tier data"
```

---

## Task 2: `bbs-normalize.py` — CSV to normalized JSON

**Files:**
- Create: `bbs-normalize.py`
- Test: `tests/normalize.test.py`

**Interfaces:**
- Consumes: `bbslist.csv` text on stdin (columns: `bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software`).
- Produces: a JSON array on stdout, each record shaped
  `{name, sysop, newLoginHint, host, telnetPort, sshPort, webUrl, location, country, software}`
  where `telnetPort` is always an int (defaults to `23` when the source leaves it blank — confirmed against the source's own `dialdirectory.xml`, which writes `port="23"` for exactly those rows), `sshPort` is an int or `null`, and `country` is the last comma-separated segment of `location`. This exact shape is what `bbs-fetch` writes to the cache file and what `BbsModel.js`'s tests and `BbsService.qml` consume.

- [ ] **Step 1: Write the failing test**

```python
# tests/normalize.test.py
import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "bbs-normalize.py"

CSV = (
    "bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software\n"
    '0xDECAFBAD BBS,,NEW,bbs.decafbad.com,6523,,,"Seattle, WA, USA",,"Synchronet"\n'
    '20 For Beers BBS,paul lee,Desired Handle,20forbeers.com,1337,1338,http://20forbeers.com:1339,"Portland, OR, USA",,"Mystic"\n'
    '4 Wheel Ham BBS,w7jpj,NEW,bbs.4wheelham.com,,2222,http://4wheelham.com,"Littleton, CO, USA",,"Synchronet"\n'
    ",,,,,,,,,\n"  # blank row: must be dropped
    '0xDECAFBAD BBS,,NEW,bbs.decafbad.com,9999,,,"Seattle, WA, USA",,"Synchronet"\n'  # duplicate name: must be dropped
)


def run(csv_text):
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=csv_text, capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def test_normalizes_and_defaults_telnet_port():
    rows = run(CSV)
    assert len(rows) == 3, rows

    decafbad = rows[0]
    assert decafbad["name"] == "0xDECAFBAD BBS"
    assert decafbad["host"] == "bbs.decafbad.com"
    assert decafbad["telnetPort"] == 6523
    assert decafbad["sshPort"] is None
    assert decafbad["location"] == "Seattle, WA, USA"
    assert decafbad["country"] == "USA"
    assert decafbad["software"] == "Synchronet"

    beers = rows[1]
    assert beers["sysop"] == "paul lee"
    assert beers["newLoginHint"] == "Desired Handle"
    assert beers["telnetPort"] == 1337
    assert beers["sshPort"] == 1338
    assert beers["webUrl"] == "http://20forbeers.com:1339"

    ham = rows[2]
    # bbsPort was blank -> defaults to the standard telnet port 23.
    assert ham["telnetPort"] == 23
    assert ham["sshPort"] == 2222


def test_strips_control_characters_and_collapses_whitespace():
    csv_text = (
        "bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software\n"
        '"Messy   Name\\nWith\\tTabs",,,"host.example",23,,,"City,  ST, USA",,"Custom"\n'
    )
    rows = run(csv_text)
    assert rows[0]["name"] == "Messy Name With Tabs"
    assert rows[0]["country"] == "USA"


def test_rejects_rows_with_no_host():
    csv_text = (
        "bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software\n"
        "No Host BBS,,,,23,,,,\n"
    )
    assert run(csv_text) == []


if __name__ == "__main__":
    test_normalizes_and_defaults_telnet_port()
    test_strips_control_characters_and_collapses_whitespace()
    test_rejects_rows_with_no_host()
    print("normalize.test.py passed")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/normalize.test.py`
Expected: FAIL (`bbs-normalize.py` does not exist yet — `FileNotFoundError`).

- [ ] **Step 3: Write the implementation**

```python
#!/usr/bin/env python3
"""Normalize a Telnet BBS Guide bbslist.csv into the plugin's JSON shape."""
import csv
import json
import sys

FIELD_LIMIT = 200
MAX_RECORDS = 5000


def clean(value, limit=FIELD_LIMIT):
    if value is None:
        return ""
    return " ".join(str(value).split())[:limit]


def parse_port(value):
    value = clean(value, 6)
    if not value.isdigit():
        return None
    port = int(value)
    return port if 1 <= port <= 65535 else None


def parse_country(location):
    parts = [p.strip() for p in location.split(",") if p.strip()]
    return parts[-1] if parts else ""


def normalize_rows(rows):
    seen = set()
    output = []
    for row in rows:
        name = clean(row.get("bbsName"))
        if not name or name in seen:
            continue
        host = clean(row.get("TelnetAddress"))
        if not host:
            continue
        seen.add(name)
        # The source leaves bbsPort blank for boards on the standard telnet
        # port. Its own EtherTerm dialing directory (dialdirectory.xml)
        # confirms this convention by writing port="23" for exactly those
        # rows, so we default to 23 rather than treating it as "no telnet".
        telnet_port = parse_port(row.get("bbsPort")) or 23
        ssh_port = parse_port(row.get("sshPort"))
        location = clean(row.get("location"))
        output.append({
            "name": name,
            "sysop": clean(row.get("bbsSysop")),
            "newLoginHint": clean(row.get("newLogin")),
            "host": host,
            "telnetPort": telnet_port,
            "sshPort": ssh_port,
            "webUrl": clean(row.get("WebAddress"), 300),
            "location": location,
            "country": parse_country(location),
            "software": clean(row.get("software"), 60),
        })
        if len(output) >= MAX_RECORDS:
            break
    return output


def main():
    reader = csv.DictReader(sys.stdin)
    reader.fieldnames = [name.strip() for name in (reader.fieldnames or [])]
    rows = normalize_rows(reader)
    json.dump(rows, sys.stdout)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x bbs-normalize.py && python3 tests/normalize.test.py`
Expected: `normalize.test.py passed`

- [ ] **Step 5: Commit**

```bash
git add bbs-normalize.py tests/normalize.test.py
git commit -m "Add bbslist.csv normalizer"
```

---

## Task 3: `bbs-fetch` — resolve, download, cache, refresh

**Files:**
- Create: `bbs-fetch`
- Test: `tests/fetch.test.sh`
- Test fixture: `tests/fixtures/curl`

**Interfaces:**
- Consumes: `bbs-normalize.py` (Task 2), `manifest.json`'s `.version` (via `jq`).
- Produces: `bbs-fetch list` and `bbs-fetch refresh`, both printing the cached JSON array to stdout and maintaining `~/.cache/omarchy-bbs/list.json`. This is what `BbsService.qml` (Task 5) shells out to.

- [ ] **Step 1: Write the fixture curl stub**

```bash
# tests/fixtures/curl
#!/usr/bin/env bash
set -euo pipefail

url=""
output=""
prev=""
for arg in "$@"; do
  if [[ $prev == "--output" ]]; then output="$arg"; fi
  case "$arg" in http://*|https://*) url="$arg" ;; esac
  prev="$arg"
done

emit() { if [[ -n $output ]]; then cat > "$output"; else cat; fi; }

case "$url" in
  */lists/download-list/)
    printf '<a href="/bbslist/ibbs-fallback.zip">Download</a>\n' | emit
    ;;
  */bbslist/ibbs-fallback.zip)
    cat "$BBS_FETCH_TEST_FIXTURE_ZIP" | emit
    ;;
  */bbslist/ibbs*.zip)
    if [[ ${BBS_FETCH_TEST_MONTHLY_404:-0} == 1 ]]; then
      echo "curl: (22) The requested URL returned error: 404" >&2
      exit 22
    fi
    cat "$BBS_FETCH_TEST_FIXTURE_ZIP" | emit
    ;;
  *)
    echo "curl stub: unhandled URL $url" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Write the integration test (will fail — `bbs-fetch` doesn't exist)**

```bash
#!/usr/bin/env bash
# tests/fetch.test.sh
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

export XDG_RUNTIME_DIR="$test_root/runtime"
export XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_RUNTIME_DIR"
chmod +x "$project_dir/tests/fixtures/curl"

python3 - "$test_root/fixture.zip" <<'PY'
import csv, io, sys, zipfile

rows = [
    {"bbsName": "0xDECAFBAD BBS", "bbsSysop": "", "newLogin": "NEW",
     "TelnetAddress": "bbs.decafbad.com", "bbsPort": "6523", "sshPort": "",
     "WebAddress": "", "location": "Seattle, WA, USA", "Modem": "",
     "software": "Synchronet"},
    {"bbsName": "20 For Beers BBS", "bbsSysop": "paul lee",
     "newLogin": "Desired Handle", "TelnetAddress": "20forbeers.com",
     "bbsPort": "1337", "sshPort": "1338",
     "WebAddress": "http://20forbeers.com:1339",
     "location": "Portland, OR, USA", "Modem": "", "software": "Mystic"},
    {"bbsName": "4 Wheel Ham BBS", "bbsSysop": "w7jpj", "newLogin": "NEW",
     "TelnetAddress": "bbs.4wheelham.com", "bbsPort": "", "sshPort": "2222",
     "WebAddress": "http://4wheelham.com", "location": "Littleton, CO, USA",
     "Modem": "", "software": "Synchronet"},
]
fields = ["bbsName", "bbsSysop", "newLogin", "TelnetAddress", "bbsPort",
          "sshPort", "WebAddress", "location", "Modem", "software"]
buf = io.StringIO()
writer = csv.DictWriter(buf, fieldnames=fields)
writer.writeheader()
writer.writerows(rows)
with zipfile.ZipFile(sys.argv[1], "w") as zf:
    zf.writestr("bbslist.csv", buf.getvalue())
PY

env_base=(PATH="$project_dir/tests/fixtures:$PATH"
          BBS_FETCH_TEST_FIXTURE_ZIP="$test_root/fixture.zip")

# 1. Normal path: current-month URL succeeds, cache gets populated.
env "${env_base[@]}" "$project_dir/bbs-fetch" list > "$test_root/list.json"
jq -e 'length == 3 and .[0].name == "0xDECAFBAD BBS"' "$test_root/list.json" >/dev/null
jq -e '.[1].telnetPort == 1337 and .[1].sshPort == 1338' "$test_root/list.json" >/dev/null
jq -e '.[2].telnetPort == 23 and .[2].sshPort == 2222' "$test_root/list.json" >/dev/null
[[ -s "$XDG_CACHE_HOME/omarchy-bbs/list.json" ]]

# 2. Monthly URL 404s -> falls back to the scraped download-page link.
rm -rf "$XDG_CACHE_HOME"
env "${env_base[@]}" BBS_FETCH_TEST_MONTHLY_404=1 \
  "$project_dir/bbs-fetch" list > "$test_root/fallback.json"
jq -e 'length == 3' "$test_root/fallback.json" >/dev/null

# 3. Fresh cache is served without hitting the network again.
env "${env_base[@]}" BBS_FETCH_TEST_MONTHLY_404=1 \
  BBS_FETCH_TEST_FIXTURE_ZIP=/nonexistent \
  "$project_dir/bbs-fetch" list > "$test_root/cached.json"
jq -e 'length == 3' "$test_root/cached.json" >/dev/null

# 4. A stale cache is served immediately, and a background refresh replaces it.
stale='[{"name":"Old Cached BBS","host":"old.example","telnetPort":23,"sshPort":null,"location":"","country":"","software":"","sysop":"","newLoginHint":"","webUrl":""}]'
printf '%s\n' "$stale" > "$XDG_CACHE_HOME/omarchy-bbs/list.json"
touch -d '40 days ago' "$XDG_CACHE_HOME/omarchy-bbs/list.json"
env "${env_base[@]}" "$project_dir/bbs-fetch" list > "$test_root/stale.json"
jq -e 'length == 1 and .[0].name == "Old Cached BBS"' "$test_root/stale.json" >/dev/null
for _ in $(seq 1 100); do
  jq -e 'length == 3' "$XDG_CACHE_HOME/omarchy-bbs/list.json" >/dev/null 2>&1 && break
  sleep 0.05
done
jq -e 'length == 3' "$XDG_CACHE_HOME/omarchy-bbs/list.json" >/dev/null

echo "fetch.test.sh passed"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/fetch.test.sh`
Expected: FAIL (`bbs-fetch: No such file or directory`).

- [ ] **Step 4: Write the implementation**

```bash
#!/usr/bin/env bash
# bbs-fetch
set -euo pipefail
umask 077

: "${XDG_RUNTIME_DIR:?bbs-fetch requires XDG_RUNTIME_DIR}"
runtime_dir="$XDG_RUNTIME_DIR/omarchy-bbs"
cache_root=${XDG_CACHE_HOME:-$HOME/.cache}
cache_dir="$cache_root/omarchy-bbs"
install -d -m 700 "$runtime_dir" "$cache_dir"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
list_cache_file="$cache_dir/list.json"
list_cache_minutes=43200   # 30 days: the source list is published monthly
max_response_bytes=8388608 # 8 MiB, well above the ~2.3 MiB zip
version=$(jq -r '.version' "$script_dir/manifest.json")
user_agent="Omarchy BBS Guide/$version (https://github.com/Paulie420/omarchy-bbs)"
base_url="https://www.telnetbbsguide.com"
work_dir=""

cleanup() { [[ -z $work_dir ]] || rm -rf "$work_dir"; }
trap cleanup EXIT

current_list_url() {
  printf '%s/bbslist/ibbs%s%s.zip\n' "$base_url" "$(date +%m)" "$(date +%y)"
}

discover_list_url() {
  curl --fail --silent --show-error --connect-timeout 4 --max-time 12 \
    --proto '=https' --user-agent "$user_agent" \
    "$base_url/lists/download-list/" \
    | grep -oE 'href="[^"]+\.zip"' | head -n1 | sed -E 's/^href="//; s/"$//'
}

download_zip() {
  local url=$1 out=$2
  case "$url" in http://*|https://*) ;; *) url="$base_url$url" ;; esac
  setpriv --pdeathsig TERM curl --fail --silent --show-error \
    --connect-timeout 6 --max-time 30 --retry 1 --retry-delay 0 \
    --max-filesize "$max_response_bytes" --proto '=https' \
    --user-agent "$user_agent" "$url" --output "$out"
}

fetch_and_normalize() {
  work_dir=$(mktemp -d "$runtime_dir/fetch.XXXXXX")
  local zip="$work_dir/list.zip"
  if ! download_zip "$(current_list_url)" "$zip"; then
    local fallback
    fallback=$(discover_list_url) || return 1
    [[ -n $fallback ]] || return 1
    download_zip "$fallback" "$zip" || return 1
  fi
  (( $(stat -c '%s' -- "$zip") <= max_response_bytes )) || return 1
  unzip -p -qq "$zip" bbslist.csv > "$work_dir/bbslist.csv" || return 1
  python3 "$script_dir/bbs-normalize.py" < "$work_dir/bbslist.csv" \
    > "$work_dir/list.json"
  jq -e 'type == "array" and length > 0' "$work_dir/list.json" >/dev/null
}

publish_copy() {
  local source=$1 target=$2 temporary
  temporary=$(mktemp "${target%/*}/publish.XXXXXX")
  cp "$source" "$temporary"
  mv "$temporary" "$target"
}

refresh_list_cache() {
  fetch_and_normalize || return 1
  publish_copy "$work_dir/list.json" "$list_cache_file"
}

refresh_list_cache_in_background() {
  (
    exec 9>"$cache_dir/list.lock"
    flock -n 9 || exit 0
    refresh_list_cache
  ) </dev/null >/dev/null 2>&1 &
}

valid_list_cache() {
  [[ -s $list_cache_file ]] \
    && (( $(stat -c '%s' -- "$list_cache_file") <= max_response_bytes )) \
    && jq -e 'type == "array" and length > 0' "$list_cache_file" >/dev/null 2>&1
}

action=${1:-list}
case "$action" in
  list)
    if valid_list_cache; then
      cat "$list_cache_file"
      if ! find "$list_cache_file" -mmin "-$list_cache_minutes" \
        -print -quit | grep -q .; then
        refresh_list_cache_in_background
      fi
      exit 0
    fi
    refresh_list_cache
    cat "$list_cache_file"
    ;;
  refresh)
    refresh_list_cache
    cat "$list_cache_file"
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 5: Run test to verify it passes**

Run: `chmod +x bbs-fetch && bash tests/fetch.test.sh`
Expected: `fetch.test.sh passed`

- [ ] **Step 6: Commit**

```bash
git add bbs-fetch tests/fetch.test.sh tests/fixtures/curl
git commit -m "Add bbs-fetch: monthly list resolution, cache, background refresh"
```

---

## Task 4: `BbsModel.js` — filtering, sorting, tier-join

**Files:**
- Create: `BbsModel.js`
- Test: `tests/model.test.mjs`

**Interfaces:**
- Consumes: normalized entry objects from Task 2's shape (`name, sysop, newLoginHint, host, telnetPort, sshPort, webUrl, location, country, software`), plus a `tiers` object shaped like `assets/tiers.json`.
- Produces (called from `BarWidget.qml` in Task 6):
  - `joinTiers(entries, tiers)` -> entries with a `tier` field (`"best"|"great"|"good"|null`)
  - `filterEntries(entries, {query, tier, protocol, software, country})` -> filtered array
  - `sortByTierThenName(entries)` -> sorted array (best first, then alphabetical)
  - `distinctValues(entries, key)` -> sorted array of unique values for a field
  - `connectUrl(entry, protocol)` -> `"telnet://host:port"` or `"ssh://host:port"` or `""`

- [ ] **Step 1: Write the failing test**

```js
// tests/model.test.mjs
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const testDir = path.dirname(fileURLToPath(import.meta.url))
const source = fs.readFileSync(path.join(testDir, "..", "BbsModel.js"), "utf8")
const model = { Array, String, Object }
vm.createContext(model)
vm.runInContext(source, model)

const entries = [
  { name: "20 For Beers BBS", sysop: "paul lee", host: "20forbeers.com",
    telnetPort: 1337, sshPort: 1338, location: "Portland, OR, USA",
    country: "USA", software: "Mystic", tier: null },
  { name: "0xDECAFBAD BBS", sysop: "", host: "bbs.decafbad.com",
    telnetPort: 6523, sshPort: null, location: "Seattle, WA, USA",
    country: "USA", software: "Synchronet", tier: null },
  { name: "84-24", sysop: "Michele Giorgi", host: "telnet.84-24.org",
    telnetPort: 23, sshPort: null, location: "Rimini, , Italy",
    country: "Italy", software: "Custom", tier: null },
]

const tiers = { best: ["20 For Beers BBS"], great: [], good: ["84-24"] }
const joined = model.joinTiers(entries, tiers)
assert.equal(joined.find(e => e.name === "20 For Beers BBS").tier, "best")
assert.equal(joined.find(e => e.name === "84-24").tier, "good")
assert.equal(joined.find(e => e.name === "0xDECAFBAD BBS").tier, null)
// joinTiers must not mutate its input.
assert.equal(entries[0].tier, null)

const sorted = model.sortByTierThenName(joined)
assert.equal(sorted[0].name, "20 For Beers BBS") // best first
assert.equal(sorted[sorted.length - 1].tier, null)

assert.equal(model.filterEntries(joined, { tier: "best" }).length, 1)
assert.equal(model.filterEntries(joined, { protocol: "ssh" }).length, 1)
assert.equal(model.filterEntries(joined, { country: "Italy" }).length, 1)
assert.equal(model.filterEntries(joined, { software: "Mystic" }).length, 1)
assert.equal(model.filterEntries(joined, { query: "decafbad" }).length, 1)
assert.equal(model.filterEntries(joined, { query: "portland" }).length, 1) // matches location
assert.equal(model.filterEntries(joined, { query: "nonexistent" }).length, 0)
assert.equal(model.filterEntries(joined, {}).length, 3)

assert.deepEqual(model.distinctValues(joined, "country"), ["Italy", "USA"])

assert.equal(model.connectUrl(entries[0], "telnet"), "telnet://20forbeers.com:1337")
assert.equal(model.connectUrl(entries[0], "ssh"), "ssh://20forbeers.com:1338")
assert.equal(model.connectUrl(entries[1], "ssh"), "") // no ssh port -> empty

console.log("model.test.mjs passed")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node tests/model.test.mjs`
Expected: FAIL (`BbsModel.js` does not exist / `model.joinTiers is not a function`).

- [ ] **Step 3: Write the implementation**

```js
// BbsModel.js
.pragma library

function tierRank(tier) {
  if (tier === "best") return 3
  if (tier === "great") return 2
  if (tier === "good") return 1
  return 0
}

function joinTiers(entries, tiers) {
  var lookup = {}
  var groups = tiers || {}
  var tierNames = ["best", "great", "good"]
  for (var t = 0; t < tierNames.length; t++) {
    var tierName = tierNames[t]
    var names = Array.isArray(groups[tierName]) ? groups[tierName] : []
    for (var n = 0; n < names.length; n++) lookup["$" + names[n]] = tierName
  }

  var output = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var tier = lookup["$" + entry.name] || null
    if (tier === entry.tier) {
      output.push(entry)
      continue
    }
    var copy = {}
    for (var key in entry) copy[key] = entry[key]
    copy.tier = tier
    output.push(copy)
  }
  return output
}

function matchesQuery(entry, query) {
  if (!query) return true
  var fields = [entry.name, entry.sysop, entry.software, entry.location, entry.country]
  for (var i = 0; i < fields.length; i++) {
    if (String(fields[i] || "").toLowerCase().indexOf(query) >= 0) return true
  }
  return false
}

function matchesProtocol(entry, protocol) {
  if (!protocol || protocol === "all") return true
  if (protocol === "telnet") return entry.telnetPort !== null && entry.telnetPort !== undefined
  if (protocol === "ssh") return entry.sshPort !== null && entry.sshPort !== undefined
  return true
}

function filterEntries(entries, filters) {
  var opts = filters || {}
  var query = String(opts.query || "").trim().toLowerCase()
  var tier = opts.tier || "all"
  var protocol = opts.protocol || "all"
  var software = opts.software || "all"
  var country = opts.country || "all"

  var output = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (tier !== "all" && entry.tier !== tier) continue
    if (software !== "all" && entry.software !== software) continue
    if (country !== "all" && entry.country !== country) continue
    if (!matchesProtocol(entry, protocol)) continue
    if (!matchesQuery(entry, query)) continue
    output.push(entry)
  }
  return output
}

function sortByTierThenName(entries) {
  var output = entries.slice()
  output.sort(function (a, b) {
    var rankDiff = tierRank(b.tier) - tierRank(a.tier)
    if (rankDiff !== 0) return rankDiff
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0
  })
  return output
}

function distinctValues(entries, key) {
  var seen = {}
  var output = []
  for (var i = 0; i < entries.length; i++) {
    var value = entries[i][key]
    if (!value || seen[value]) continue
    seen[value] = true
    output.push(value)
  }
  output.sort()
  return output
}

function connectUrl(entry, protocol) {
  if (!entry || !entry.host) return ""
  if (protocol === "ssh") return entry.sshPort ? "ssh://" + entry.host + ":" + entry.sshPort : ""
  return entry.telnetPort ? "telnet://" + entry.host + ":" + entry.telnetPort : ""
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node tests/model.test.mjs`
Expected: `model.test.mjs passed`

- [ ] **Step 5: Commit**

```bash
git add BbsModel.js tests/model.test.mjs
git commit -m "Add BbsModel: filtering, sorting, and tier-join logic"
```

---

## Task 5: `bbs-connect` — the launch-or-report-missing helper

**Files:**
- Create: `bbs-connect`
- Test: `tests/connect.test.sh`

**Interfaces:**
- Consumes: a single `telnet://host:port` or `ssh://host:port` argument (from `BbsModel.connectUrl`, Task 4).
- Produces: exit code `0` on a successful launch, `2` on a malformed URL, `3` specifically when `syncterm` is not installed (this exact code is what `BarWidget.qml`, Task 6, checks to decide whether to show the copy-address fallback instead of a generic error).

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/connect.test.sh
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

# 1. Malformed URL is rejected before anything else.
if "$project_dir/bbs-connect" 'not-a-url' >/dev/null 2>&1; then
  echo "Malformed URL was accepted" >&2
  exit 1
fi

# 2. syncterm missing -> exit code 3, no PATH entry for it.
set +e
PATH="/usr/bin:/bin" "$project_dir/bbs-connect" 'telnet://20forbeers.com:1337' >/dev/null 2>&1
missing_status=$?
set -e
[[ $missing_status == 3 ]] || { echo "Expected exit 3, got $missing_status" >&2; exit 1; }

# 3. syncterm present -> launches via omarchy-launch-terminal with the URL.
mkdir -p "$test_root/bin"
cat > "$test_root/bin/syncterm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_root/bin/syncterm"
cat > "$test_root/bin/omarchy-launch-terminal" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$test_root/launch-args.txt"
EOF
chmod +x "$test_root/bin/omarchy-launch-terminal"
PATH="$test_root/bin:/usr/bin:/bin" "$project_dir/bbs-connect" 'telnet://20forbeers.com:1337'
[[ "$(cat "$test_root/launch-args.txt")" == $'syncterm\ntelnet://20forbeers.com:1337' ]]

echo "connect.test.sh passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/connect.test.sh`
Expected: FAIL (`bbs-connect: No such file or directory`).

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
# bbs-connect
set -euo pipefail

url=${1:?Usage: bbs-connect <telnet://or ssh://host:port>}
[[ $url =~ ^(telnet|ssh)://[A-Za-z0-9.-]+:[0-9]{1,5}$ ]] \
  || { echo "Invalid connect URL: $url" >&2; exit 2; }

if ! command -v syncterm >/dev/null 2>&1; then
  echo "syncterm not installed" >&2
  exit 3
fi

exec omarchy-launch-terminal syncterm "$url"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x bbs-connect && bash tests/connect.test.sh`
Expected: `connect.test.sh passed`

- [ ] **Step 5: Commit**

```bash
git add bbs-connect tests/connect.test.sh
git commit -m "Add bbs-connect: launch SyncTERM or report it's missing"
```

---

## Task 6: `BbsService.qml` — cache loading and fetch plumbing

**Files:**
- Create: `BbsService.qml`

**Interfaces:**
- Consumes: `bbs-fetch` (Task 3), `assets/tiers.json` (Task 1), `BbsModel.joinTiers` (Task 4).
- Produces (consumed by `BarWidget.qml`, Task 7):
  - `property var entries` — tier-joined array, updated whenever the cache file or `tiers.json` changes.
  - `property bool fetching`
  - `property string fetchError` — empty string when there is no error.
  - `function refresh()` — forces `bbs-fetch refresh`.

This is plumbing, not user-facing UI, so its test cycle is the manual check in Step 3 below plus `qmllint` — there's no separate automated test file for it (its logic is a thin wire between the already-tested `bbs-fetch` and `BbsModel.js`).

- [ ] **Step 1: Write the component**

```qml
// BbsService.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "BbsModel.js" as BbsModel

Item {
  id: root

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string cacheFile: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
  readonly property string listCachePath: root.cacheFile + "/omarchy-bbs/list.json"

  property var rawEntries: []
  property var tiers: ({ best: [], great: [], good: [] })
  readonly property var entries: BbsModel.joinTiers(root.rawEntries, root.tiers)
  property bool fetching: false
  property string fetchError: ""

  function applyList(raw) {
    try {
      var parsed = JSON.parse(raw || "[]")
      root.rawEntries = Array.isArray(parsed) ? parsed : []
      root.fetchError = ""
    } catch (error) {
      root.fetchError = "Could not read the cached BBS list."
    }
  }

  function applyTiers(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      root.tiers = {
        best: Array.isArray(parsed.best) ? parsed.best : [],
        great: Array.isArray(parsed.great) ? parsed.great : [],
        good: Array.isArray(parsed.good) ? parsed.good : []
      }
    } catch (error) {
      root.tiers = { best: [], great: [], good: [] }
    }
  }

  function refresh() {
    if (root.fetching) return
    root.fetching = true
    fetchProcess.command = [root.pluginDir + "bbs-fetch", "refresh"]
    fetchProcess.running = true
  }

  FileView {
    id: tiersFile
    path: root.pluginDir + "assets/tiers.json"
    watchChanges: true
    onLoaded: root.applyTiers(text())
    onFileChanged: reload()
  }

  FileView {
    id: listFile
    path: root.listCachePath
    watchChanges: true
    onLoaded: root.applyList(text())
    onLoadFailed: function (error) {
      // The cache file does not exist yet on first run. Trigger a fetch
      // instead of treating this as an error.
      root.refresh()
    }
    onFileChanged: reload()
  }

  Process {
    id: primeProcess
    command: [root.pluginDir + "bbs-fetch", "list"]
    onExited: function (exitCode) {
      if (exitCode === 0) listFile.reload()
    }
  }

  Process {
    id: fetchProcess
    command: []
    onExited: function (exitCode) {
      root.fetching = false
      if (exitCode === 0) {
        listFile.reload()
      } else {
        root.fetchError = "Could not refresh the BBS list."
      }
    }
  }

  Component.onCompleted: {
    primeProcess.running = true
  }
}
```

- [ ] **Step 2: Manual verification**

Run: `qmllint -I /usr/share/omarchy/shell BbsService.qml`
Expected: no errors.

Run (with the real plugin cloned at `~/.config/omarchy/plugins/paulie420.bbs`):
```bash
~/.config/omarchy/plugins/paulie420.bbs/bbs-fetch list \
  > /tmp/bbs-manual-check.json
jq 'length' /tmp/bbs-manual-check.json
```
Expected: a positive integer (confirms the real network path works end to end before wiring the UI on top of it).

- [ ] **Step 3: Commit**

```bash
git add BbsService.qml
git commit -m "Add BbsService: cache loading and fetch plumbing"
```

---

## Task 7: `BarWidget.qml` — bar icon and dropdown panel

**Files:**
- Create: `BarWidget.qml`

**Interfaces:**
- Consumes: `BbsService.qml` (Task 6, instantiated inline), `BbsModel.js` (Task 4), `bbs-connect` (Task 5).
- Produces: the plugin's only entry point (`manifest.json`'s `barWidget`), so this task is the first point the whole plugin is visually testable.

This is the biggest task; it follows `paulie420.vpn/BarWidget.qml`'s shape exactly (a `Panel`-rooted root with a `BarIconButton` and an embedded `KeyboardPanel`), swapping VPN's provider list for a searchable/filterable BBS directory. A `ListView` (not a `Repeater`) is used for the row list specifically because it can hold 1,000+ entries — a `Repeater` would eagerly instantiate every delegate, which is fine for VPN's handful of providers but not here.

- [ ] **Step 1: Write the component**

```qml
// BarWidget.qml
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "BbsModel.js" as BbsModel

Panel {
  id: root
  moduleName: "paulie420.bbs"
  ipcTarget: "paulie420.bbs"

  // Without this pair the bar's ModuleSlot collapses to 0x0: Panel derives
  // from Item, which has no implicit size of its own.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string activeTab: "directory"
  property string query: ""
  property string tierFilter: "all"
  property string protocolFilter: "all"
  property string softwareFilter: "all"
  property string countryFilter: "all"
  property var selectedEntry: null
  property string connectNotice: ""

  BbsService { id: service }

  readonly property var visibleEntries: BbsModel.sortByTierThenName(
    BbsModel.filterEntries(service.entries, {
      query: root.query, tier: root.tierFilter, protocol: root.protocolFilter,
      software: root.softwareFilter, country: root.countryFilter
    }))
  readonly property var softwareOptions: BbsModel.distinctValues(service.entries, "software")
  readonly property var countryOptions: BbsModel.distinctValues(service.entries, "country")

  function selectEntry(entry) { root.selectedEntry = entry; root.connectNotice = "" }
  function closeDetail() { root.selectedEntry = null; root.connectNotice = "" }

  function connect(protocol) {
    if (!root.selectedEntry) return
    var url = BbsModel.connectUrl(root.selectedEntry, protocol)
    if (!url) return
    // Reuses BbsService's own resolvedUrl-based pluginDir (matching
    // akshar.radio-atlas's playerPath precedent) instead of a hardcoded
    // install path, so this keeps working regardless of where the plugin
    // is actually installed.
    connectProcess.command = [service.pluginDir + "bbs-connect", url]
    connectProcess.expectedUrl = url
    connectProcess.running = true
  }

  function copyAddress() {
    if (!root.selectedEntry) return
    var url = BbsModel.connectUrl(root.selectedEntry, "telnet") || BbsModel.connectUrl(root.selectedEntry, "ssh")
    copyProcess.command = ["wl-copy", url]
    copyProcess.running = true
    root.connectNotice = "Copied " + url
  }

  Process {
    id: connectProcess
    property string expectedUrl: ""
    command: []
    onExited: function (exitCode) {
      if (exitCode === 3) {
        root.connectNotice = "SyncTERM is not installed. Copy the address below and use another client."
      } else if (exitCode !== 0) {
        root.connectNotice = "Could not launch SyncTERM."
      } else {
        root.close()
      }
    }
  }

  Process {
    id: copyProcess
    command: []
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "☎" // U+260E BLACK TELEPHONE — plain Unicode so it renders
                    // even without the Nerd Font glyph set omarchy.ttf ships;
                    // swap for a matching nf-md glyph if visual consistency
                    // with other bar icons matters more, but verify it does
                    // not render as a tofu box first.
    tooltipText: "BBS Guide"
    slotSize: Style.bar.statusSlot
    fontSize: Style.bar.iconFont
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Style.space(520), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.selectedEntry ? root.closeDetail() : root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(16)

          Text {
            text: "DIRECTORY"
            color: root.activeTab === "directory" ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.activeTab === "directory"
            MouseArea { anchors.fill: parent; onClicked: root.activeTab = "directory" }
          }
          Text {
            text: "HOW TO CONNECT"
            color: root.activeTab === "howto" ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.activeTab === "howto"
            MouseArea { anchors.fill: parent; onClicked: root.activeTab = "howto" }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ---- Directory tab -------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.activeTab === "directory" && !root.selectedEntry

          TextField {
            width: parent.width
            placeholderText: "Search name, sysop, software, location…"
            text: root.query
            onTextChanged: root.query = text
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: ["all", "best", "great", "good"]
              Rectangle {
                required property string modelData
                width: chipLabel.implicitWidth + Style.space(12)
                height: chipLabel.implicitHeight + Style.space(6)
                radius: Style.space(4)
                color: root.tierFilter === modelData ? Color.accent : "transparent"
                border.color: root.dim
                Text {
                  id: chipLabel
                  anchors.centerIn: parent
                  text: modelData.toUpperCase()
                  color: root.tierFilter === modelData ? Color.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.tierFilter = parent.modelData }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: ["all", "telnet", "ssh"]
              Rectangle {
                required property string modelData
                width: protoLabel.implicitWidth + Style.space(12)
                height: protoLabel.implicitHeight + Style.space(6)
                radius: Style.space(4)
                color: root.protocolFilter === modelData ? Color.accent : "transparent"
                border.color: root.dim
                Text {
                  id: protoLabel
                  anchors.centerIn: parent
                  text: modelData.toUpperCase()
                  color: root.protocolFilter === modelData ? Color.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.protocolFilter = parent.modelData }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            ComboBox {
              width: (parent.width - Style.space(8)) / 2
              model: ["all"].concat(root.softwareOptions)
              onActivated: root.softwareFilter = currentText
            }
            ComboBox {
              width: (parent.width - Style.space(8)) / 2
              model: ["all"].concat(root.countryOptions)
              onActivated: root.countryFilter = currentText
            }
          }

          Text {
            text: root.visibleEntries.length + " of " + service.entries.length + " BBSes"
              + (service.fetching ? "  ·  refreshing…" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: service.fetchError !== ""
            text: service.fetchError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          ListView {
            width: parent.width
            height: Style.space(320)
            clip: true
            model: root.visibleEntries
            delegate: Item {
              id: rowItem
              required property var modelData
              width: ListView.view.width
              height: rowLabel.implicitHeight + rowMeta.implicitHeight + Style.space(10)

              Rectangle {
                anchors.fill: parent
                color: rowMouse.containsMouse ? root.hoverFill : "transparent"
                radius: Style.space(4)
              }

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(4)
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(6)
                  Text {
                    visible: rowItem.modelData.tier !== null
                    text: rowItem.modelData.tier ? rowItem.modelData.tier.toUpperCase() : ""
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    id: rowLabel
                    text: rowItem.modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
                Text {
                  id: rowMeta
                  text: rowItem.modelData.software + "  ·  " + rowItem.modelData.location
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectEntry(rowItem.modelData)
              }
            }
          }
        }

        // ---- Detail view ----------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.selectedEntry !== null

          Text {
            text: "← Back"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea { anchors.fill: parent; onClicked: root.closeDetail() }
          }

          Text {
            visible: root.selectedEntry !== null
            text: root.selectedEntry ? root.selectedEntry.name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: root.selectedEntry ? [
              { k: "Sysop", v: root.selectedEntry.sysop || "Unknown" },
              { k: "Software", v: root.selectedEntry.software || "Unknown" },
              { k: "Location", v: root.selectedEntry.location || "Unknown" },
              { k: "Telnet", v: root.selectedEntry.host + ":" + root.selectedEntry.telnetPort },
              { k: "SSH", v: root.selectedEntry.sshPort ? (root.selectedEntry.host + ":" + root.selectedEntry.sshPort) : "Not offered" },
              { k: "Web", v: root.selectedEntry.webUrl || "None" },
              { k: "New user login", v: root.selectedEntry.newLoginHint || "Ask the sysop" }
            ] : []

            Item {
              required property var modelData
              width: parent.width
              height: kLabel.implicitHeight
              Text {
                id: kLabel
                anchors.left: parent.left
                text: modelData.k
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                text: modelData.v
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width * 0.6
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          Row {
            spacing: Style.space(8)
            Rectangle {
              width: connectLabel.implicitWidth + Style.space(16)
              height: connectLabel.implicitHeight + Style.space(8)
              radius: Style.space(4)
              color: Color.accent
              Text { id: connectLabel; anchors.centerIn: parent; text: "Connect (Telnet)"
                     color: Color.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.connect("telnet") }
            }
            Rectangle {
              visible: root.selectedEntry && root.selectedEntry.sshPort
              width: sshLabel.implicitWidth + Style.space(16)
              height: sshLabel.implicitHeight + Style.space(8)
              radius: Style.space(4)
              border.color: root.dim
              Text { id: sshLabel; anchors.centerIn: parent; text: "Connect (SSH)"
                     color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.connect("ssh") }
            }
            Rectangle {
              width: copyLabel.implicitWidth + Style.space(16)
              height: copyLabel.implicitHeight + Style.space(8)
              radius: Style.space(4)
              border.color: root.dim
              Text { id: copyLabel; anchors.centerIn: parent; text: "Copy address"
                     color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.copyAddress() }
            }
          }

          Text {
            visible: root.connectNotice !== ""
            text: root.connectNotice
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }

        // ---- How-to-connect tab -----------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "howto"

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            text: "Telnet is the historical, usually anonymous-friendly way "
              + "to reach a BBS — just an address and a port. SSH almost "
              + "always requires an account on that BBS already, since it's "
              + "authenticated.\n\n"
              + "SyncTERM (AUR: syncterm) is the recommended client — this "
              + "button launches it directly. NetRunner and TERMinator/qodem "
              + "are common alternatives if you'd rather use something else: "
              + "paste the host as the address, and set the port and "
              + "protocol (telnet or ssh) shown in a listing's detail view."
          }
        }
      }
    }
  }
}
```

- [ ] **Step 2: qmllint check**

Run: `qmllint -I /usr/share/omarchy/shell BarWidget.qml`
Expected: no errors. Fix any reported issues (e.g. missing `required property` on a delegate, unresolved type) before moving on.

- [ ] **Step 3: Manifest validation**

Run: `omarchy plugin validate .`
Expected: passes.

- [ ] **Step 4: Manual render check**

```bash
omarchy-shell shell rescanPlugins
qs -p /usr/share/omarchy/shell ipc call shell debugBarGeometry
```
Expected: `paulie420.bbs`'s bar item reports non-zero width/height. If it doesn't, restart the shell fully (`omarchy restart shell`) before assuming the QML is wrong — this codebase's plugins have repeatedly hit stale-compiled-QML after edits that only `rescanPlugins` (not a full restart) fails to clear.

Then, from the bar: left-click the BBS icon, confirm the Directory tab lists entries, that typing in the search field narrows them, that the tier/protocol chips and software/country dropdowns filter correctly, that clicking a row opens its detail view with correct host/port info, and that the How-to-Connect tab renders.

- [ ] **Step 5: Commit**

```bash
git add BarWidget.qml
git commit -m "Add BBS directory bar widget and dropdown panel"
```

---

## Task 8: Connect flow verification, README, and pre-push scrub

**Files:**
- Modify: `README.md`
- Verify: all files (personal-data / AI-mention scrub)

**Interfaces:** none new — this task closes out the plugin for its first real push.

- [ ] **Step 1: Manual connect-flow check**

With `syncterm` installed (it already is on this machine), open the panel, select any entry, click "Connect (Telnet)", and confirm a terminal opens running SyncTERM connected to that address. Click "Connect (SSH)" on an entry that has an SSH port (e.g. 20 For Beers BBS) and confirm the same over SSH. Then temporarily rename `/usr/bin/syncterm` (or override `PATH` for a manual test run) and confirm the panel shows "SyncTERM is not installed…" and that "Copy address" places the address on the clipboard (`wl-paste` to check).

- [ ] **Step 2: Write the README**

```markdown
# BBS Guide

Browse, search, and connect to classic telnet/SSH Bulletin Board Systems
from the Omarchy bar. Ships a curated Best/Great/Good tier above the full
directory, and a built-in guide to the terminal clients you'll need.

## Install

```bash
omarchy plugin add https://github.com/Paulie420/omarchy-bbs.git --enable
```

BBS Guide uses `curl`, `jq`, `python3`, `unzip`, and `wl-copy`. These ship
with Omarchy. Connecting requires `syncterm` (AUR); without it, BBS Guide
falls back to letting you copy the address for another client.

## Data and attribution

BBS listings come from the [Telnet BBS Guide](https://www.telnetbbsguide.com/),
used with the site owner's permission. The list refreshes monthly and is
cached locally at `~/.cache/omarchy-bbs/list.json`.

## Curation

The Best/Great/Good tiers are hand-curated by the plugin author in
`assets/tiers.json` and shipped via releases — there is no voting system.
Suggestions are welcome as GitHub issues.

## Development

```bash
./tests/run
qmllint -I /usr/share/omarchy/shell BarWidget.qml BbsService.qml
```
```

- [ ] **Step 3: Write `tests/run`**

```bash
#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

jq -e '
  .schemaVersion == 1
  and .id == "paulie420.bbs"
  and (.kinds | index("bar-widget"))
' "$project_dir/manifest.json" >/dev/null

bash -n "$project_dir/bbs-fetch" "$project_dir/bbs-connect"
python3 -m py_compile "$project_dir/bbs-normalize.py"

python3 "$project_dir/tests/normalize.test.py"
node "$project_dir/tests/model.test.mjs"
bash "$project_dir/tests/fetch.test.sh"
bash "$project_dir/tests/connect.test.sh"

echo "All tests passed"
```

Run: `chmod +x tests/run && ./tests/run`
Expected: `All tests passed`

- [ ] **Step 4: Pre-push scrub**

Run these checks and fix anything they surface before pushing:

```bash
rg -i 'claude|anthropic' --hidden --glob '!.git' .
rg -n '20\.0forbeers|192\.168\.|10\.0\.0\.' --hidden --glob '!.git' . || true
```
Expected: the first command returns nothing. The second is a sanity check that no other personal IPs/hostnames beyond the intentionally-public `20forbeers.com` BBS listing (which is public data from the source list, not a secret) leaked into any default or example.

- [ ] **Step 5: Final commit and push**

```bash
git add README.md tests/run
git commit -m "Add README and test orchestrator"
git push -u origin main
```

---

## Self-Review Notes

- **Spec coverage:** data pipeline (Tasks 3, 6), curation with no voting (Task 1's placeholder `tiers.json` + `BbsModel.joinTiers`, Task 4), search/filter by name/sysop/software/location/country/protocol/tier (Task 4, wired into UI in Task 7), connect flow via SyncTERM with copy-address fallback (Tasks 5, 7, 8), How-to-Connect content (Task 7), testing and validation gates (Tasks 2–8), licensing/attribution (README in Task 8), no-special-case for 20forbeers.com (Global Constraints, and Task 7's UI treats every entry identically).
- **Placeholder scan:** no TBD/TODO markers; the one intentionally-empty artifact (`assets/tiers.json`) is explicitly called out as a follow-up content task in the spec and Global Constraints, not left ambiguous.
- **Type consistency:** the normalized entry shape (`name, sysop, newLoginHint, host, telnetPort, sshPort, webUrl, location, country, software, tier`) is introduced in Task 2 and used identically in Tasks 3, 4, 6, and 7 — `host` (not `telnetHost`) is used consistently everywhere, including in `BbsModel.connectUrl`.
