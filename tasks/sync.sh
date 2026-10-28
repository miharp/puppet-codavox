#!/bin/bash
# One codavox reconciliation on this node: poll the publisher, converge every
# environment it serves, and expire OpenVox Server's cache for each one that
# moved. The publisher comes from /etc/codavox/config.yaml, as for the service.
#
# The exit status is the agent's own: 0 only when this node is fully converged,
# cache flush included. The agent's log is returned either way, since it names
# the environment that failed and why.
set -uo pipefail

# JSON-encodes one line. Control characters other than tab and carriage return
# are dropped, since JSON cannot carry them raw. Each task carries its own copy
# of these helpers, so it runs under any task runner without helper files.
json_string() {
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  printf '"%s"' "$s"
}

# JSON-encodes each line of $1 as an array of strings.
json_lines() {
  local line sep=''
  printf '['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s%s' "$sep" "$(json_string "$line")"
    sep=','
  done <<<"$1"
  printf ']'
}

fail() {
  printf '{"status":"failed","log":%s,"_error":{"msg":%s,"kind":"codavox/sync-failed","details":{"exit_code":%d}}}\n' \
    "$(json_lines "${3:-}")" "$(json_string "$1")" "$2"
  exit 1
}

# The agent reads this node's Puppet private key and writes under
# /opt/puppetlabs/codavox, both root's. Say so, rather than return its
# permission errors.
if [ "$(id -u)" -ne 0 ]; then
  fail "codavox::sync must run as root (in OpenBolt, --run-as root)" 1
fi
if ! command -v codavox >/dev/null 2>&1; then
  fail "codavox is not installed on this node" 1
fi

log=$(codavox agent --once 2>&1)
exit_code=$?

if [ "$exit_code" -ne 0 ]; then
  # The agent's last line is its summary: `codavox: failed to sync: production`.
  last=$(printf '%s\n' "$log" | sed '/^$/d' | tail -n 1)
  fail "codavox agent --once did not converge this node: ${last#codavox: }" "$exit_code" "$log"
fi

printf '{"status":"converged","log":%s}\n' "$(json_lines "$log")"
