#!/bin/bash
# ocs-runner.sh — dijalankan oleh systemd timer (sebagai root) di server OCS.
# Alur: git pull -> jalankan tasks/*.sh yang belum pernah jalan (urut nama)
#       -> simpan output ke logs/<task>.log -> catat di state/done.log -> push.
# Kalau satu task gagal, task berikutnya TIDAK dijalankan (biar tidak lanjut di kondisi rusak).
# Seluruh logika dibungkus main() supaya aman walau file ini ter-update saat git pull.

set -u

REPO_DIR="${REPO_DIR:-/opt/ocsaeon}"
LOCK_FILE="${LOCK_FILE:-/run/ocsaeon-runner.lock}"
TASK_TIMEOUT="${TASK_TIMEOUT:-3600}"   # detik, batas maksimal satu task

log() { echo "[$(date '+%F %T')] $*"; }

git_sync_pull() {
  git -C "$REPO_DIR" pull --rebase --autostash -q origin main
}

git_push_changes() {
  local msg="$1"
  git -C "$REPO_DIR" add logs state
  if git -C "$REPO_DIR" diff --cached --quiet; then
    return 0
  fi
  git -C "$REPO_DIR" commit -q -m "$msg"
  if ! git -C "$REPO_DIR" push -q origin main; then
    log "push gagal, coba pull --rebase lalu push ulang"
    git_sync_pull && git -C "$REPO_DIR" push -q origin main
  fi
}

task_done() {
  # sudah pernah dijalankan (berhasil atau gagal) -> jangan jalan ulang
  grep -q "^$1|" "$REPO_DIR/state/done.log" 2>/dev/null
}

main() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "runner lain masih jalan, skip"
    exit 0
  fi

  cd "$REPO_DIR" || { log "repo tidak ada di $REPO_DIR"; exit 1; }
  mkdir -p logs state
  touch state/done.log

  if ! git_sync_pull; then
    log "git pull gagal (cek koneksi / deploy key)"
    exit 1
  fi

  local task name logf start end rc
  for task in $(ls tasks/*.sh 2>/dev/null | sort); do
    name="$(basename "$task")"
    task_done "$name" && continue

    logf="logs/${name%.sh}.log"
    start="$(date '+%F %T %Z')"
    log "menjalankan $name"

    # Tandai sedang jalan, push dulu supaya kelihatan dari GitHub
    {
      echo "=== TASK   : $name"
      echo "=== HOST   : $(hostname)"
      echo "=== MULAI  : $start"
      echo "=== STATUS : RUNNING"
    } > "$logf"
    git_push_changes "server: mulai $name"

    {
      echo "=== TASK   : $name"
      echo "=== HOST   : $(hostname)"
      echo "=== MULAI  : $start"
      echo "-----------------------------------------------------------"
    } > "$logf"

    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
      timeout "$TASK_TIMEOUT" bash "$task" </dev/null >>"$logf" 2>&1
    rc=$?
    end="$(date '+%F %T %Z')"

    {
      echo "-----------------------------------------------------------"
      echo "=== SELESAI: $end"
      if [ "$rc" -eq 0 ]; then
        echo "=== STATUS : OK (exit 0)"
      elif [ "$rc" -eq 124 ]; then
        echo "=== STATUS : TIMEOUT (> ${TASK_TIMEOUT}s)"
      else
        echo "=== STATUS : GAGAL (exit $rc)"
      fi
    } >> "$logf"

    echo "$name|$rc|$start|$end" >> state/done.log

    if [ "$rc" -ne 0 ]; then
      # Task lain yang sudah antre saat ini ditandai SKIP (tidak akan pernah jalan).
      # Perbaikan harus dibuat sebagai task baru.
      local other oname
      for other in $(ls tasks/*.sh 2>/dev/null | sort); do
        oname="$(basename "$other")"
        task_done "$oname" && continue
        echo "$oname|skip|$end|dilewati karena $name gagal" >> state/done.log
        log "SKIP $oname"
      done
      git_push_changes "server: $name GAGAL (exit $rc), task antre di-skip"
      log "$name gagal (exit $rc)"
      break
    fi

    git_push_changes "server: $name selesai (exit $rc)"
  done
}

main "$@"
exit $?
