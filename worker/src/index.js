export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allowedOrigin = 'https://sistemas-eemti.github.io';
    const headers = {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Content-Type': 'application/json'
    };
    if (origin !== allowedOrigin) return new Response(JSON.stringify({ ok: false, message: 'Origem não autorizada.' }), { status: 403, headers });
    if (request.method === 'OPTIONS') return new Response(null, { headers });
    if (request.method !== 'POST') return new Response(JSON.stringify({ ok: false, message: 'Método inválido.' }), { status: 405, headers });
    try {
      const body = await request.json();
      if (body.action !== 'sync' || !body.record) return new Response(JSON.stringify({ ok: false, message: 'Requisição inválida.' }), { status: 400, headers });
       const record = body.record;
       const credential = body.credential || {};
       const response = await fetch(env.SUPABASE_URL + '/rest/v1/rpc/sync_punch', {
         method: 'POST',
         headers: {
           'Content-Type': 'application/json',
           'apikey': env.SUPABASE_SERVICE_ROLE_KEY,
           'Authorization': 'Bearer ' + env.SUPABASE_SERVICE_ROLE_KEY
         },
         body: JSON.stringify({
           p_client_record_id: record.id,
           p_channel: record.channel,
           p_device_id: record.deviceId,
           p_enrollment: record.matricula,
           p_captured_at: record.capturedAt,
           p_offline: record.offline === true,
           p_latitude: record.latitude ?? null,
           p_longitude: record.longitude ?? null,
           p_accuracy_meters: record.accuracy ?? null,
           p_pin: credential.pin || null,
           p_token: credential.token || null
         })
       });
      const result = await response.text();
      return new Response(result, { status: response.ok ? 200 : 502, headers });
    } catch (_) {
      return new Response(JSON.stringify({ ok: false, message: 'Falha no gateway.' }), { status: 502, headers });
    }
  }
};
