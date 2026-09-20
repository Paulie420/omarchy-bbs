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
