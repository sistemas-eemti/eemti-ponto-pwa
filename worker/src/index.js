export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const headers = {
      'Access-Control-Allow-Origin': env.ALLOWED_ORIGIN,
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Content-Type': 'application/json'
    };
    if (origin !== env.ALLOWED_ORIGIN) return new Response(JSON.stringify({ ok: false, message: 'Origem não autorizada.' }), { status: 403, headers });
    if (request.method === 'OPTIONS') return new Response(null, { headers });
    if (request.method !== 'POST') return new Response(JSON.stringify({ ok: false, message: 'Método inválido.' }), { status: 405, headers });
    try {
      const body = await request.json();
      if (body.action !== 'sync' || !body.record) return new Response(JSON.stringify({ ok: false, message: 'Requisição inválida.' }), { status: 400, headers });
      const payload = { secret: env.API_SECRET, action: 'sync', record: body.record, credential: body.credential || {} };
      const response = await fetch(env.APPS_SCRIPT_URL, { method: 'POST', headers: { 'Content-Type': 'text/plain;charset=utf-8' }, body: JSON.stringify(payload), redirect: 'follow' });
      const result = await response.text();
      return new Response(result, { status: response.ok ? 200 : 502, headers });
    } catch (_) {
      return new Response(JSON.stringify({ ok: false, message: 'Falha no gateway.' }), { status: 502, headers });
    }
  }
};
