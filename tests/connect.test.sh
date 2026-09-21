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

# 2. syncterm missing -> exit code 3. Uses an isolated, deliberately empty
# PATH directory rather than trusting the real system PATH to lack syncterm
# -- syncterm is this plugin's own recommended client and is commonly
# installed on real Omarchy systems (it is on this dev machine too), so a
# real system PATH is not a reliable way to simulate "not installed".
# bash itself is resolved to an absolute path first (real_bash) and invoked
# directly, bypassing the script's own "#!/usr/bin/env bash" shebang, which
# would otherwise fail to resolve "bash" under the emptied PATH.
mkdir -p "$test_root/empty-bin"
real_bash=$(command -v bash)
set +e
PATH="$test_root/empty-bin" "$real_bash" "$project_dir/bbs-connect" 'telnet://20forbeers.com:1337' >/dev/null 2>&1
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
