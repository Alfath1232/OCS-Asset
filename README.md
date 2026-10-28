# ocsaeon — OCS Inventory server AEON (GitOps sederhana)

Repo ini dipakai untuk mengelola server OCS Inventory (`ocsaeon`) tanpa copy-paste command.

## Cara kerja

```
tasks/NNNN-nama.sh  ──push──▶  GitHub  ◀──pull tiap 2 menit──  server (systemd timer, root)
                                  ▲                                  │
                                  └──── logs/ + state/done.log ◀─────┘ (push hasil)
```

1. Script baru ditaruh di `tasks/` dengan nomor urut (`0002-...sh`, `0003-...sh`).
2. Server menjalankan task yang **belum pernah jalan**, urut nama, sebagai **root**.
3. Output tiap task masuk `logs/NNNN-nama.log`, ringkasannya di `state/done.log`
   (`task|exit code|mulai|selesai`).
4. Kalau satu task **gagal**, semua task lain yang sedang antre ditandai `skip`
   dan tidak akan pernah jalan. Perbaikan dibuat sebagai task **baru**
   (task lama tidak dijalankan ulang).

## Aturan

- **Siapa pun yang bisa push ke repo ini = root di server.** Repo wajib private,
  akses hanya untuk orang yang dipercaya.
- **Jangan pernah taruh password/secret di repo atau di output log.**
  Secret dibuat di server dan disimpan di `/root/ocsaeon-secrets/` (chmod 600),
  dibaca manual lewat SSH.
- Task harus non-interaktif (stdin = `/dev/null`).
- Batas waktu satu task: 3600 detik.
- Perubahan berisiko: task backup dulu, baru task perubahan.

## Struktur

| Path | Isi |
|---|---|
| `runner/ocs-runner.sh` | Runner yang dipanggil timer |
| `runner/install-runner.sh` | Pemasang systemd service + timer (sekali saja) |
| `tasks/` | Script yang akan dijalankan server |
| `logs/` | Output dari server |
| `state/done.log` | Daftar task yang sudah dijalankan |

## Operasional di server

```bash
systemctl list-timers ocsaeon-runner.timer      # cek jadwal
journalctl -u ocsaeon-runner.service -n 50      # log runner
sudo systemctl start ocsaeon-runner.service     # paksa jalan sekarang
```

Matikan otomatisasi (rollback):

```bash
sudo systemctl disable --now ocsaeon-runner.timer
```
