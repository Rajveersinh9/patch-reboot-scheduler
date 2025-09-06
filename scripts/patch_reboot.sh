#!/usr/bin/env bash
# patch_reboot.sh
# Usage: DRY_RUN=1 SLACK_WEBHOOK=... ADMIN_EMAIL=... ./patch_reboot.sh

set -o pipefail

# --- Configuration (override via env) ---
DRY_RUN="${DRY_RUN:-0}"             # set to 1 to test (no reboot, no real patch)
RETRIES="${RETRIES:-2}"             # number of retry attempts on failure
SLEEP_BETWEEN="${SLEEP_BETWEEN:-60}" # seconds between retries
LOGFILE="${LOGFILE:-./logs/patch_reboot.log}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

mkdir -p "$(dirname "$LOGFILE")"

timestamp() { date --iso-8601=seconds; }

log() {
  echo "$(timestamp) | $1" | tee -a "$LOGFILE"
}

send_slack() {
  [ -z "$SLACK_WEBHOOK" ] && return 0
  payload="{\"text\":\"$1\"}"
  curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1
}

send_email() {
  [ -z "$ADMIN_EMAIL" ] && return 0
  # Requires mailx or sendmail configured on the host
  echo -e "$1" | mail -s "Patch/Restart Alert: $(hostname)" "$ADMIN_EMAIL"
}

detect_pkg_mgr() {
  if command -v apt >/dev/null 2>&1; then echo "apt"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  else echo "unknown"
  fi
}

apply_patches() {
  mgr=$(detect_pkg_mgr)
  case "$mgr" in
    apt)
      sudo apt update -y && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
      return $?
      ;;
    yum|dnf)
      sudo $mgr -y update
      return $?
      ;;
    *)
      log "No supported package manager found."
      return 2
      ;;
  esac
}

attempt=0
while [ $attempt -le "$RETRIES" ]; do
  attempt=$((attempt+1))
  log "Attempt #$attempt: Starting patch operation (DRY_RUN=$DRY_RUN)..."
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1: Skipping actual patch; simulating success."
    PATCH_RC=0
  else
    apply_patches
    PATCH_RC=$?
  fi

  if [ "$PATCH_RC" -eq 0 ]; then
    log "Patch attempt #$attempt SUCCESS."
    send_slack "Patch succeeded on $(hostname) (attempt $attempt)."
    # If not dry run, reboot
    if [ "$DRY_RUN" != "1" ]; then
      log "Rebooting now..."
      # graceful reboot after 1 minute to allow processes to finish
      sudo shutdown -r +1 "Scheduled reboot after patch (initiated by patch_reboot.sh)"
    else
      log "DRY_RUN=1: Would have rebooted."
    fi
    echo "$(timestamp),$(hostname),patch,success,attempt:$attempt" >> "$LOGFILE"
    exit 0
  else
    log "Patch attempt #$attempt FAILED (rc=$PATCH_RC)."
    send_slack "ALERT: Patch failed on $(hostname) (attempt $attempt)."
    send_email "Patch failed on $(hostname). See logs: $LOGFILE"
    echo "$(timestamp),$(hostname),patch,failure,attempt:$attempt,rc:$PATCH_RC" >> "$LOGFILE"
    if [ $attempt -le "$RETRIES" ]; then
      log "Sleeping $SLEEP_BETWEEN seconds before retry..."
      sleep "$SLEEP_BETWEEN"
    else
      log "All attempts exhausted. Manual intervention required."
      exit 1
    fi
  fi
done
