-- EEMTI Ponto: schema inicial PostgreSQL/Supabase.
-- A PWA nunca acessa essas tabelas diretamente. O Worker usa service_role.

create extension if not exists pgcrypto;

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.positions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  entry_time time,
  exit_time time,
  break_start time,
  break_end time,
  daily_minutes integer not null default 0 check (daily_minutes >= 0),
  weekdays smallint[] not null default '{1,2,3,4,5}',
  tolerance_minutes integer not null default 0 check (tolerance_minutes >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  enrollment text not null unique,
  name text not null,
  cpf text unique,
  pis text,
  department_id uuid references public.departments(id),
  position_id uuid references public.positions(id),
  schedule_id uuid references public.schedules(id),
  pin_hash text,
  active boolean not null default true,
  admitted_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.geofences (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  radius_meters integer not null check (radius_meters > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  client_device_id text not null unique,
  channel text not null check (channel in ('mobile', 'kiosk')),
  label text,
  active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  device_id uuid not null references public.devices(id),
  token_hash text not null unique,
  expires_at timestamptz not null,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (employee_id, device_id, token_hash)
);

create table public.punches (
  id uuid primary key default gen_random_uuid(),
  client_record_id text not null unique,
  employee_id uuid not null references public.employees(id),
  device_id uuid references public.devices(id),
  origin text not null check (origin in ('mobile', 'kiosk', 'mobile_offline', 'kiosk_offline', 'manual')),
  captured_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  synced_at timestamptz,
  latitude numeric(10,7),
  longitude numeric(10,7),
  accuracy_meters numeric(10,2),
  geofence_id uuid references public.geofences(id),
  inside_geofence boolean,
  distance_meters numeric(10,2),
  captured_offline boolean not null default false,
  excluded_at timestamptz,
  previous_hash text not null default '',
  hash text not null unique,
  created_at timestamptz not null default now()
);

create index punches_employee_captured_at_idx on public.punches (employee_id, captured_at);
create index punches_recorded_at_idx on public.punches (recorded_at desc);
create index punches_device_id_idx on public.punches (device_id);

create table public.punch_adjustments (
  id uuid primary key default gen_random_uuid(),
  punch_id uuid not null references public.punches(id),
  kind text not null check (kind in ('exclude', 'include', 'edit')),
  reason text not null,
  before_value jsonb,
  after_value jsonb,
  requested_by text not null,
  approved_by text,
  created_at timestamptz not null default now()
);

create table public.absences (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  absence_date date not null,
  type text not null default 'absence',
  reason text,
  excused boolean not null default false,
  document_reference text,
  created_at timestamptz not null default now(),
  unique (employee_id, absence_date, type)
);

create table public.occurrences (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  occurrence_date date not null,
  type text not null,
  description text not null,
  recorded_by text not null,
  created_at timestamptz not null default now()
);

create table public.holidays (
  holiday_date date primary key,
  description text not null,
  type text not null default 'national'
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  event_at timestamptz not null default now(),
  actor text not null,
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb
);

create table public.settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger schedules_updated_at before update on public.schedules
for each row execute function public.set_updated_at();
create trigger employees_updated_at before update on public.employees
for each row execute function public.set_updated_at();
create trigger geofences_updated_at before update on public.geofences
for each row execute function public.set_updated_at();

-- Sem políticas públicas: somente o Worker (service_role) terá acesso às tabelas.
alter table public.departments enable row level security;
alter table public.positions enable row level security;
alter table public.schedules enable row level security;
alter table public.employees enable row level security;
alter table public.geofences enable row level security;
alter table public.devices enable row level security;
alter table public.device_tokens enable row level security;
alter table public.punches enable row level security;
alter table public.punch_adjustments enable row level security;
alter table public.absences enable row level security;
alter table public.occurrences enable row level security;
alter table public.holidays enable row level security;
alter table public.audit_events enable row level security;
alter table public.settings enable row level security;
