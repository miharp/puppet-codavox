#!/bin/bash
# `codavox deploy --wait` on the primary: r10k stages the code, the publisher
# seals it, and the task returns once the publisher serves the new code_id.
# Compilers pick it up on their next poll, or on codavox::sync.
#
# r10k, its configuration, and the basedir come from /etc/codavox/config.yaml,
# as for the deploy server.
set -uo pipefail

# JSON-encodes one line. Control characters other than tab and carriage return
# are dropped, since JSON cannot carry them raw: r10k's output can hold them.
json_string() {
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  printf '"%s"' "$s"
}

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

# fail <message> <exit code> [results JSON] [stderr]
fail() {
  printf '{"results":%s,"_error":{"msg":%s,"kind":"codavox/deploy-failed","details":{"exit_code":%d,"stderr":%s}}}\n' \
    "${3:-[]}" "$(json_string "$1")" "$2" "$(json_lines "${4:-}")"
  exit 1
}

# Parameters arrive as JSON text: an array is ["production","staging"]. The
# metadata restricts every element to \w+, which leaves nothing to unescape;
# anything else is refused here too, for a runner that did not check.
names() {
  local raw=$1 part name
  raw=${raw#[}
  raw=${raw%]}
  IFS=',' read -ra parts <<<"$raw"
  for part in "${parts[@]}"; do
    name=${part//[[:space:]]/}
    name=${name#\"}
    name=${name%\"}
    [[ $name =~ ^[A-Za-z0-9_]+$ ]] || return 1
    printf '%s\n' "$name"
  done
}

if [ "$(id -u)" -ne 0 ]; then
  fail "codavox::deploy must run as root (in OpenBolt, --run-as root)" 1
fi
if ! command -v codavox >/dev/null 2>&1; then
  fail "codavox is not installed on this node" 1
fi

args=(deploy --wait --json)

envs=()
if [ -n "${PT_environments:-}" ]; then
  list=$(names "$PT_environments") && [ -n "$list" ] ||
    fail "environments must be a non-empty array of environment names" 1
  mapfile -t envs <<<"$list"
fi
case "${PT_all:-false}:${#envs[@]}" in
  true:0) args+=(--all) ;;
  true:*) fail "give environments or all, not both" 1 ;;
  *:0) fail "give environments, or all: true to deploy every environment" 1 ;;
  *) args+=("${envs[@]}") ;;
esac

if [ -n "${PT_modules:-}" ]; then
  list=$(names "$PT_modules") && [ -n "$list" ] ||
    fail "modules must be a non-empty array of module names" 1
  args+=(--modules "$(printf '%s' "$list" | paste -sd, -)")
fi

stderr_file=$(mktemp)
trap 'rm -f "$stderr_file"' EXIT

results=$(codavox "${args[@]}" 2>"$stderr_file")
exit_code=$?
stderr=$(cat "$stderr_file")

# deploy prints its JSON array even when an environment fails, but not when it
# refuses the request outright.
case "$results" in
  \[*) ;;
  *) results='[]' ;;
esac

if [ "$exit_code" -ne 0 ]; then
  msg="codavox deploy failed (exit ${exit_code})"
  [ "$results" = '[]' ] || msg+="; results name each environment's outcome"
  last=$(printf '%s\n' "$stderr" | sed '/^$/d' | tail -n 1)
  [ -z "$last" ] || msg+=": ${last#codavox: }"
  fail "$msg" "$exit_code" "$results" "$(printf '%s\n' "$stderr" | tail -n 40)"
fi

printf '{"results":%s}\n' "$results"
