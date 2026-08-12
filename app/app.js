const channel = document.body.dataset.channel;
const needsGeo = channel === 'mobile';
const $ = id => document.getElementById(id);

function feedback(kind, text) { const el = $('feedback'); el.className = 'feedback ' + kind; el.textContent = text; }
function atualizarRelogio() { const now = new Date(); $('clock').textContent = now.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' }); $('date').textContent = now.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' }); }

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
    if (result.last) { feedback('ok', result.last.message || 'Batida registrada.'); $('matricula').value = ''; $('pin').value = ''; $('matricula').focus(); }
    else if (result.offline) { feedback('warn', 'Sem conexão. Batida salva neste aparelho.'); $('matricula').value = ''; $('pin').value = ''; $('matricula').focus(); }
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
$('punch').addEventListener('click', punch);
const syncButton = $('sync'); if (syncButton) syncButton.addEventListener('click', syncPending);
if (channel === 'quiosque') {
  $('matricula').addEventListener('keydown', event => {
    if (event.key === 'Enter') { event.preventDefault(); $('pin').focus(); }
  });
  $('pin').addEventListener('keydown', event => {
    if (event.key === 'Enter') { event.preventDefault(); punch(); }
  });
}
setInterval(atualizarRelogio, 1000); atualizarRelogio();
(async () => { try { if (navigator.storage && navigator.storage.persist) await navigator.storage.persist(); } catch (_) {} await status(); await autoSync(); if (channel === 'quiosque') { setInterval(autoSync, 30000); setTimeout(() => $('matricula').focus(), 0); } })();
