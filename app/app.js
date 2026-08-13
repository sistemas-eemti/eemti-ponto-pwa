const channel = document.body.dataset.channel;
const needsGeo = channel === 'mobile';
const $ = id => document.getElementById(id);

function escapeText(value) { const el = document.createElement('span'); el.textContent = value ?? ''; return el.innerHTML; }

let successFeedbackTimer;
function feedback(kind, text) { const el = $('feedback'); el.className = 'feedback ' + kind; el.textContent = text; }
function clearSuccessFeedback() { clearTimeout(successFeedbackTimer); successFeedbackTimer = setTimeout(() => { const el = $('feedback'); if (el.classList.contains('ok') || el.classList.contains('warn')) feedback('', ''); }, 2000); }
function atualizarRelogio() { const now = new Date(); $('clock').textContent = now.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' }); $('date').textContent = now.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' }); }

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  const btn = $('theme-toggle'); if (btn) btn.textContent = theme === 'dark' ? 'Tema claro' : 'Tema escuro';
  try { localStorage.setItem('ponto_tema', theme); } catch (_) {}
}
function toggleTheme() { applyTheme((document.documentElement.getAttribute('data-theme') || 'light') === 'dark' ? 'light' : 'dark'); }
(function () { let t = null; try { t = localStorage.getItem('ponto_tema'); } catch (_) {} applyTheme(t === 'escuro' || t === 'dark' ? 'dark' : 'light'); })();

async function status() {
  const count = await pendingCount(channel);
  const online = navigator.onLine;
  $('network').className = 'network ' + (online ? 'online' : 'offline');
  $('network').textContent = (online ? 'Conectado' : 'Sem conexão') + (count ? ' · ' + count + ' batida(s) pendente(s).' : '');
}

async function queuePunch(matricula, geo) {
  const record = { id: novoId(), channel, matricula, deviceId: await deviceId(channel), capturedAt: new Date().toISOString(), offline: !navigator.onLine };
  if (geo) Object.assign(record, geo);
  await storePut('queue', record);
  return record;
}

async function punch() {
  const matricula = $('matricula').value.trim();
  const pin = $('pin').value.trim();
  if (!matricula || !pin) return feedback('error', 'Preencha matrícula e PIN.');
  $('punch').disabled = true;
  try {
    let geo = null;
    if (needsGeo) {
      feedback('', 'Obtendo localização...');
      const position = await new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 }));
      geo = { latitude: position.coords.latitude, longitude: position.coords.longitude, accuracy: Math.round(position.coords.accuracy || 0) };
    }
    await queuePunch(matricula, geo);
    const result = await syncFor(channel, matricula, { pin, token: await tokenFor(channel, matricula) });
    if (result.last) { const el = $('feedback'); el.className = 'feedback ok'; el.innerHTML = escapeText(result.last.message || 'Batida registrada.') + (result.last.aviso ? '<br><span class="aviso">' + escapeText(result.last.aviso) + '</span>' : ''); $('matricula').value = ''; $('pin').value = ''; $('matricula').focus(); clearSuccessFeedback(); }
    else if (result.offline) { feedback('warn', 'Sem conexão. Batida salva neste aparelho.'); $('matricula').value = ''; $('pin').value = ''; $('matricula').focus(); clearSuccessFeedback(); }
    else feedback('error', result.error || 'Batida pendente.');
  } catch (_) { feedback('error', needsGeo ? 'Não foi possível obter a localização.' : 'Não foi possível registrar a batida.'); }
  $('punch').disabled = false;
  status();
}

async function syncPending() {
  const matricula = $('matricula').value.trim();
  const pin = $('pin').value.trim();
  if (!matricula || !pin) return feedback('error', 'Informe matrícula e PIN para sincronizar.');
  const result = await syncFor(channel, matricula, { pin, token: await tokenFor(channel, matricula) });
  feedback(result.last ? 'ok' : result.offline ? 'warn' : 'error', result.last ? 'Pendências sincronizadas.' : result.offline ? 'Sem conexão.' : result.error || 'Nenhuma pendência.');
  status();
}

async function showHistory() {
  const matricula = $('matricula').value.trim();
  const pin = $('pin').value.trim();
  if (!matricula || !pin) return feedback('error', 'Informe matrícula e PIN para consultar suas marcações.');
  const button = $('history-button');
  button.disabled = true;
  try {
    const result = await punchHistory(matricula, pin, channel);
    const rows = result.rows || [];
    $('history').hidden = false;
    $('history').innerHTML = `<strong>${escapeText(result.name || 'Minhas marcações')}</strong>${rows.map(row => `<div class="history-row"><span>${escapeText(row.captured_at)}</span><span>${escapeText(row.origin || '-')}</span></div>`).join('') || '<p>Nenhuma marcação encontrada.</p>'}`;
    $('pin').value = '';
    feedback('', '');
  } catch (error) { feedback('error', error.message || 'Não foi possível consultar as marcações.'); }
  button.disabled = false;
}

async function autoSync() {
  if (!navigator.onLine) return;
  const rows = await storeAll('queue');
  const mats = [...new Set(rows.filter(x => x.channel === channel).map(x => x.matricula))];
  for (const mat of mats) await syncFor(channel, mat, null);
  status();
}

if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js');
window.addEventListener('online', autoSync);
window.addEventListener('offline', status);
const themeToggle = $('theme-toggle'); if (themeToggle) themeToggle.addEventListener('click', toggleTheme);
$('punch').addEventListener('click', punch);
const syncButton = $('sync'); if (syncButton) syncButton.addEventListener('click', syncPending);
const historyButton = $('history-button'); if (historyButton) historyButton.addEventListener('click', showHistory);
if (channel === 'kiosk') {
  $('matricula').addEventListener('keydown', event => {
    if (event.key === 'Enter') { event.preventDefault(); $('pin').focus(); }
  });
  $('pin').addEventListener('keydown', event => {
    if (event.key === 'Enter') { event.preventDefault(); punch(); }
  });
}
setInterval(atualizarRelogio, 1000); atualizarRelogio();
(async () => { try { if (navigator.storage && navigator.storage.persist) await navigator.storage.persist(); } catch (_) {} await status(); await autoSync(); if (channel === 'kiosk') { setInterval(autoSync, 30000); setTimeout(() => $('matricula').focus(), 0); } })();
