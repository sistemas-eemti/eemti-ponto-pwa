-- Dados iniciais exclusivamente para homologação.
-- Troque os PINs antes da produção e remova funcionários fictícios.

insert into public.departments (name) values
  ('Teste'), ('Segurança'), ('Terceirizados')
on conflict (name) do nothing;

insert into public.positions (name) values ('Colaborador')
on conflict (name) do nothing;

insert into public.schedules (name, entry_time, exit_time, daily_minutes, weekdays, tolerance_minutes)
values ('Todos os Dias', '08:00', '17:00', 480, '{1,2,3,4,5,6,7}', 10)
on conflict (name) do nothing;

insert into public.employees (enrollment, name, department_id, position_id, schedule_id, pin_hash)
select v.enrollment, v.name, d.id, p.id, s.id, crypt(v.pin, gen_salt('bf'))
from (values
  ('002', 'Rafael David Teixeira', '1234'),
  ('004', 'Teste 04', '1234'),
  ('100', 'Karoline David', '1234'),
  ('200', 'Ana Paula de Araujo', '1234')
) as v(enrollment, name, pin)
cross join (select id from public.departments where name = 'Teste') d
cross join (select id from public.positions where name = 'Colaborador') p
cross join (select id from public.schedules where name = 'Todos os Dias') s
on conflict (enrollment) do nothing;

-- Atualize com as coordenadas reais da escola antes de produção.
insert into public.geofences (name, latitude, longitude, radius_meters)
values ('Local de teste', -3.7318620, -38.5266700, 100)
on conflict do nothing;
