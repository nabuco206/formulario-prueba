-- Ejecutar solo en una base de prueba después de cuotas.sql y validar_rut.sql.
begin;

insert into auth.users(id, email)
values ('00000000-0000-0000-0000-000000000001', 'tesorero@example.invalid');
insert into cuotas_privado.autorizados values ('00000000-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

do $$
declare valor text;
begin
  foreach valor in array array['12.345.678-5', '123456785', ' 12.345.678-5 ', '6-k', '6K', '1-9', '10-8', '14-0'] loop
    if not cuotas_privado.rut_valido(valor) then raise exception 'Se rechazó un RUT válido: %', valor; end if;
  end loop;
  foreach valor in array array['12.345.678-K', '123456786', '6-0', '0-0', 'abc123456785', '12..345.678-5', '12-345-678-5', '', '12345678'] loop
    if cuotas_privado.rut_valido(valor) then raise exception 'Se aceptó un RUT inválido: %', valor; end if;
  end loop;
  if cuotas_privado.rut_valido(null) then raise exception 'Se aceptó un RUT nulo'; end if;
end;
$$;

set local role authenticated;
select public.cuotas_crear_vecino('Ana', '12.345.678-5', '2026-01-01');
do $$
begin
  begin
    perform public.cuotas_crear_vecino('Luis', '12.345.678-K', '2026-01-01');
    raise exception 'Se guardó un RUT inválido';
  exception when raise_exception then
    if sqlerrm <> 'Ingresa un RUT válido con su dígito verificador' then raise; end if;
  end;
end;
$$;
reset role;
do $$
declare vecino bigint;
begin
  select id into vecino from cuotas_privado.vecinos where nombre = 'Ana';
  begin
    perform public.cuotas_editar_vecino(vecino, 'Ana', '123456786', '2026-01-01');
    raise exception 'Se modificó el RUT a uno inválido';
  exception when raise_exception then
    if sqlerrm <> 'Ingresa un RUT válido con su dígito verificador' then raise; end if;
  end;
  perform public.cuotas_editar_vecino(vecino, 'Ana', '6-k', '2026-01-01');
  if not exists (select 1 from cuotas_privado.vecinos where id = vecino and rut = '6-k') then
    raise exception 'No se guardó un RUT válido con K';
  end if;
end;
$$;
select public.cuotas_cambiar_clave_portal('clave-de-prueba');
set local role anon;
select set_config('request.headers', '{"cf-connecting-ip":"192.0.2.1"}', true);
do $$
declare resultado jsonb;
begin
  resultado := public.vecino_mis_cuotas(extract(year from current_date)::integer, '6-K', 'clave-de-prueba');
  if resultado->'vecino'->>'nombre' <> 'Ana' then
    raise exception 'El portal no reconoció un RUT corto: %', resultado;
  end if;
end;
$$;
reset role;
alter table cuotas_privado.vecinos disable trigger vecinos_validar_rut;
insert into cuotas_privado.vecinos(nombre, rut, inicio) values ('Antiguo', 'rut-anterior', '2026-01-01');
alter table cuotas_privado.vecinos enable trigger vecinos_validar_rut;
do $$
declare vecino bigint;
begin
  select id into vecino from cuotas_privado.vecinos where nombre = 'Antiguo';
  perform public.cuotas_editar_vecino(vecino, 'Antiguo corregido', 'rut-anterior', '2026-01-01');
  if not exists (select 1 from cuotas_privado.vecinos where id = vecino and rut = 'rut-anterior') then
    raise exception 'Se modificó el RUT anterior';
  end if;
end;
$$;
rollback;
