-- Ejecutar una sola vez en el SQL Editor del proyecto Supabase.
-- Primero crea al menos un usuario en Authentication > Users.
begin;

create schema if not exists cuotas_privado;
revoke all on schema cuotas_privado from public, anon, authenticated;

create table cuotas_privado.autorizados (
  usuario_id uuid primary key references auth.users(id) on delete cascade
);
create table cuotas_privado.vecinos (
  id bigint generated always as identity primary key,
  nombre text not null check (length(btrim(nombre)) between 1 and 100),
  rut text not null unique check (length(btrim(rut)) between 1 and 30),
  inicio date not null check (inicio = date_trunc('month', inicio)::date),
  creado_en timestamptz not null default now()
);
create table cuotas_privado.aranceles (
  anio integer primary key check (anio between 2000 and 2100),
  monto bigint not null check (monto between 1 and 1000000000)
);
create table cuotas_privado.pagos (
  id bigint generated always as identity primary key,
  vecino_id bigint not null references cuotas_privado.vecinos(id),
  monto bigint not null check (monto between 1 and 1000000000),
  fecha date not null,
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now(),
  anulado_en timestamptz,
  anulado_por uuid references auth.users(id),
  motivo_anulacion text
);
create table cuotas_privado.aplicaciones (
  pago_id bigint not null references cuotas_privado.pagos(id),
  mes date not null,
  monto bigint not null check (monto > 0),
  primary key (pago_id, mes)
);

revoke all on all tables in schema cuotas_privado from public, anon, authenticated;
revoke all on all sequences in schema cuotas_privado from public, anon, authenticated;

create function cuotas_privado.verificar_acceso() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from cuotas_privado.autorizados where usuario_id = auth.uid()
  ) then
    raise exception 'Usuario no autorizado';
  end if;
end;
$$;
revoke all on function cuotas_privado.verificar_acceso() from public, anon, authenticated;

create function public.cuotas_datos(p_anio integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare resultado jsonb;
begin
  perform cuotas_privado.verificar_acceso();
  if p_anio not between 2000 and 2100 then raise exception 'Año inválido'; end if;
  select jsonb_build_object(
    'vecinos', coalesce((select jsonb_agg(to_jsonb(v) order by v.nombre, v.id)
      from cuotas_privado.vecinos v), '[]'::jsonb),
    'aranceles', coalesce((select jsonb_agg(to_jsonb(a) order by a.anio)
      from cuotas_privado.aranceles a), '[]'::jsonb),
    'cuotas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vecino_id', v.id, 'mes', m.mes::date,
        'monto', a.monto, 'pagado', coalesce(p.pagado, 0)
      ) order by v.id, m.mes)
      from cuotas_privado.vecinos v
      cross join lateral generate_series(
        make_date(p_anio, 1, 1)::timestamp,
        make_date(p_anio, 12, 1)::timestamp, interval '1 month'
      ) m(mes)
      left join cuotas_privado.aranceles a on a.anio = p_anio
      left join lateral (
        select sum(ap.monto) as pagado
        from cuotas_privado.aplicaciones ap
        join cuotas_privado.pagos pg on pg.id = ap.pago_id
        where pg.vecino_id = v.id and pg.anulado_en is null and ap.mes = m.mes::date
      ) p on true
      where m.mes::date >= v.inicio
    ), '[]'::jsonb),
    'pagos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'vecino_id', p.vecino_id, 'monto', p.monto, 'fecha', p.fecha,
        'anulado_en', p.anulado_en, 'motivo_anulacion', p.motivo_anulacion,
        'aplicaciones', coalesce((
          select jsonb_agg(jsonb_build_object('mes', ap.mes, 'monto', ap.monto) order by ap.mes)
          from cuotas_privado.aplicaciones ap where ap.pago_id = p.id
        ), '[]'::jsonb)
      ) order by p.fecha desc, p.id desc)
      from cuotas_privado.pagos p
      where extract(year from p.fecha) = p_anio
        or exists (select 1 from cuotas_privado.aplicaciones ap
          where ap.pago_id = p.id and extract(year from ap.mes) = p_anio)
    ), '[]'::jsonb)
  ) into resultado;
  return resultado;
end;
$$;

create function public.cuotas_crear_vecino(p_nombre text, p_rut text, p_inicio date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform cuotas_privado.verificar_acceso();
  if p_nombre is null or length(btrim(p_nombre)) not between 1 and 100
    or p_rut is null or length(btrim(p_rut)) not between 1 and 30
    or p_inicio is null or p_inicio <> date_trunc('month', p_inicio)::date
    or extract(year from p_inicio) not between 2000 and 2100 then
    raise exception 'Completa nombre, RUT y mes de inicio válidos';
  end if;
  insert into cuotas_privado.vecinos(nombre, rut, inicio)
  values (btrim(p_nombre), btrim(p_rut), p_inicio);
end;
$$;

create function public.cuotas_guardar_arancel(p_anio integer, p_monto bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform cuotas_privado.verificar_acceso();
  if p_anio is null or p_anio not between 2000 and 2100 or p_monto is null
    or p_monto not between 1 and 1000000000 then
    raise exception 'Año o monto inválido';
  end if;
  perform pg_advisory_xact_lock(834213, 1);
  if exists (select 1 from cuotas_privado.aplicaciones
    where extract(year from mes) = p_anio) then
    raise exception 'No se puede cambiar el monto de un año con pagos registrados, incluso anulados';
  end if;
  insert into cuotas_privado.aranceles(anio, monto) values (p_anio, p_monto)
    on conflict (anio) do update set monto = excluded.monto;
end;
$$;

create function public.cuotas_registrar_pago(p_vecino bigint, p_monto bigint, p_fecha date)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  inicio date; fin date; mes_actual date; cuota bigint; pagado bigint;
  aplicar bigint; restante bigint; pago_id bigint;
begin
  perform cuotas_privado.verificar_acceso();
  if p_vecino is null or p_monto is null or p_monto not between 1 and 1000000000
    or p_fecha is null then raise exception 'Datos de pago inválidos'; end if;
  perform pg_advisory_xact_lock(834213, 1);
  select v.inicio into inicio from cuotas_privado.vecinos v where v.id = p_vecino;
  if inicio is null then raise exception 'Vecino no encontrado'; end if;
  select make_date(max(anio), 12, 1) into fin from cuotas_privado.aranceles;
  if fin is null or fin < inicio then raise exception 'Configura los montos anuales antes de registrar pagos'; end if;
  insert into cuotas_privado.pagos(vecino_id, monto, fecha, creado_por)
    values (p_vecino, p_monto, p_fecha, auth.uid()) returning id into pago_id;
  restante := p_monto;
  mes_actual := inicio;
  while mes_actual <= fin and restante > 0 loop
    select a.monto into cuota from cuotas_privado.aranceles a
      where a.anio = extract(year from mes_actual)::integer;
    if cuota is null then
      raise exception 'Falta configurar el monto del año %', extract(year from mes_actual);
    end if;
    select coalesce(sum(ap.monto), 0) into pagado
      from cuotas_privado.aplicaciones ap
      join cuotas_privado.pagos p on p.id = ap.pago_id
      where p.vecino_id = p_vecino and p.anulado_en is null and ap.mes = mes_actual;
    aplicar := least(restante, greatest(cuota - pagado, 0));
    if aplicar > 0 then
      insert into cuotas_privado.aplicaciones(pago_id, mes, monto) values (pago_id, mes_actual, aplicar);
      restante := restante - aplicar;
    end if;
    mes_actual := (mes_actual + interval '1 month')::date;
  end loop;
  if restante > 0 then
    raise exception 'El pago supera las cuotas disponibles; configura los años necesarios';
  end if;
  return pago_id;
end;
$$;

create function public.cuotas_anular_pago(p_pago bigint, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform cuotas_privado.verificar_acceso();
  if p_motivo is null or length(btrim(p_motivo)) not between 1 and 300 then
    raise exception 'Indica un motivo de anulación';
  end if;
  perform pg_advisory_xact_lock(834213, 1);
  update cuotas_privado.pagos set anulado_en = now(), anulado_por = auth.uid(),
    motivo_anulacion = btrim(p_motivo)
    where id = p_pago and anulado_en is null;
  if not found then raise exception 'Pago no encontrado o ya anulado'; end if;
end;
$$;

revoke all on function public.cuotas_datos(integer) from public, anon;
revoke all on function public.cuotas_crear_vecino(text, text, date) from public, anon;
revoke all on function public.cuotas_guardar_arancel(integer, bigint) from public, anon;
revoke all on function public.cuotas_registrar_pago(bigint, bigint, date) from public, anon;
revoke all on function public.cuotas_anular_pago(bigint, text) from public, anon;
grant execute on function public.cuotas_datos(integer) to authenticated;
grant execute on function public.cuotas_crear_vecino(text, text, date) to authenticated;
grant execute on function public.cuotas_guardar_arancel(integer, bigint) to authenticated;
grant execute on function public.cuotas_registrar_pago(bigint, bigint, date) to authenticated;
grant execute on function public.cuotas_anular_pago(bigint, text) to authenticated;
commit;
