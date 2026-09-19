/* Local Oregon light-pollution comparison viewer (no backend required beyond static files). */
(() => {
  const MANIFEST_URL = "../output/oregon/viewer_data/manifest.json";
  const DATA = "../output/oregon/viewer_data/";

  const els = {
    topErrors: document.getElementById("topErrors"),
    candidate: document.getElementById("candidate"),
    layer: document.getElementById("layer"),
    mode: document.getElementById("mode"),
    probe: document.getElementById("probe"),
    metrics: document.getElementById("metrics"),
    stage: document.getElementById("stage"),
    leftCanvas: document.getElementById("leftCanvas"),
    rightCanvas: document.getElementById("rightCanvas"),
    leftTag: document.getElementById("leftTag"),
    rightTag: document.getElementById("rightTag"),
    swipeHandle: document.getElementById("swipeHandle"),
    status: document.getElementById("status"),
  };

  let manifest = null;
  let grid = null;
  let originalF32 = null;
  let candidateF32 = null;
  let shape = [0, 0];
  let vmin = 18, vmax = 22, emax = 0.3;

  const view = { x: 0, y: 0, scale: 1, dragging: false, lastX: 0, lastY: 0 };
  let swipePct = 0.5;
  let hierarchyLeaves = null;

  async function loadManifest() {
    const res = await fetch(MANIFEST_URL);
    if (!res.ok) throw new Error("manifest.json not found. Run: python3 -m light_pollution run-oregon");
    manifest = await res.json();
    grid = manifest.grid;
    vmin = manifest.vmin;
    vmax = manifest.vmax;
    emax = manifest.error_emax || 0.3;
    els.candidate.innerHTML = "";
    for (const c of manifest.candidates) {
      const opt = document.createElement("option");
      opt.value = c.id;
      opt.textContent = `${c.label || c.id}  | MiB=${c.global_mib != null ? Number(c.global_mib).toFixed(2) : "—"} | MAE=${fmt(c.mae)}`;
      els.candidate.appendChild(opt);
    }
    originalF32 = await loadF32("original");
    shape = [grid.height, grid.width];
    await selectCandidate(manifest.candidates[0].id);
    fitView();
    render();
    els.status.textContent = `Loaded ${manifest.candidates.length} candidates · source ${manifest.provenance?.source_name || ""}`;
  }

  async function loadF32(name) {
    const metaRes = await fetch(DATA + name + ".meta.json");
    const meta = await metaRes.json();
    const buf = await fetch(DATA + meta.f32).then((r) => r.arrayBuffer());
    const arr = new Float32Array(buf);
    return { arr, meta };
  }

  async function selectCandidate(id) {
    candidateF32 = await loadF32(id);
    const c = manifest.candidates.find((x) => x.id === id);
    els.metrics.innerHTML = renderMetrics(c);
    els.rightTag.textContent = id;
    renderTopErrors(c);
    hierarchyLeaves = null;
    if (id.startsWith("hierarchical_adaptive_")) {
      fetch("../output/oregon/candidates/" + id + "_overlay.json")
        .then((r) => r.ok ? r.json() : null)
        .then((j) => { hierarchyLeaves = j && j.leaves; render(); })
        .catch(() => {});
    }
    render();
  }

  function renderTopErrors(c) {
    if (!c || !c.top_errors || !c.top_errors.length) {
      els.topErrors.textContent = "No top-error table for this candidate";
      return;
    }
    let html = "<table style='width:100%;font-size:0.7rem;border-collapse:collapse'>";
    html += "<tr><th>#</th><th>Lon</th><th>Lat</th><th>Orig</th><th>Cand</th><th>|err|</th><th>Band</th></tr>";
    for (const r of c.top_errors.slice(0, 20)) {
      const ch = r.band_changed ? "⚠" : "";
      html += `<tr data-lon="${r.lon}" data-lat="${r.lat}" style="cursor:pointer;border-top:1px solid #30363d">
        <td>${r.rank}</td><td>${Number(r.lon).toFixed(3)}</td><td>${Number(r.lat).toFixed(3)}</td>
        <td>${Number(r.original).toFixed(3)}</td><td>${Number(r.candidate).toFixed(3)}</td>
        <td>${Number(r.abs_error).toFixed(3)}</td>
        <td>${r.original_band||"?"}→${r.candidate_band||"?"} ${ch}</td></tr>`;
    }
    html += "</table>";
    els.topErrors.innerHTML = html;
    els.topErrors.querySelectorAll("tr[data-lon]").forEach((tr) => {
      tr.addEventListener("click", () => centerOnLonLat(+tr.dataset.lon, +tr.dataset.lat));
    });
  }

  function centerOnLonLat(lon, lat) {
    if (!grid) return;
    const col = Math.floor((lon - grid.origin_lon) / grid.pixel_width);
    const row = Math.floor((grid.origin_lat - lat) / Math.abs(grid.pixel_height));
    const wrap = document.querySelector(".stage-wrap");
    const cx = wrap.clientWidth / (els.mode.value === "swipe" ? 1 : 2) / 2;
    const cy = wrap.clientHeight / 2;
    view.x = cx - col * view.scale;
    view.y = cy - row * view.scale;
    applyTransform();
    els.probe.innerHTML = `<dl><dt>Centered</dt><dd>${lon.toFixed(4)}, ${lat.toFixed(4)}</dd>
      <dt>Row,Col</dt><dd>${row}, ${col}</dd></dl>`;
  }

  function renderMetrics(c) {
    if (!c) return "";
    const g = c.global_size || {};
    const mib = c.global_mib != null ? Number(c.global_mib).toFixed(2) : (g.total_mib != null ? Number(g.total_mib).toFixed(2) : "—");
    const rel = c.global_reliability || g.reliability || g.kind || "";
    const warn = (manifest && manifest.budget_guarantee_warning) ? `<p class="hint" style="color:#f0883e">${manifest.budget_guarantee_warning}</p>` : "";
    return warn + `<dl>
      <dt>Label</dt><dd style="grid-column:1/-1">${c.label || c.id}</dd>
      <dt>Family</dt><dd>${c.family}</dd>
      <dt>Storage/Quant</dt><dd>${c.storage || c.quantization || "—"}</dd>
      <dt>Budget</dt><dd>${c.budget ?? "—"}</dd>
      <dt>Policy</dt><dd>${c.policy || "—"}</dd>
      <dt>Cap °</dt><dd>${c.cap_deg || "—"}</dd>
      <dt>MAE</dt><dd>${fmt(c.mae)}</dd>
      <dt>P50 / P95 / P99</dt><dd>${fmt(c.p50_ae)} / ${fmt(c.p95_ae)} / ${fmt(c.p99_ae)}</dd>
      <dt>max AE</dt><dd>${fmt(c.max_ae)}</dd>
      <dt>% cells >0.05/0.10/0.20</dt><dd>${fmt(c.exceed_0_05_pct)} / ${fmt(c.exceed_0_10_pct)} / ${fmt(c.exceed_0_20_pct)}</dd>
      <dt>Band agree %</dt><dd>${fmt(c.band_agree_pct)}</dd>
      <dt>Global MiB</dt><dd>${mib}</dd>
      <dt>Reliability</dt><dd style="grid-column:1/-1">${rel}</dd>
      <dt>Meets budget?</dt><dd>${c.meets_configured_budget === false ? "NO" : (c.meets_configured_budget ?? "n/a")}</dd>
      <dt>Viol leaf% / cell%</dt><dd>${fmt(c.viol_leaf_pct)} / ${fmt(c.viol_cell_pct)}</dd>
    </dl>`;
  }

  function fmt(v) {
    if (v == null || Number.isNaN(v)) return "—";
    return typeof v === "number" ? v.toFixed(4) : String(v);
  }

  function isNodata(v) {
    return !Number.isFinite(v) || Math.abs(v) >= 1e30;
  }

  function magColor(v) {
    if (isNodata(v)) return [40, 40, 40, 255];
    let t = (v - vmin) / Math.max(vmax - vmin, 1e-6);
    t = Math.min(1, Math.max(0, t));
    // low mag (polluted) yellow → high mag navy
    const r = 255 * (1 - t) + 10 * t;
    const g = 220 * (1 - t) + 20 * t;
    const b = 50 * (1 - t) + 80 * t;
    return [r, g, b, 255];
  }

  function errColor(err, signed) {
    if (signed) {
      const t = Math.max(-1, Math.min(1, err / emax));
      if (t >= 0) return [0, 0, 255 * t, 255];
      return [255 * (-t), 0, 0, 255];
    }
    const t = Math.min(1, Math.abs(err) / emax);
    return [255 * t, 255 * (1 - t), 40, 255];
  }

  function drawRaster(canvas, mode, which) {
    const h = shape[0], w = shape[1];
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    const img = ctx.createImageData(w, h);
    const o = originalF32.arr;
    const c = candidateF32.arr;
    for (let i = 0; i < w * h; i++) {
      let col;
      if (mode === "original" || (mode === "value" && which === "left")) {
        col = magColor(o[i]);
      } else if (mode === "value" && which === "right") {
        col = magColor(c[i]);
      } else if (mode === "signed") {
        if (isNodata(o[i]) || isNodata(c[i])) col = [40, 40, 40, 255];
        else col = errColor(c[i] - o[i], true);
      } else if (mode === "abs") {
        if (isNodata(o[i]) || isNodata(c[i])) col = [40, 40, 40, 255];
        else col = errColor(Math.abs(c[i] - o[i]), false);
      } else {
        col = magColor(which === "left" ? o[i] : c[i]);
      }
      const p = i * 4;
      img.data[p] = col[0];
      img.data[p + 1] = col[1];
      img.data[p + 2] = col[2];
      img.data[p + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  }

  function render() {
    if (!originalF32 || !candidateF32) return;
    const layer = els.layer.value;
    const mode = els.mode.value;
    els.stage.classList.toggle("swipe", mode === "swipe");

    if (layer === "signed" || layer === "abs") {
      drawRaster(els.leftCanvas, layer, "left");
      drawRaster(els.rightCanvas, layer, "right");
      els.leftTag.textContent = layer === "signed" ? "Signed error" : "Abs error";
      els.rightTag.textContent = els.candidate.value;
    } else {
      drawRaster(els.leftCanvas, "value", "left");
      drawRaster(els.rightCanvas, "value", "right");
      els.leftTag.textContent = "Original";
      els.rightTag.textContent = els.candidate.value;
    }
    applyTransform();
    if (mode === "swipe") updateSwipe();
  }

  function applyTransform() {
    const t = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`;
    els.leftCanvas.style.transform = t;
    els.rightCanvas.style.transform = t;
    drawHierarchyOverlay();
  }

  function drawHierarchyOverlay() {
    const cb = document.getElementById("hierarchyOverlay");
    let ov = document.getElementById("hierCanvas");
    if (!cb || !cb.checked || !hierarchyLeaves || !grid) {
      if (ov) ov.style.display = "none";
      return;
    }
    if (!ov) {
      ov = document.createElement("canvas");
      ov.id = "hierCanvas";
      ov.style.position = "absolute";
      ov.style.left = "0";
      ov.style.top = "0";
      ov.style.pointerEvents = "none";
      ov.style.imageRendering = "pixelated";
      document.querySelector(".stage-wrap").appendChild(ov);
    }
    ov.style.display = "block";
    ov.width = shape[1];
    ov.height = shape[0];
    ov.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`;
    ov.style.transformOrigin = "0 0";
    const ctx = ov.getContext("2d");
    ctx.clearRect(0, 0, ov.width, ov.height);
    const ox = grid.origin_lon; // actually need crop global offset from meta - use grid of oregon
    // leaves store global cell coords; oregon grid starts at crop origin
    // approximate: convert global cell to local using known oregon window from grid size
    // Prefer: leaf coords relative — pipeline stores global_c0/r0; Oregon crop xoff=6600 yoff=3360
    const xoff = 6600, yoff = 3360;
    for (const L of hierarchyLeaves) {
      const c = L.global_c0 - xoff;
      const r = L.global_r0 - yoff;
      if (c + L.w < 0 || r + L.h < 0 || c >= shape[1] || r >= shape[0]) continue;
      ctx.strokeStyle = L.budget_violation ? "rgba(255,80,80,0.9)" : "rgba(88,166,255,0.55)";
      ctx.lineWidth = 1;
      ctx.strokeRect(c + 0.5, r + 0.5, L.w, L.h);
    }
  }

  function fitView() {
    const wrap = document.querySelector(".stage-wrap");
    const w = wrap.clientWidth / (els.mode.value === "swipe" ? 1 : 2);
    const h = wrap.clientHeight;
    const sx = w / shape[1];
    const sy = h / shape[0];
    view.scale = Math.min(sx, sy) * 0.95;
    view.x = 10;
    view.y = 10;
  }

  function updateSwipe() {
    const wrap = els.stage;
    const rect = wrap.getBoundingClientRect();
    const x = rect.width * swipePct;
    els.swipeHandle.style.left = `${x}px`;
    // clip right panel? For simplicity show both stacked with handle only in swipe mode
  }

  function canvasToLonLat(canvas, clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    // account for CSS transform approx using view
    const x = (clientX - rect.left) / view.scale;
    const y = (clientY - rect.top) / view.scale;
    // rect already includes transform for hit testing — better use offset relative to canvas element layout
    const elRect = canvas.getBoundingClientRect();
    const px = (clientX - elRect.left) / (elRect.width / shape[1]);
    const py = (clientY - elRect.top) / (elRect.height / shape[0]);
    const col = Math.floor(px);
    const row = Math.floor(py);
    if (row < 0 || col < 0 || row >= shape[0] || col >= shape[1]) return null;
    const lon = grid.origin_lon + (col + 0.5) * grid.pixel_width;
    const lat = grid.origin_lat + (row + 0.5) * grid.pixel_height;
    return { row, col, lon, lat };
  }

  function probeAt(ev, canvas) {
    const loc = canvasToLonLat(canvas, ev.clientX, ev.clientY);
    if (!loc) {
      els.probe.textContent = "Outside raster";
      return;
    }
    const i = loc.row * shape[1] + loc.col;
    const o = originalF32.arr[i];
    const c = candidateF32.arr[i];
    const oOk = !isNodata(o);
    const cOk = !isNodata(c);
    const err = oOk && cOk ? c - o : null;
    els.probe.innerHTML = `<dl>
      <dt>Lon</dt><dd>${loc.lon.toFixed(5)}</dd>
      <dt>Lat</dt><dd>${loc.lat.toFixed(5)}</dd>
      <dt>Row, Col</dt><dd>${loc.row}, ${loc.col}</dd>
      <dt>Original</dt><dd>${oOk ? o.toFixed(4) : "NoData"}</dd>
      <dt>Candidate</dt><dd>${cOk ? c.toFixed(4) : "NoData"}</dd>
      <dt>Signed err</dt><dd>${err == null ? "—" : err.toFixed(4)}</dd>
      <dt>Abs err</dt><dd>${err == null ? "—" : Math.abs(err).toFixed(4)}</dd>
    </dl>`;
  }

  // events
  els.candidate.addEventListener("change", () => selectCandidate(els.candidate.value));
  els.layer.addEventListener("change", render);
  els.mode.addEventListener("change", () => { fitView(); render(); });

  const wrap = document.querySelector(".stage-wrap");
  wrap.addEventListener("mousedown", (e) => {
    view.dragging = true;
    view.lastX = e.clientX;
    view.lastY = e.clientY;
  });
  window.addEventListener("mouseup", () => { view.dragging = false; });
  window.addEventListener("mousemove", (e) => {
    if (!view.dragging) return;
    view.x += e.clientX - view.lastX;
    view.y += e.clientY - view.lastY;
    view.lastX = e.clientX;
    view.lastY = e.clientY;
    applyTransform();
  });
  wrap.addEventListener("wheel", (e) => {
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.1 : 0.9;
    view.scale = Math.min(64, Math.max(0.05, view.scale * factor));
    applyTransform();
  }, { passive: false });

  els.leftCanvas.addEventListener("mousemove", (e) => probeAt(e, els.leftCanvas));
  els.rightCanvas.addEventListener("mousemove", (e) => probeAt(e, els.rightCanvas));

  document.getElementById("fit").addEventListener("click", () => { fitView(); applyTransform(); });
  const hov = document.getElementById("hierarchyOverlay");
  if (hov) hov.addEventListener("change", () => applyTransform());
  const gw = document.getElementById("gotoWorst");
  if (gw) gw.addEventListener("click", () => {
    const c = manifest.candidates.find((x) => x.id === els.candidate.value);
    if (c && c.top_errors && c.top_errors[0]) {
      centerOnLonLat(c.top_errors[0].lon, c.top_errors[0].lat);
    }
  });

  loadManifest().catch((err) => {
    els.status.innerHTML = `<span class="error">${err.message}</span>`;
    console.error(err);
  });
})();
