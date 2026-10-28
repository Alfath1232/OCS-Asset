(function () {
  "use strict";
  const $ = id => document.getElementById(id);
  const esc = OCS.esc;
  let rows = [];
  const selected = new Set();
  let logoBlack = "";

  fetch("../shared/aeon-logo-black.svg").then(r => r.text()).then(t => { logoBlack = t; render(); });

  function qrSvg(text) {
    const q = qrcode(0, "M");
    q.addData(text);
    q.make();
    return q.createSvgTag({ cellSize: 1, margin: 0, scalable: true });
  }

  function code128Svg(text) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    JsBarcode(svg, text, { format: "CODE128", displayValue: false, margin: 0, height: 60, width: 2 });
    svg.setAttribute("preserveAspectRatio", "none");
    const w = svg.getAttribute("width"), h = svg.getAttribute("height");
    svg.setAttribute("viewBox", "0 0 " + parseFloat(w) + " " + parseFloat(h));
    svg.removeAttribute("width"); svg.removeAttribute("height");
    return svg.outerHTML;
  }

  function logoTag() {
    return logoBlack
      ? logoBlack.replace(/<\?xml[^>]*>/, "").replace(/<!--[\s\S]*?-->/g, "")
          .replace(/width="200" height="59.886429"/, 'class="logo" viewBox="0 0 200 59.886429" preserveAspectRatio="xMinYMid meet"')
      : '<b class="logo">AEON</b>';
  }

  function labelHtml(r, code) {
    const id = r.assetId;
    if (code === "code128") {
      return '<div class="label code128">' +
        '<div class="top">' + logoTag() + '<span class="host">' + esc(r.name) + '</span></div>' +
        '<div class="bc">' + code128Svg(id) + '</div>' +
        '<div class="aid">' + esc(id) + '</div>' +
        '</div>';
    }
    return '<div class="label">' +
      '<div class="qr">' + qrSvg(id) + '</div>' +
      '<div class="txt">' + logoTag() +
      '<span class="aid">' + esc(id) + '</span>' +
      '<span class="host">' + esc(r.name) + '</span>' +
      '<span class="sn">SN ' + esc(r.serial || "-") + '</span>' +
      '</div></div>';
  }

  function labelsMarkup() {
    const fmt = $("f-format").value, code = $("f-code").value;
    const list = rows.filter(r => selected.has(r.id) && r.assetId);
    if (!list.length) return "";
    const items = list.map(r => labelHtml(r, code));
    if (fmt === "a4") {
      let html = '<div class="f-a4">';
      for (let i = 0; i < items.length; i += 24) html += '<div class="sheet">' + items.slice(i, i + 24).join("") + "</div>";
      return html + "</div>";
    }
    return '<div class="f-roll"><div class="roll">' + items.join("") + "</div></div>";
  }

  function filtered() {
    const q = $("q").value.trim().toLowerCase();
    const lok = $("f-lokasi").value;
    return rows.filter(r =>
      (!lok || r.lokasi === lok) &&
      (!q || [r.assetId, r.name, r.serial, r.pic, r.area].join(" ").toLowerCase().includes(q)));
  }

  function render() {
    const list = filtered();
    $("rows").innerHTML = list.map(r =>
      '<tr class="' + (selected.has(r.id) ? "sel" : "") + '">' +
      '<td><input type="checkbox" data-id="' + r.id + '"' + (selected.has(r.id) ? " checked" : "") + (r.assetId ? "" : " disabled") + ' aria-label="Pilih ' + esc(r.name) + '"></td>' +
      (r.assetId ? '<td class="id">' + esc(r.assetId) + "</td>" : '<td class="empty">belum ada</td>') +
      "<td>" + esc(r.name) + "</td><td>" + esc(r.serial) + "</td><td>" + esc(r.lokasi || "–") + "</td><td>" + esc(r.area || "–") + "</td><td>" + esc(r.pic || "–") + "</td></tr>"
    ).join("") || '<tr><td colspan="7" class="empty">Tidak ada aset yang cocok.</td></tr>';
    const withId = list.filter(r => r.assetId);
    $("all").checked = withId.length > 0 && withId.every(r => selected.has(r.id));
    $("count").textContent = list.length + " aset tampil, " + selected.size + " dipilih";
    const n = rows.filter(r => selected.has(r.id) && r.assetId).length;
    $("print").disabled = n === 0;
    $("print").textContent = "Cetak " + n + " label";
    const markup = labelsMarkup();
    $("preview").innerHTML = markup || '<p class="count" style="margin:0">Belum ada aset yang dipilih.</p>';
    $("page-size").textContent = $("f-format").value === "a4"
      ? "@page { size: A4; margin: 0; }"
      : "@page { size: 50mm 25mm; margin: 0; }";
  }

  function wire() {
    ["q", "f-lokasi", "f-format", "f-code"].forEach(id => $(id).addEventListener("input", render));
    $("rows").addEventListener("change", e => {
      const id = Number(e.target.dataset.id);
      if (!id) return;
      if (e.target.checked) selected.add(id); else selected.delete(id);
      render();
    });
    $("all").addEventListener("change", e => {
      filtered().filter(r => r.assetId).forEach(r => e.target.checked ? selected.add(r.id) : selected.delete(r.id));
      render();
    });
    $("print").addEventListener("click", () => {
      $("print-area").innerHTML = labelsMarkup();
      window.print();
    });
  }

  OCS.guard(async () => {
    wire();
    try {
      const all = await OCS.loadAll();
      rows = all.rows;
      const lokasi = (all.defs.byName["Lokasi"] || { options: [] }).options.map(o => o.text);
      $("f-lokasi").innerHTML = '<option value="">Semua lokasi</option>' + lokasi.map(l => "<option>" + esc(l) + "</option>").join("");
      render();
    } catch (e) {
      $("err").textContent = e.message; $("err").hidden = false;
      $("count").textContent = "";
    }
  });
})();
