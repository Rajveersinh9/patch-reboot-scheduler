# Patch & Reboot Scheduler

## Purpose
Automates OS patching and scheduled reboots with logging and alerting to Slack/email.

## Prereqs
- Linux: apt/yum/dnf, curl, mailutils (optional)
- Windows: PowerShell (Run as Admin), PSWindowsUpdate module
- Optional: Slack incoming webhook

## Quick test (Linux)
DRY_RUN=1 ./scripts/patch_reboot.sh
