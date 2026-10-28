(function () {
  "use strict";
  const $ = id => document.getElementById(id);
  const esc = OCS.esc;
  const SKEY = "ocsaeon_stocktake";

  let rows = [], defs = null, user = null;
  let sess = null;            // {lokasi, area, petugas, checked: {assetId: hasil}}
  let current = null;         // aset yang sedang ditampilkan
  let scanner = null, scanning = false, busy = false;
  let tab = "todo";

  /* ---------- util ---------- */
  function now() {
    const d = new Date(), p = n => String(n).padStart(2, "0");
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " + p(d.getHours()) + ":" + p(d.getMinutes());
  }
  function toast(text) {
    const t = $("toast"); t.textContent = text; t.classList.add("show");
    clearTimeout(toast._t); toast._t = setTimeout(() => t.classList.remove("show"), 2600);
  }
  function saveSess() { try { sessionStorage.setItem(SKEY, JSON.stringify(sess)); } catch (e) { /* abaikan */ } }
  function loadSess() { try { return JSON.parse(sessionStorage.getItem(SKEY) || "null"); } catch (e) { return null; } }
  function showErr(m) { $("err").textContent = m; $("err").hidden = !m; }

  /* ---------- data ---------- */
  function scope() {
    return rows.filter(r => r.lokasi === sess.lokasi && (!sess.area || r.area === sess.area));
  }
  function find(code) {
    const q = String(code || "").trim().toUpperCase();
    if (!q) return null;
    return rows.find(r => (r.assetId || "").toUpperCase() === q)
      || rows.find(r => (r.name || "").toUpperCase() === q)
      || rows.find(r => (r.serial || "").toUpperCase() === q)
      || null;
  }

  async function record(r, hasil, extra) {
    if (busy) return;
    busy = true;
    try {
      const ad = JSON.parse(JSON.stringify((r.data && r.data.accountdata) || {}));
      OCS.setValue(defs, ad, "Hasil stocktake", hasil);
      OCS.setValue(defs, ad, "Stocktake terakhir", now());
      OCS.setValue(defs, ad, "Stocktake oleh", sess.petugas);
      if (extra && extra.lokasi) OCS.setValue(defs, ad, "Lokasi", extra.lokasi);
      if (extra && extra.area) OCS.setValue(defs, ad, "Area", extra.area);
      const saved = await OCS.saveAccountData(r.id, r.data, ad);
      r.data = { id: saved.id, accountdata: saved.accountdata || ad };
      r.accountdata = r.data.accountdata;
      r.lokasi = OCS.text(defs, r.accountdata, "Lokasi");
      r.area = OCS.text(defs, r.accountdata, "Area");
      r.stResult = hasil; r.stLast = OCS.text(defs, r.accountdata, "Stocktake terakhir"); r.stBy = sess.petugas;
      sess.checked[r.assetId || ("#" + r.id)] = hasil;
      saveSess();
      if (navigator.vibrate) navigator.vibrate(40);
      toast((r.assetId || r.name) + ": " + hasil.toLowerCase());
      if (current === r) showResult(r);
      renderProgress(); renderList();
    } catch (e) {
      if (e.status === 401) { toast("Sesi login berakhir"); setTimeout(() => location.reload(), 1200); }
      else showErr("Gagal menyimpan: " + e.message);
    } finally { busy = false; }
  }

  /* ---------- tampilan ---------- */
  function renderProgress() {
    const list = scope();
    const done = list.filter(r => sess.checked[r.assetId || ("#" + r.id)]).length;
    const extra = Object.keys(sess.checked).length - done;
    $("bar").style.width = list.length ? (done / list.length * 100) + "%" : "0";
    $("progress-text").innerHTML = "<b>" + done + " dari " + list.length + "</b> aset tercatat di sini sudah dicek" +
      (extra > 0 ? ". " + extra + " aset dari tempat lain ikut dicatat." : ".");
  }

  function chip(h) {
    const cls = h === "Sesuai" ? "ok" : h === "Pindah lokasi" ? "move" : "bad";
    return '<span class="chip ' + cls + '">' + esc(h) + "</span>";
  }

  function renderList() {
    $("tab-todo").setAttribute("aria-selected", tab === "todo");
    $("tab-done").setAttribute("aria-selected", tab === "done");
    const key = r => r.assetId || ("#" + r.id);
    let html = "";
    if (tab === "todo") {
      const todo = scope().filter(r => !sess.checked[key(r)]);
      html = todo.map(r =>
        '<li><div class="meta"><b>' + esc(r.assetId || "tanpa Asset ID") + "</b><span>" + esc(r.name) + (r.area ? ", " + esc(r.area) : "") + (r.pic ? ", " + esc(r.pic) : "") + "</span></div>" +
        '<button class="btn" data-missing="' + r.id + '">Tidak ditemukan</button></li>').join("");
      if (!html) html = '<li class="empty">' + (scope().length ? "Semua aset di sini sudah dicek." : "Belum ada aset yang tercatat di tempat ini.") + "</li>";
    } else {
      const done = rows.filter(r => sess.checked[key(r)]);
      html = done.map(r => '<li><div class="meta"><b>' + esc(r.assetId) + "</b><span>" + esc(r.name) + "</span></div>" + chip(sess.checked[key(r)]) + "</li>").join("")
        || '<li class="empty">Belum ada aset yang dicek.</li>';
    }
    $("list").innerHTML = html;
  }

  function showResult(r) {
    current = r;
    const box = $("result");
    box.hidden = false;
    const placeLabel = sess.lokasi + (sess.area ? ", " + sess.area : "");
    const recorded = (r.lokasi || "belum diisi") + (r.area ? ", " + r.area : "");
    const sameLok = r.lokasi === sess.lokasi;
    const areaDiff = sess.area && r.area !== sess.area;
    const checked = sess.checked[r.assetId || ("#" + r.id)];

    let flag = "", actions = "";
    if (checked) {
      flag = '<div class="flag ok">Sudah dicatat pada sesi ini: ' + esc(checked) + ".</div>";
    } else if (!r.lokasi) {
      flag = '<div class="flag warn">Lokasi aset ini belum diisi di OCS.</div>';
    } else if (!sameLok) {
      flag = '<div class="flag warn">Tercatat di ' + esc(recorded) + ", bukan di " + esc(sess.lokasi) + ".</div>";
    } else if (areaDiff) {
      flag = '<div class="flag warn">Tercatat di area ' + esc(r.area || "kosong") + ".</div>";
    }

    if (!sameLok) {
      actions = '<button class="btn primary" data-act="move">Catat pindah ke ' + esc(placeLabel) + "</button>" +
                '<button class="btn" data-act="next">Lewati</button>';
    } else {
      actions = '<button class="btn primary" data-act="ok">' + (areaDiff ? "Sesuai, perbarui area ke " + esc(sess.area) : "Sesuai") + "</button>" +
                '<button class="btn" data-act="next">Lewati</button>';
    }

    box.innerHTML =
      '<div class="aid">' + esc(r.assetId || "tanpa Asset ID") + "</div>" +
      '<div class="host">' + esc(r.name) + "</div>" +
      "<dl>" +
      "<dt>Serial</dt><dd>" + esc(r.serial || "-") + "</dd>" +
      "<dt>Tercatat</dt><dd>" + esc(recorded) + "</dd>" +
      "<dt>PIC</dt><dd>" + esc(r.pic || "-") + "</dd>" +
      "<dt>Status</dt><dd>" + esc(r.status || "-") + "</dd>" +
      "<dt>Cek terakhir</dt><dd>" + esc(r.stLast ? r.stLast + " (" + (r.stResult || "-") + ")" : "belum pernah") + "</dd>" +
      "</dl>" + flag + '<div class="actions">' + actions + "</div>";
    box.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  function notFoundCode(code) {
    current = null;
    const box = $("result");
    box.hidden = false;
    box.innerHTML = '<div class="aid">' + esc(code) + "</div>" +
      '<div class="flag bad">Kode ini tidak ada di OCS. Bisa jadi label salah, atau PC-nya belum terpasang agent.</div>' +
      '<div class="actions"><button class="btn" data-act="next">Tutup</button></div>';
  }

  function lookup(code) {
    const r = find(code);
    if (r) showResult(r); else notFoundCode(code);
  }

  /* ---------- kamera ---------- */
  async function startScan() {
    if (scanning) return stopScan();
    $("scan").classList.add("on");
    $("scan-btn").textContent = "Tutup kamera";
    try {
      if (!scanner) {
        scanner = new Html5Qrcode("reader", {
          formatsToSupport: [Html5QrcodeSupportedFormats.QR_CODE, Html5QrcodeSupportedFormats.CODE_128],
          verbose: false,
        });
      }
      await scanner.start({ facingMode: "environment" }, { fps: 10, qrbox: (w, h) => {
        const s = Math.floor(Math.min(w, h) * 0.7); return { width: s, height: s };
      } }, text => { stopScan(); lookup(text); }, () => {});
      scanning = true;
    } catch (e) {
      $("scan").classList.remove("on");
      $("scan-btn").textContent = "Pindai label";
      showErr("Kamera tidak bisa dibuka: " + (e && e.message ? e.message : e) + ". Izinkan akses kamera di browser, atau ketik Asset ID.");
    }
  }
  async function stopScan() {
    if (scanner && scanning) { try { await scanner.stop(); } catch (e) { /* sudah berhenti */ } }
    scanning = false;
    $("scan").classList.remove("on");
    $("scan-btn").textContent = "Pindai label";
  }

  /* ---------- sesi ---------- */
  function fillSetup() {
    const opts = (name, first) => first + ((defs.byName[name] || { options: [] }).options.map(o => "<option>" + esc(o.text) + "</option>").join(""));
    $("s-lokasi").innerHTML = opts("Lokasi", '<option value="">Pilih lokasi</option>');
    $("s-area").innerHTML = opts("Area", '<option value="">Semua area</option>');
    $("s-petugas").value = (sess && sess.petugas) || user.username || "";
  }
  function enterRun() {
    $("setup").hidden = true; $("run").hidden = false;
    $("place").innerHTML = esc(sess.lokasi) + "<small>" + esc(sess.area || "Semua area") + ", petugas " + esc(sess.petugas) + "</small>";
    $("result").hidden = true;
    renderProgress(); renderList();
  }

  function wire() {
    $("setup-form").addEventListener("submit", e => {
      e.preventDefault();
      const lokasi = $("s-lokasi").value, area = $("s-area").value, petugas = $("s-petugas").value.trim();
      if (!lokasi || !petugas) return;
      if (!sess || sess.lokasi !== lokasi || sess.area !== area) sess = { lokasi, area, petugas, checked: {} };
      sess.petugas = petugas;
      saveSess(); enterRun();
    });
    $("change").addEventListener("click", () => { stopScan(); $("run").hidden = true; $("setup").hidden = false; fillSetup(); });
    $("scan-btn").addEventListener("click", startScan);
    $("manual").addEventListener("submit", e => {
      e.preventDefault();
      const q = $("manual-q").value; if (!q.trim()) return;
      lookup(q); $("manual-q").value = "";
    });
    $("result").addEventListener("click", e => {
      const act = e.target.dataset.act; if (!act) return;
      if (act === "next") { $("result").hidden = true; current = null; return; }
      if (!current) return;
      if (act === "ok") record(current, "Sesuai", sess.area && current.area !== sess.area ? { area: sess.area } : null);
      if (act === "move") record(current, "Pindah lokasi", { lokasi: sess.lokasi, area: sess.area || null });
    });
    document.querySelector(".tabs").addEventListener("click", e => {
      if (!e.target.dataset.tab) return; tab = e.target.dataset.tab; renderList();
    });
    $("list").addEventListener("click", e => {
      const id = Number(e.target.dataset.missing); if (!id) return;
      const r = rows.find(x => x.id === id); if (r) record(r, "Tidak ditemukan");
    });
  }

  OCS.guard(async u => {
    user = u;
    if (!window.isSecureContext) { $("insecure").hidden = false; $("scan-btn").hidden = true; }
    wire();
    try {
      const all = await OCS.loadAll();
      rows = all.rows; defs = all.defs;
      sess = loadSess();
      fillSetup();
      if (sess && sess.lokasi) enterRun();
    } catch (e) { showErr(e.message); }
  });
})();
