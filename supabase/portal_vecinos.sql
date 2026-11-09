-- Ejecutar una sola vez después de instalar cuotas.sql.
-- El inicio de sesión usa un correo sintético interno derivado del RUT.
begin;

create unique index if not exists vecinos_rut_normalizado_uidx
  on cuotas_privado.vecinos (regexp_replace(upper(btrim(rut)), '[^0-9K]', '', 'g'));

create or replace function public.vecino_mis_cuotas(p_anio integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email text;
  v_alias text;
  v_rut text;
  v_inicio date;
  v_vecino_id bigint;
  v_nombre text;
  v_mes_actual date := date_trunc('month', current_date)::date;
  v_anio_actual integer := extract(year from current_date)::integer;
  v_resultado jsonb;
begin
  if auth.uid() is null then raise exception 'Inicia sesión para continuar'; end if;
  if p_anio is null or p_anio not between 2000 and v_anio_actual then
    raise exception 'Año inválido';
  end if;

  select u.email into v_email from auth.users u where u.id = auth.uid();
  v_alias := lower(split_part(coalesce(v_email, ''), '@', 1));
  if split_part(coalesce(v_email, ''), '@', 2) <> 'socios.invalid'
    or v_alias !~ '^rut[0-9]{7,8}[0-9k]$' then
    raise exception 'RUT o clave incorrectos';
  end if;
  v_rut := upper(substring(v_alias from 4));

  select v.id, v.nombre, v.inicio into v_vecino_id, v_nombre, v_inicio
    from cuotas_privado.vecinos v
    where regexp_replace(upper(btrim(v.rut)), '[^0-9K]', '', 'g') = v_rut;
  if v_vecino_id is null then raise exception 'RUT o clave incorrectos'; end if;
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

revoke all on function public.vecino_mis_cuotas(integer) from public, anon;
grant execute on function public.vecino_mis_cuotas(integer) to authenticated;
commit;
