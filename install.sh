#!/bin/bash
# Installs the login banner: script + systemd service (refreshes the banner on every boot).
# Usage:  sudo bash install.sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root:  sudo bash $0" >&2
  exit 1
fi

DIR=$(cd "$(dirname "$0")" && pwd)

install -m 0755 "$DIR/update-issue.sh"      /usr/local/sbin/update-issue.sh
install -m 0644 "$DIR/update-issue.service" /etc/systemd/system/update-issue.service

# Keep a backup of the original /etc/issue (first run only)
[ -f /etc/issue.orig ] || cp -a /etc/issue /etc/issue.orig

systemctl daemon-reload
systemctl enable update-issue.service

# Build the banner right now
/usr/local/sbin/update-issue.sh

echo
echo "Done. The banner will be refreshed on every boot."
echo "To see it now: log out of the console (exit) or switch consoles (Alt+F2, then Alt+F1)."
echo "Manual refresh:   sudo update-issue.sh"
echo "Restore original: sudo systemctl disable update-issue.service && sudo cp /etc/issue.orig /etc/issue"
