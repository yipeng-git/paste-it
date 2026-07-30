#!/usr/bin/env bash
# Inject PostHog credentials into a copied Info.plist (never commit the token).
#
# Sources (first wins for token):
#   1. POSTHOG_PROJECT_TOKEN env
#   2. Secrets/posthog.env (gitignored)
#
# Usage: inject_posthog_token /path/to/App.app/Contents/Info.plist

inject_posthog_token() {
  local plist="${1:?plist path required}"
  local root="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local token="${POSTHOG_PROJECT_TOKEN:-}"
  local host="${POSTHOG_HOST:-}"
  local env_file="$root/Secrets/posthog.env"

  if [[ -z "$token" && -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$env_file"
    set +a
    token="${POSTHOG_PROJECT_TOKEN:-}"
    host="${POSTHOG_HOST:-$host}"
  fi

  token="$(printf '%s' "$token" | tr -d '[:space:]')"
  host="$(printf '%s' "${host:-}" | tr -d '[:space:]')"

  if [[ -z "$token" ]]; then
    echo "  (PostHog: no token — analytics disabled for this build)"
    return 0
  fi

  if /usr/libexec/PlistBuddy -c 'Print :PostHogProjectToken' "$plist" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Set :PostHogProjectToken $token" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :PostHogProjectToken string $token" "$plist"
  fi

  if [[ -n "$host" ]]; then
    if /usr/libexec/PlistBuddy -c 'Print :PostHogHost' "$plist" &>/dev/null; then
      /usr/libexec/PlistBuddy -c "Set :PostHogHost $host" "$plist"
    else
      /usr/libexec/PlistBuddy -c "Add :PostHogHost string $host" "$plist"
    fi
  fi

  echo "  (PostHog: token injected into Info.plist)"
}
