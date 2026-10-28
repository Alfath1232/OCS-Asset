/* ocs.js — akses API OCS 3 untuk halaman AEON (label & stocktake).
 * Memakai login yang sama dengan console OCS: token di localStorage["token_authentication"].
 * API di origin yang sama: /api/ (nginx meneruskan ke backend Django).
 */
(function (global) {
  "use strict";
  const API = "/api/";
  const TOKEN_KEY = "token_authentication";
  const SLUG = "inventory_base.inventorybase";

  function token() {
    try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; }
  }
  function setToken(t) {
    try {
      if (t) {
        localStorage.setItem(TOKEN_KEY, t);
        localStorage.setItem("authenticated", "true");
      } else {
        localStorage.removeItem(TOKEN_KEY);
        localStorage.setItem("authenticated", "false");
      }
    } catch (e) { /* storage diblok: login berlaku selama halaman terbuka */ }
    memToken = t;
  }
  let memToken = null;

  async function req(method, path, body) {
    const t = token() || memToken;
    const url = /^https?:/.test(path) ? path : API + path.replace(/^\//, "");
    const res = await fetch(url, {
      method,
      headers: Object.assign(
        { "Accept": "application/json" },
        body !== undefined ? { "Content-Type": "application/json" } : {},
        t ? { "Authorization": "Token " + t } : {}
      ),
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (res.status === 401) {
      const err = new Error("Sesi login berakhir. Silakan masuk lagi.");
      err.status = 401;
      throw err;
    }
    if (!res.ok) {
      let detail = "";
      try { detail = JSON.stringify(await res.json()); } catch (e) { /* bukan JSON */ }
      const err = new Error("Permintaan ke server gagal (" + res.status + ") " + detail);
      err.status = res.status;
      throw err;
    }
    return res.status === 204 ? null : res.json();
  }

  async function login(username, password) {
    const r = await fetch(API + "api-auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    if (!r.ok) throw new Error("Username atau password salah.");
    const d = await r.json();
    if (!d.token) throw new Error("Server tidak memberi token login.");
    setToken(d.token);
    return me();
  }

  async function logout() {
    try { await req("POST", "api-auth/token/logout"); } catch (e) { /* abaikan */ }
    setToken(null);
  }

  async function me() { return req("GET", "myaccount/"); }

  /** Semua aset (mengikuti paginasi bila ada). */
  async function assets() {
    let out = [];
    let page = await req("GET", "asset/bases/?limit=500");
    if (Array.isArray(page)) return page;
    out = out.concat(page.results || []);
    while (page.next) {
      page = await req("GET", page.next.replace(/^https?:\/\/[^/]+/, ""));
      out = out.concat(page.results || []);
    }
    return out;
  }

  /** Definisi custom field aset: {byName, byId} */
  async function fields() {
    const list = await req("GET", "accountinfo/config/?expand=accountinfo_values&datatarget=ASSET");
    const arr = Array.isArray(list) ? list : (list.results || []);
    const byName = {}, byId = {};
    arr.forEach(f => {
      const values = (f.accountinfo_values || []).map(v => (typeof v === "object" ? { value: v.id, text: v.value } : v));
      const item = { id: f.id, name: f.name, type: f.datatype, options: values };
      byName[f.name] = item; byId[String(f.id)] = item;
    });
    return { byName, byId };
  }

  /** Data custom field per aset: Map(assetId -> {id, accountdata}) */
  async function accountData() {
    const list = await req("GET", "accountinfo/data/?object_slug=" + encodeURIComponent(SLUG));
    const arr = Array.isArray(list) ? list : (list.results || []);
    const map = new Map();
    arr.forEach(d => map.set(Number(d.object_id), { id: d.id, accountdata: d.accountdata || {} }));
    return map;
  }

  /** Simpan seluruh accountdata satu aset (buat baris baru bila belum ada). */
  async function saveAccountData(assetId, existing, accountdata) {
    if (existing && existing.id) {
      return req("PATCH", "accountinfo/data/" + existing.id + "/", { accountdata });
    }
    return req("POST", "accountinfo/data/", { object_slug: SLUG, object_id: assetId, accountdata });
  }

  /** Ambil teks nilai custom field (TEXT -> string, SELECT -> text, CHECKBOX -> gabungan). */
  function text(fieldsDef, accountdata, name) {
    const f = fieldsDef.byName[name];
    if (!f || !accountdata) return "";
    const v = accountdata[String(f.id)];
    if (v === null || v === undefined) return "";
    if (typeof v === "object" && !Array.isArray(v)) return v.text || "";
    if (Array.isArray(v)) {
      return v.map(id => (f.options.find(o => String(o.value) === String(id)) || {}).text || id).join(", ");
    }
    return String(v);
  }

  /** Set nilai custom field berdasar nama + teks (SELECT dicari pilihannya). */
  function setValue(fieldsDef, accountdata, name, value) {
    const f = fieldsDef.byName[name];
    if (!f) return accountdata;
    const key = String(f.id);
    if (f.type === "SELECT") {
      const opt = f.options.find(o => o.text === value);
      accountdata[key] = opt ? { value: opt.value, text: opt.text } : null;
    } else {
      accountdata[key] = value == null ? "" : String(value);
    }
    return accountdata;
  }

  /** Muat semua: aset + definisi field + nilai, digabung jadi daftar rapi. */
  async function loadAll() {
    const [list, defs, data] = await Promise.all([assets(), fields(), accountData()]);
    const rows = list.map(a => {
      const d = data.get(Number(a.id)) || null;
      const ad = d ? d.accountdata : {};
      return {
        id: a.id, name: a.name, serial: a.serial, os: [a.osname, a.osversion].filter(Boolean).join(" "),
        ip: a.srcip, uuid: a.uuid, lastUpdate: a.last_update,
        data: d, accountdata: ad,
        assetId: text(defs, ad, "Asset ID"),
        lokasi: text(defs, ad, "Lokasi"),
        area: text(defs, ad, "Area"),
        pic: text(defs, ad, "PIC"),
        status: text(defs, ad, "Status aset"),
        stLast: text(defs, ad, "Stocktake terakhir"),
        stResult: text(defs, ad, "Hasil stocktake"),
        stBy: text(defs, ad, "Stocktake oleh"),
      };
    });
    rows.sort((x, y) => (x.assetId || "~").localeCompare(y.assetId || "~") || String(x.name).localeCompare(String(y.name)));
    return { rows, defs };
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  /** Pasang alur login: panggil onReady(user) setelah login valid. */
  function guard(onReady) {
    const loginBox = document.getElementById("login");
    const app = document.getElementById("app");
    const form = document.getElementById("login-form");
    const msg = document.getElementById("login-msg");
    async function tryStart() {
      try {
        const user = await me();
        loginBox.hidden = true; app.hidden = false;
        const who = document.getElementById("who");
        if (who) who.textContent = user.username || "";
        onReady(user);
      } catch (e) {
        loginBox.hidden = false; app.hidden = true;
        if (e.status && e.status !== 401) { msg.textContent = e.message; msg.hidden = false; }
      }
    }
    form.addEventListener("submit", async ev => {
      ev.preventDefault();
      msg.hidden = true;
      const btn = form.querySelector("button");
      btn.disabled = true;
      try {
        await login(form.username.value.trim(), form.password.value);
        form.password.value = "";
        await tryStart();
      } catch (e) {
        msg.textContent = e.message; msg.hidden = false;
      } finally { btn.disabled = false; }
    });
    const out = document.getElementById("logout");
    if (out) out.addEventListener("click", async ev => { ev.preventDefault(); await logout(); location.reload(); });
    if (token()) tryStart(); else { loginBox.hidden = false; app.hidden = true; }
  }

  global.OCS = { loadAll, saveAccountData, setValue, text, me, login, logout, guard, esc };
})(window);
