-- Ejecutar como administrador después de instalar cuotas.sql y portal_vecinos.sql
-- en una base de prueba con los roles y funciones de Supabase.
begin;

insert into auth.users(id, email)
values ('00000000-0000-0000-0000-000000000001', 'tesorero@example.invalid'),
       ('00000000-0000-0000-0000-000000000002', 'otro@example.invalid');
insert into cuotas_privado.autorizados(usuario_id)
values ('00000000-0000-0000-0000-000000000001');
insert into cuotas_privado.vecinos(nombre, rut, inicio)
values ('Vecino de prueba', '12.345.678-K', date_trunc('year', current_date)::date);
insert into cuotas_privado.aranceles(anio, monto)
values (extract(year from current_date)::integer, 1000);

set local role anon;
do $$
begin
  begin
    perform public.cuotas_cambiar_clave_portal('clave-inicial');
    raise exception 'Un usuario anónimo pudo cambiar la clave';
  exception when insufficient_privilege then null;
  end;
  if public.vecino_mis_cuotas(extract(year from current_date)::integer, '12345678K', 'clave-inicial')->>'error'
    not like '%no está configurada%' then
    raise exception 'El portal aceptó consultas antes de configurar la clave';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
do $$
begin
  begin
    perform public.cuotas_cambiar_clave_portal('clave-inicial');
    raise exception 'Un usuario no autorizado pudo cambiar la clave';
  exception when raise_exception then
    if sqlerrm <> 'Usuario no autorizado' then raise; end if;
  end;
end;
$$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
begin
  begin
    perform public.cuotas_cambiar_clave_portal('corta');
    raise exception 'Se aceptó una clave demasiado corta';
  exception when raise_exception then
    if sqlerrm not like 'La clave debe tener%' then raise; end if;
  end;
  begin
    perform public.cuotas_cambiar_clave_portal(repeat('á', 37));
    raise exception 'Se aceptó una clave de más de 72 bytes';
  exception when raise_exception then
    if sqlerrm not like 'La clave debe tener%' then raise; end if;
  end;
end;
$$;
select public.cuotas_cambiar_clave_portal('clave-inicial');

reset role;
do $$
begin
  if (select hash = 'clave-inicial' from cuotas_privado.clave_portal) then
    raise exception 'La clave fue almacenada sin hash';
  end if;
end;
$$;
set local role anon;
select set_config('request.headers', '{"cf-connecting-ip":"192.0.2.1"}', true);
do $$
declare resultado jsonb;
begin
  resultado := public.vecino_mis_cuotas(extract(year from current_date)::integer, '12.345.678-K', 'clave-inicial');
  if resultado->'vecino'->>'nombre' <> 'Vecino de prueba' or resultado ? 'error' then
    raise exception 'No se pudieron consultar las cuotas: %', resultado;
  end if;
  resultado := public.vecino_mis_cuotas(extract(year from current_date)::integer, '12345678K', 'incorrecta');
  if resultado->>'codigo' <> 'credenciales' then
    raise exception 'Se aceptó una clave incorrecta: %', resultado;
  end if;
end;
$$;

reset role;
set local role authenticated;
select public.cuotas_cambiar_clave_portal('clave-nueva');
reset role;
set local role anon;
do $$
declare resultado jsonb;
begin
  resultado := public.vecino_mis_cuotas(extract(year from current_date)::integer, '12345678K', 'clave-inicial');
  if resultado->>'codigo' <> 'credenciales' then
    raise exception 'La clave anterior sigue funcionando';
  end if;
  resultado := public.vecino_mis_cuotas(extract(year from current_date)::integer, '12345678K', 'clave-nueva');
  if resultado->'vecino'->>'nombre' <> 'Vecino de prueba' then
    raise exception 'La clave nueva no funciona: %', resultado;
  end if;
  for i in 1..20 loop
    perform public.vecino_mis_cuotas(extract(year from current_date)::integer, '12345678K', 'incorrecta');
  end loop;
  resultado := public.vecino_mis_cuotas(extract(year from current_date)::integer, '12345678K', 'clave-nueva');
  if resultado->>'error' not like 'Demasiados intentos%' then
    raise exception 'No se bloquearon los intentos excesivos: %', resultado;
  end if;
end;
$$;
rollback;
