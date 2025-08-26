#!/bin/bash
set -euo pipefail

# Ensure displayplacer exists
if [[ ! -x /opt/homebrew/bin/displayplacer ]]; then
  echo "displayplacer not found at /opt/homebrew/bin/displayplacer" >&2
  exit 1
fi


# Determine execution context: if root, target the logged-in console user
dp_list_cmd=(/opt/homebrew/bin/displayplacer list)
dp_exec_prefix=()
if [[ "$(id -u)" -eq 0 ]]; then
  console_user=$(stat -f %Su /dev/console)
  if [[ -n "${console_user:-}" && "${console_user}" != "root" ]]; then
    console_uid=$(id -u "$console_user")
    # Prefer running within the user's GUI bootstrap domain
    if launchctl asuser "$console_uid" id >/dev/null 2>&1; then
      dp_list_cmd=(launchctl asuser "$console_uid" /opt/homebrew/bin/displayplacer list)
      dp_exec_prefix=(launchctl asuser "$console_uid" sudo -u "$console_user")
    else
      dp_list_cmd=(sudo -u "$console_user" /opt/homebrew/bin/displayplacer list)
      dp_exec_prefix=(sudo -u "$console_user")
    fi
  fi
fi

# Output the current display configuration
"${dp_list_cmd[@]}"