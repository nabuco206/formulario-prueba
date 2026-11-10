-- Ejecutar después de instalar cuotas.sql; también actualiza instalaciones anteriores.
begin;

alter table cuotas_privado.pagos add column if not exists comprobante text;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
do $$
begin
  if not exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'pgcrypto' and n.nspname = 'extensions'
  ) then
    raise exception 'La extensión pgcrypto debe estar instalada en el esquema extensions';
  end if;
end;
$$;

create unique index if not exists vecinos_rut_normalizado_uidx
  on cuotas_privado.vecinos (regexp_replace(upper(btrim(rut)), '[^0-9K]', '', 'g'));

create table if not exists cuotas_privado.clave_portal (
  unica boolean primary key default true check (unica),
  hash text not null
);
create table if not exists cuotas_privado.intentos_portal (
  origen text primary key,
  desde timestamptz not null,
  intentos integer not null
);
revoke all on cuotas_privado.clave_portal, cuotas_privado.intentos_portal from public, anon, authenticated;

create or replace function public.cuotas_cambiar_clave_portal(p_clave text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform cuotas_privado.verificar_acceso();
  if p_clave is null or char_length(p_clave) < 8 or octet_length(p_clave) > 72 then
    raise exception 'La clave debe tener al menos 8 caracteres y un máximo de 72 bytes';
  end if;
  insert into cuotas_privado.clave_portal(unica, hash)
    values (true, extensions.crypt(p_clave, extensions.gen_salt('bf', 10)))
    on conflict (unica) do update set hash = excluded.hash;
end;
$$;

create or replace function public.vecino_mis_cuotas(p_anio integer, p_rut text, p_clave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_origen text;
  v_intentos integer;
  v_hash text;
  v_rut text;
  v_inicio date;
  v_vecino_id bigint;
  v_nombre text;
  v_mes_actual date := date_trunc('month', current_date)::date;
  v_anio_actual integer := extract(year from current_date)::integer;
  v_resultado jsonb;
begin
  v_origen := md5(coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb ->> 'cf-connecting-ip',
    'sin-direccion'
  ));
  perform pg_advisory_xact_lock(hashtext(v_origen));
  delete from cuotas_privado.intentos_portal
    where origen = v_origen and desde < now() - interval '15 minutes';
  select intentos into v_intentos from cuotas_privado.intentos_portal where origen = v_origen;
  if coalesce(v_intentos, 0) >= 20 then
    return jsonb_build_object('error', 'Demasiados intentos. Espera 15 minutos e inténtalo nuevamente.');
  end if;

  select hash into v_hash from cuotas_privado.clave_portal where unica;
  if v_hash is null then
    return jsonb_build_object('error', 'La clave del portal aún no está configurada. Contacta a la directiva.');
  end if;
  if p_clave is null or octet_length(p_clave) > 72
    or extensions.crypt(p_clave, v_hash) <> v_hash then
    insert into cuotas_privado.intentos_portal(origen, desde, intentos)
      values (v_origen, now(), 1)
      on conflict (origen) do update set intentos = cuotas_privado.intentos_portal.intentos + 1;
    return jsonb_build_object('error', 'RUT o clave incorrectos.', 'codigo', 'credenciales');
  end if;
  delete from cuotas_privado.intentos_portal where origen = v_origen;
  if p_anio is null or p_anio not between 2000 and v_anio_actual then
    raise exception 'Año inválido';
  end if;
  v_rut := regexp_replace(upper(coalesce(p_rut, '')), '[^0-9K]', '', 'g');
  if v_rut !~ '^[0-9]{1,8}[0-9K]$' then return jsonb_build_object('error', 'RUT o clave incorrectos.'); end if;

  select v.id, v.nombre, v.inicio into v_vecino_id, v_nombre, v_inicio
    from cuotas_privado.vecinos v
    where regexp_replace(upper(btrim(v.rut)), '[^0-9K]', '', 'g') = v_rut;
  if v_vecino_id is null then return jsonb_build_object('error', 'RUT o clave incorrectos.'); end if;
  if p_anio < extract(year from v_inicio)::integer then
    raise exception 'Año fuera del período de cuotas';
  end if;

  select jsonb_build_object(
    'vecino', jsonb_build_object('nombre', v_nombre, 'rut', v_rut),
    'anio_inicio', extract(year from v_inicio)::integer,
    'anio_actual', v_anio_actual,
    'mes_actual', v_mes_actual,
    'configuracion_completa', not exists (
      select 1
      from generate_series(extract(year from v_inicio)::integer, v_anio_actual) y(anio)
      left join cuotas_privado.aranceles a on a.anio = y.anio::integer
      where a.anio is null
    ),
    'deuda_hasta_hoy', coalesce((
      select sum(greatest(a.monto - coalesce(p.pagado, 0), 0))
      from generate_series(
        v_inicio::timestamp, v_mes_actual::timestamp, interval '1 month'
      ) m(mes)
      join cuotas_privado.aranceles a on a.anio = extract(year from m.mes)::integer
      left join lateral (
        select sum(ap.monto) as pagado
        from cuotas_privado.aplicaciones ap
        join cuotas_privado.pagos pg on pg.id = ap.pago_id
        where pg.vecino_id = v_vecino_id and pg.anulado_en is null
          and ap.mes = m.mes::date
      ) p on true
    ), 0),
    'cuotas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mes', m.mes::date,
        'monto', a.monto,
        'pagado', coalesce(p.pagado, 0)
      ) order by m.mes)
      from generate_series(
        greatest(make_date(p_anio, 1, 1), v_inicio)::timestamp,
        least(make_date(p_anio, 12, 1), v_mes_actual)::timestamp,
        interval '1 month'
      ) m(mes)
      left join cuotas_privado.aranceles a on a.anio = p_anio
      left join lateral (
        select sum(ap.monto) as pagado
        from cuotas_privado.aplicaciones ap
        join cuotas_privado.pagos pg on pg.id = ap.pago_id
        where pg.vecino_id = v_vecino_id and pg.anulado_en is null
          and ap.mes = m.mes::date
      ) p on true
      where p_anio >= extract(year from v_inicio)::integer
        and p_anio <= v_anio_actual
    ), '[]'::jsonb),
    'pagos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pg.id,
        'monto', pg.monto,
        'fecha', pg.fecha,
        'comprobante', pg.comprobante,
        'anulado_en', pg.anulado_en,
        'motivo_anulacion', pg.motivo_anulacion,
        'aplicaciones', coalesce((
          select jsonb_agg(jsonb_build_object('mes', ap.mes, 'monto', ap.monto) order by ap.mes)
          from cuotas_privado.aplicaciones ap where ap.pago_id = pg.id
        ), '[]'::jsonb)
      ) order by pg.fecha desc, pg.id desc)
      from cuotas_privado.pagos pg
      where pg.vecino_id = v_vecino_id
        and (extract(year from pg.fecha) = p_anio or exists (
          select 1 from cuotas_privado.aplicaciones ap
          where ap.pago_id = pg.id and extract(year from ap.mes) = p_anio
        ))
    ), '[]'::jsonb)
  ) into v_resultado;

  return v_resultado;
end;
$$;

drop function if exists public.vecino_mis_cuotas(integer);
revoke all on function public.cuotas_cambiar_clave_portal(text) from public, anon;
revoke all on function public.vecino_mis_cuotas(integer, text, text) from public;
grant execute on function public.cuotas_cambiar_clave_portal(text) to authenticated;
grant execute on function public.vecino_mis_cuotas(integer, text, text) to anon, authenticated;
commit;
