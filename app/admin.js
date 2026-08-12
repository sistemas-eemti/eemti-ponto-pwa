import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(window.ADMIN_CONFIG.SUPABASE_URL, window.ADMIN_CONFIG.SUPABASE_PUBLISHABLE_KEY);
const $ = id => document.getElementById(id);
const pageTitles = { dashboard: 'Visão geral', employees: 'Funcionários', geofences: 'Geocercas' };

function message(text = '', error = false) { const el = $('app-message'); el.textContent = text; el.style.color = error ? 'var(--red)' : 'var(--green)'; }
function optionList(id, rows, label) { $(id).innerHTML = '<option value="">Nenhum</option>' + rows.map(row => `<option value="${row.id}">${escapeHtml(row[label])}</option>`).join(''); }
function escapeHtml(value) { const el = document.createElement('span'); el.textContent = value ?? ''; return el.innerHTML; }
function todayRange() { const date = new Date(); date.setHours(0, 0, 0, 0); return date.toISOString(); }

async function requireAdmin() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return false;
  const { data: isAdmin, error } = await supabase.rpc('is_admin');
  if (error || !isAdmin) { await supabase.auth.signOut(); $('login-message').textContent = 'Esta conta não possui acesso administrativo.'; return false; }
  const { data: profile } = await supabase.from('admin_profiles').select('display_name').eq('user_id', session.user.id).maybeSingle();
  $('account-name').textContent = profile?.display_name || session.user.email;
  $('login-view').hidden = true; $('app-view').hidden = false;
  return true;
}

async function loadDashboard() {
  const today = todayRange();
  const [employees, punches, outside, geofences, recent] = await Promise.all([
    supabase.from('employees').select('*', { count: 'exact', head: true }).eq('active', true),
    supabase.from('punches').select('*', { count: 'exact', head: true }).gte('captured_at', today),
    supabase.from('punches').select('*', { count: 'exact', head: true }).gte('captured_at', today).eq('inside_geofence', false),
    supabase.from('geofences').select('*', { count: 'exact', head: true }).eq('active', true),
    supabase.from('punches').select('captured_at, origin, inside_geofence, employees(name, enrollment)').order('captured_at', { ascending: false }).limit(12)
  ]);
  const results = [employees, punches, outside, geofences, recent];
  const failure = results.find(result => result.error); if (failure) throw failure.error;
  $('total-employees').textContent = employees.count || 0; $('today-punches').textContent = punches.count || 0; $('outside-punches').textContent = outside.count || 0; $('active-geofences').textContent = geofences.count || 0;
  $('recent-punches').innerHTML = recent.data.map(row => `<tr><td>${new Date(row.captured_at).toLocaleString('pt-BR')}</td><td>${escapeHtml(row.employees?.name || '-')}${row.employees?.enrollment ? ` <span class="muted">${escapeHtml(row.employees.enrollment)}</span>` : ''}</td><td>${escapeHtml(row.origin)}</td><td>${row.inside_geofence === false ? '<span class="badge">Fora da cerca</span>' : 'Dentro / não verificado'}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhuma batida registrada.</td></tr>';
}

async function loadEmployees() {
  const [employees, departments, positions, schedules] = await Promise.all([
    supabase.from('employees').select('enrollment,name,active,departments(name)').order('name'),
    supabase.from('departments').select('id,name').order('name'), supabase.from('positions').select('id,name').order('name'), supabase.from('schedules').select('id,name').order('name')
  ]);
  const results = [employees, departments, positions, schedules]; const failure = results.find(result => result.error); if (failure) throw failure.error;
  optionList('employee-department', departments.data, 'name'); optionList('employee-position', positions.data, 'name'); optionList('employee-schedule', schedules.data, 'name');
  $('employees-list').innerHTML = employees.data.map(row => `<tr><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.departments?.name || '-')}</td><td><span class="badge">${row.active ? 'Ativo' : 'Inativo'}</span></td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhum funcionário cadastrado.</td></tr>';
}

async function loadGeofences() {
  const { data, error } = await supabase.from('geofences').select('*').order('name'); if (error) throw error;
  $('geofences-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.latitude}, ${row.longitude}</td><td>${row.radius_meters} m</td><td><span class="badge">${row.active ? 'Ativa' : 'Inativa'}</span></td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhuma geocerca cadastrada.</td></tr>';
}

async function loadPage(page) { message(); if (page === 'dashboard') await loadDashboard(); if (page === 'employees') await loadEmployees(); if (page === 'geofences') await loadGeofences(); }
async function showPage(page) { document.querySelectorAll('.nav').forEach(el => el.classList.toggle('active', el.dataset.page === page)); document.querySelectorAll('.page').forEach(el => el.classList.toggle('active', el.id === `${page}-page`)); $('page-title').textContent = pageTitles[page]; await loadPage(page); }

$('login-form').addEventListener('submit', async event => { event.preventDefault(); $('login-message').textContent = ''; const { error } = await supabase.auth.signInWithPassword({ email: $('email').value.trim(), password: $('password').value }); if (error) { $('login-message').textContent = 'E-mail ou senha inválidos.'; return; } if (await requireAdmin()) await showPage('dashboard'); });
$('logout').addEventListener('click', async () => { await supabase.auth.signOut(); $('app-view').hidden = true; $('login-view').hidden = false; $('password').value = ''; });
$('refresh').addEventListener('click', () => loadPage(document.querySelector('.nav.active').dataset.page).catch(error => message(error.message, true)));
document.querySelectorAll('.nav').forEach(button => button.addEventListener('click', () => showPage(button.dataset.page).catch(error => message(error.message, true))));
$('employee-form').addEventListener('submit', async event => { event.preventDefault(); const { error } = await supabase.rpc('admin_save_employee', { p_enrollment: $('employee-enrollment').value, p_name: $('employee-name').value, p_pin: $('employee-pin').value, p_department_id: $('employee-department').value || null, p_position_id: $('employee-position').value || null, p_schedule_id: $('employee-schedule').value || null }); if (error) { message(error.message, true); return; } event.target.reset(); message('Funcionário salvo.'); await loadEmployees(); });
$('geofence-form').addEventListener('submit', async event => { event.preventDefault(); const { error } = await supabase.from('geofences').insert({ name: $('geofence-name').value.trim(), latitude: $('geofence-latitude').value, longitude: $('geofence-longitude').value, radius_meters: $('geofence-radius').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Geocerca salva.'); await loadGeofences(); });

if (await requireAdmin()) await showPage('dashboard').catch(error => message(error.message, true));
