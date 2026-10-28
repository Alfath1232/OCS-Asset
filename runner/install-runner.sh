#!/bin/bash
# install-runner.sh — dijalankan SEKALI oleh admin di server:
#   sudo bash /opt/ocsaeon/runner/install-runner.sh
# Memasang systemd service + timer yang menjalankan ocs-runner.sh tiap 2 menit.
#
# Rollback (matikan otomatisasi total):
#   sudo systemctl disable --now ocsaeon-runner.timer
#   sudo rm /etc/systemd/system/ocsaeon-runner.{service,timer}
#   sudo systemctl daemon-reload

set -euo pipefail

REPO_DIR="/opt/ocsaeon"

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan dengan sudo." >&2
  exit 1
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Repo belum ada di $REPO_DIR. Clone dulu." >&2
  exit 1
fi

echo "== Set identitas git untuk commit dari server"
git -C "$REPO_DIR" config user.name  "ocsaeon-server"
git -C "$REPO_DIR" config user.email "ocsaeon-server@localhost"
git -C "$REPO_DIR" config pull.rebase true
if [ -f /root/.ssh/ocsaeon_deploy ]; then
  git -C "$REPO_DIR" config core.sshCommand \
    "ssh -i /root/.ssh/ocsaeon_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi

chmod 700 "$REPO_DIR/runner/ocs-runner.sh"

echo "== Tulis unit systemd"
cat > /etc/systemd/system/ocsaeon-runner.service <<'UNIT'
[Unit]
Description=OCS AEON GitOps task runner
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/ocsaeon/runner/ocs-runner.sh
Nice=5
UNIT

cat > /etc/systemd/system/ocsaeon-runner.timer <<'UNIT'
[Unit]
Description=Jalankan OCS AEON task runner tiap 2 menit

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=15s
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now ocsaeon-runner.timer

echo "== Jalankan runner sekali sekarang (tes)"
systemctl start ocsaeon-runner.service || true

echo
echo "== Status timer:"
systemctl list-timers ocsaeon-runner.timer --no-pager
echo
echo "== Log runner terakhir:"
journalctl -u ocsaeon-runner.service -n 15 --no-pager
