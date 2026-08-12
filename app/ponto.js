function normalizarMatricula(value) {
  const text = String(value || '').trim();
  return /^\d+$/.test(text) ? String(Number(text)) : text;
}

function novoId() {
  return 'L' + Date.now().toString(36) + '-' + crypto.getRandomValues(new Uint32Array(1))[0].toString(36);
}

async function deviceId(channel) {
  const key = 'device:' + channel;
  const saved = await storeGet('meta', key);
  if (saved) return saved.value;
  const value = novoId() + novoId();
  await storePut('meta', { key, value });
  return value;
}

async function tokenFor(channel, matricula) {
  const saved = await storeGet('tokens', channel + ':' + normalizarMatricula(matricula));
  return saved ? saved.token : '';
}

async function saveToken(channel, matricula, token) {
  if (token) await storePut('tokens', { key: channel + ':' + normalizarMatricula(matricula), token });
}

async function api(payload) {
  const response = await fetch(window.PONTO_CONFIG.API_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
  });
  if (!response.ok) throw new Error('Falha de rede.');
  return response.json();
}

async function syncFor(channel, matricula, credential) {
  if (!navigator.onLine) return { offline: true };
  const mat = normalizarMatricula(matricula);
  const rows = (await storeAll('queue')).filter(x => x.channel === channel && normalizarMatricula(x.matricula) === mat)
    .sort((a, b) => a.capturedAt.localeCompare(b.capturedAt));
  let last = null;
  let auth = credential || { token: await tokenFor(channel, matricula) };
  for (const item of rows) {
    try {
      const result = await api({ action: 'sync', record: item, credential: auth });
      if (!result.ok) {
        item.error = result.message || 'Falha na sincronização.';
        await storePut('queue', item);
        return { error: item.error };
      }
      await storeDelete('queue', item.id);
      if (result.token) { auth.token = result.token; await saveToken(channel, matricula, result.token); }
      last = result;
    } catch (_) {
      item.offline = true;
      await storePut('queue', item);
      return { offline: true };
    }
  }
  return { last };
}

async function pendingCount(channel) {
  return (await storeAll('queue')).filter(x => x.channel === channel).length;
}
