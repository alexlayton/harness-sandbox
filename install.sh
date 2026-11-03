#!/bin/sh
# Install harness-sandbox: a single script placed on your PATH.
set -eu

REPO="${HARNESS_SANDBOX_REPO:-alexlayton/harness-sandbox}"
ref="main"
bin_dir="${HARNESS_SANDBOX_BIN_DIR:-${HOME:-}/.local/bin}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version) [ "$#" -ge 2 ] || die "--version requires a value"; ref=$2; shift 2 ;;
        --bin-dir) [ "$#" -ge 2 ] || die "--bin-dir requires a value"; bin_dir=$2; shift 2 ;;
        -h|--help)
            printf 'Usage: install.sh [--version <tag|branch>] [--bin-dir <dir>]\n'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -n "$bin_dir" ] && [ "$bin_dir" != "/.local/bin" ] || die "HOME is not set; pass --bin-dir"
command -v curl >/dev/null 2>&1 || die "curl is required"
[ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] || \
    die "harness-sandbox needs Apple's 'container', which requires a Mac with Apple silicon"

tmp=$(mktemp "${TMPDIR:-/tmp}/harness-sandbox.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'Downloading harness-sandbox (%s)...\n' "$ref"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --retry 3 \
    --output "$tmp" "https://raw.githubusercontent.com/$REPO/$ref/harness-sandbox"
head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' || die "unexpected download contents"

mkdir -p "$bin_dir"
install -m 0755 "$tmp" "$bin_dir/harness-sandbox"
printf 'Installed harness-sandbox to %s/harness-sandbox\n' "$bin_dir"

case ":${PATH:-}:" in
    *":$bin_dir:"*) ;;
    *) printf 'warning: %s is not on PATH; add it to your shell configuration\n' "$bin_dir" >&2 ;;
esac
command -v container >/dev/null 2>&1 || \
    printf 'note: Apple container is not installed; see https://github.com/apple/container/releases\n' >&2
printf 'Next: run `harness-sandbox update` to pull the base image.\n'
