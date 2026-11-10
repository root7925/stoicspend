import Foundation

/// FR-11 电脑端工作台 — 网页端（单页 HTML，与手机端同口径）
/// 能力：配对 → 只读仪表盘（月支出/控制比/分类表）+ 明细表格编辑 + CSV/JSON 导入导出
enum WorkbenchWebUI {

    static let html = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Stoic Spend · 工作台</title>
    <style>
      :root {
        --paper: #f5f1e8; --card: #fbf9f4; --ink: #252320; --ash: #8a857a;
        --accent: #8a6f46; --green: #5f8a6f; --line: #e5ded0; --gold: #9a7a33;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { background: var(--paper); color: var(--ink); font-family: ui-sans-serif, -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; padding: 24px; }
      h1 { font-size: 22px; font-weight: 600; letter-spacing: .5px; }
      .serif { font-family: ui-serif, Georgia, "Songti SC", serif; }
      .wrap { max-width: 960px; margin: 0 auto; }
      .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px; margin-bottom: 16px; }
      .muted { color: var(--ash); font-size: 13px; }
      .row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
      .spacer { flex: 1; }
      .stats { display: flex; gap: 16px; flex-wrap: wrap; }
      .stat { flex: 1; min-width: 140px; }
      .stat .num { font-size: 26px; font-weight: 600; font-variant-numeric: tabular-nums; }
      .stat .label { font-size: 12px; color: var(--ash); margin-bottom: 4px; }
      table { width: 100%; border-collapse: collapse; font-size: 14px; }
      th { text-align: left; color: var(--ash); font-weight: 500; font-size: 12px; padding: 8px 6px; border-bottom: 1px solid var(--line); }
      td { padding: 8px 6px; border-bottom: 1px solid var(--line); vertical-align: middle; }
      input, select { font: inherit; color: inherit; background: #fff; border: 1px solid var(--line); border-radius: 6px; padding: 4px 8px; }
      input.amount { width: 96px; text-align: right; font-variant-numeric: tabular-nums; }
      input.note { width: 100%; min-width: 120px; }
      select.nature { width: 110px; } select.category { width: 110px; }
      .tag { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 12px; }
      .tag.chosen { background: rgba(95,138,111,.15); color: var(--green); }
      .tag.impulse { background: rgba(154,122,51,.15); color: var(--gold); }
      .tag.none { background: rgba(0,0,0,.06); color: var(--ash); }
      button { font: inherit; cursor: pointer; border: none; border-radius: 8px; padding: 8px 16px; background: var(--accent); color: #fff; }
      button.ghost { background: transparent; color: var(--accent); border: 1px solid var(--accent); }
      button.mini { padding: 4px 10px; font-size: 12px; border-radius: 6px; }
      button:disabled { opacity: .4; cursor: default; }
      .catbar { height: 8px; border-radius: 4px; background: var(--accent); opacity: .85; }
      #pair { max-width: 360px; margin: 80px auto; text-align: center; }
      #pair input { font-size: 32px; text-align: center; letter-spacing: 12px; width: 180px; }
      .error { color: #a05f6d; font-size: 13px; margin-top: 8px; min-height: 18px; }
      .monthnav button { background: transparent; color: var(--ink); border: 1px solid var(--line); padding: 4px 12px; }
      .toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); background: var(--ink); color: var(--paper); padding: 8px 20px; border-radius: 999px; font-size: 13px; opacity: 0; transition: opacity .3s; pointer-events: none; }
      .toast.show { opacity: 1; }
      .monthlabel { font-size: 16px; font-weight: 600; min-width: 96px; text-align: center; }
      a { color: var(--accent); }
    </style>
    </head>
    <body>
    <div class="wrap">

      <div id="pair">
        <div class="card">
          <h1 class="serif" style="margin-bottom:8px">Stoic Spend 工作台</h1>
          <p class="muted" style="margin-bottom:20px">输入手机屏幕上的 4 位配对码</p>
          <input id="code" maxlength="4" inputmode="numeric" placeholder="····">
          <div class="error" id="pairError"></div>
          <button onclick="pair()">配对</button>
        </div>
      </div>

      <div id="main" style="display:none">
        <div class="row" style="margin-bottom:16px">
          <h1 class="serif">Stoic Spend 工作台</h1>
          <div class="spacer"></div>
          <a id="exportCsv" href="#" download>导出 CSV</a>
          <a id="exportJson" href="#" download>导出 JSON</a>
          <button class="ghost mini" onclick="undoImport()">撤销上次导入</button>
          <button class="ghost mini" onclick="logout()">断开</button>
        </div>

        <div class="card">
          <div class="row" style="margin-bottom:12px">
            <div class="monthnav">
              <button onclick="shiftMonth(-1)">‹</button>
              <span class="monthlabel" id="monthLabel"></span>
              <button onclick="shiftMonth(1)">›</button>
            </div>
            <div class="spacer"></div>
            <label class="muted" style="cursor:pointer">导入 CSV / JSON <input type="file" id="importFile" accept=".csv,.json,text/csv,application/json" style="display:none" onchange="onImportFile(this)"></label>
          </div>

          <div class="stats">
            <div class="stat"><div class="label">本月支出</div><div class="num" id="statTotal">–</div></div>
            <div class="stat"><div class="label">可控支出</div><div class="num" id="statCtrl" style="color:var(--green)">–</div></div>
            <div class="stat"><div class="label">控制比</div><div class="num" id="statRatio">–</div></div>
            <div class="stat"><div class="label">笔数</div><div class="num" id="statCount">–</div></div>
          </div>
        </div>

        <div class="card">
          <div class="muted" style="margin-bottom:8px">分类支出（本月）</div>
          <table id="catTable"><tbody></tbody></table>
        </div>

        <div class="card">
          <div class="row" style="margin-bottom:8px">
            <div class="muted">明细（可直接编辑，保存即写回手机）</div>
            <div class="spacer"></div>
            <span class="muted" id="previewBox" style="display:none"></span>
          </div>
          <table id="expTable">
            <thead><tr><th>日期</th><th>金额</th><th>性质</th><th>分类</th><th>备注</th><th></th></tr></thead>
            <tbody></tbody>
          </table>
        </div>
      </div>
    </div>
    <div class="toast" id="toast"></div>

    <script>
    let token = localStorage.getItem('token') || '';
    let meta = null, month = null, expenses = [];
    const $ = id => document.getElementById(id);

    function toast(msg) { const t = $('toast'); t.textContent = msg; t.classList.add('show'); setTimeout(() => t.classList.remove('show'), 2500); }
    function authedFetch(url, opts = {}) {
      opts.headers = Object.assign({}, opts.headers, { 'X-Auth-Token': token });
      return fetch(url, opts);
    }
    function monthStr(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0'); }

    async function pair() {
      const code = $('code').value.trim();
      $('pairError').textContent = '';
      const res = await fetch('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code }) });
      if (!res.ok) { $('pairError').textContent = (await res.json().catch(() => ({}))).error || '配对码不正确'; return; }
      token = (await res.json()).token;
      localStorage.setItem('token', token);
      enterMain();
    }

    function logout() { localStorage.removeItem('token'); location.reload(); }

    async function enterMain() {
      const res = await authedFetch('/api/meta');
      if (res.status === 401) { localStorage.removeItem('token'); return; }
      meta = await res.json();
      $('pair').style.display = 'none';
      $('main').style.display = '';
      month = monthStr(new Date());
      refreshExportLinks();
      await loadMonth();
    }

    function refreshExportLinks() {
      $('exportCsv').href = '/api/export/csv?token=' + encodeURIComponent(token);
      $('exportJson').href = '/api/export/json?token=' + encodeURIComponent(token);
    }

    async function shiftMonth(delta) {
      const [y, m] = month.split('-').map(Number);
      const d = new Date(y, m - 1 + delta, 1);
      month = monthStr(d);
      await loadMonth();
    }

    async function loadMonth() {
      const [sumRes, listRes] = await Promise.all([authedFetch('/api/summary?month=' + month), authedFetch('/api/expenses?month=' + month)]);
      if (sumRes.status === 401 || listRes.status === 401) { localStorage.removeItem('token'); location.reload(); return; }
      const sum = await sumRes.json();
      expenses = (await listRes.json()).expenses;
      $('monthLabel').textContent = sum.month;
      $('statTotal').textContent = sum.total.toFixed(2);
      $('statCtrl').textContent = sum.controllable.toFixed(2);
      $('statRatio').textContent = Math.round((sum.controllableRatio || 0) * 100) + '%';
      $('statCount').textContent = sum.count;

      const max = Math.max(...sum.categories.map(c => c.amount), 0.0001);
      $('catTable').tBodies[0].innerHTML = sum.categories.filter(c => c.amount > 0).map(c =>
        '<tr><td style="width:90px">' + c.name + '</td>' +
        '<td><div class="catbar" style="width:' + Math.max(2, c.amount / max * 100) + '%"></div></td>' +
        '<td style="text-align:right;width:100px;font-variant-numeric:tabular-nums">' + c.amount.toFixed(2) + '</td></tr>'
      ).join('') || '<tr><td class="muted">本月暂无支出</td></tr>';

      const natureName = k => (meta.natures.find(n => n.key === k) || {}).name || '';
      const categoryName = k => (meta.categories.find(c => c.key === k) || {}).name || '';
      $('expTable').tBodies[0].innerHTML = expenses.map(e => {
        const natureTag = e.nature ? '<span class="tag ' + e.nature + '">' + natureName(e.nature) + '</span>' : '<span class="tag none">未标记</span>';
        const natureOptions = '<option value="">未标记</option>' + meta.natures.map(n =>
          '<option value="' + n.key + '"' + (e.nature === n.key ? ' selected' : '') + '>' + n.name + '</option>').join('');
        const catOptions = meta.categories.map(c =>
          '<option value="' + c.key + '"' + (e.category === c.key ? ' selected' : '') + '>' + c.name + '</option>').join('');
        return '<tr data-id="' + e.id + '">' +
          '<td style="white-space:nowrap">' + e.date.slice(5, 16).replace('T', ' ') + '</td>' +
          '<td><input class="amount" type="number" step="0.01" min="0" value="' + e.amount + '" onchange="saveRow(this)"></td>' +
          '<td><select class="nature" onchange="saveRow(this)">' + natureOptions + '</select></td>' +
          '<td><select class="category" onchange="saveRow(this)">' + catOptions + '</select></td>' +
          '<td><input class="note" value="' + (e.note || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;') + '" onchange="saveRow(this)"></td>' +
          '<td>' + natureTag + '</td></tr>';
      }).join('') || '<tr><td colspan="6" class="muted">本月暂无支出</td></tr>';
    }

    async function saveRow(input) {
      const tr = input.closest('tr');
      const id = tr.dataset.id;
      const body = {
        amount: parseFloat(tr.querySelector('.amount').value) || 0,
        nature: tr.querySelector('.nature').value || null,
        category: tr.querySelector('.category').value,
        note: tr.querySelector('.note').value,
      };
      const res = await authedFetch('/api/expenses/' + id, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      if (res.ok) { toast('已保存'); loadMonth(); } else { toast((await res.json().catch(() => ({}))).error || '保存失败'); }
    }

    async function onImportFile(input) {
      const file = input.files[0];
      input.value = '';
      if (!file) return;
      const buf = await file.arrayBuffer();
      let binary = ''; const bytes = new Uint8Array(buf);
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      const kind = file.name.toLowerCase().endsWith('.json') ? 'json' : 'csv';
      const res = await authedFetch('/api/import', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ kind, data: btoa(binary) }) });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) { toast(data.error || '解析失败'); return; }
      const modeText = data.mode === 'replace' ? '覆盖现有全部支出' : '仅追加';
      const sample = (data.samples || []).join('；');
      if (confirm('将导入 ' + data.count + ' 条记录（' + modeText + (data.skipped ? '，跳过 ' + data.skipped + ' 行' : '') + '）\\n' + sample + '\\n\\n确认导入？导入前会自动快照，可撤销。')) {
        const cRes = await authedFetch('/api/import/confirm', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ importId: data.importId }) });
        const cData = await cRes.json().catch(() => ({}));
        toast(cRes.ok ? cData.message : (cData.error || '导入失败'));
        loadMonth();
      }
    }

    async function undoImport() {
      if (!confirm('撤销上次导入？当前支出将恢复为导入前快照。')) return;
      const res = await authedFetch('/api/import/undo', { method: 'POST' });
      const data = await res.json().catch(() => ({}));
      toast(res.ok ? data.message : (data.error || '撤销失败'));
      loadMonth();
    }

    if (token) { enterMain(); }
    </script>
    </body>
    </html>
    """
}
