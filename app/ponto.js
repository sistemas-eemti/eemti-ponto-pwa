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
  let response;
  try {
    response = await fetch(window.PONTO_CONFIG.API_URL, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    });
  } catch (_) {
    throw new Error('NETWORK');
  }
  const text = await response.text();
  let result;
  try { result = JSON.parse(text); } catch (_) { throw new Error('GATEWAY'); }
  if (!response.ok) throw new Error(result.message || 'GATEWAY');
  return result;
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
        if (result.message === 'Batida repetida. Aguarde um instante e tente de novo.') {
          await storeDelete('queue', item.id);
          return { error: result.message };
        }
        item.error = result.message || 'Falha na sincronização.';
        await storePut('queue', item);
        return { error: item.error };
      }
      await storeDelete('queue', item.id);
      if (result.token) { auth.token = result.token; await saveToken(channel, matricula, result.token); }
      last = result;
    } catch (error) {
      item.offline = true;
      await storePut('queue', item);
      if (error && error.message === 'NETWORK') return { offline: true };
      return { error: 'Falha na comunicação com o servidor. Verifique a configuração da API.' };
    }
  }
  return { last };
}

async function pendingCount(channel) {
  return (await storeAll('queue')).filter(x => x.channel === channel).length;
}
