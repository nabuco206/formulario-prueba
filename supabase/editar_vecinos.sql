-- Ejecutar después de cuotas.sql y portal_vecinos.sql, también en instalaciones existentes.
begin;

create or replace function public.cuotas_editar_vecino(
  p_vecino bigint, p_nombre text, p_rut text, p_inicio date
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform cuotas_privado.verificar_acceso();
  if p_vecino is null or p_nombre is null or length(btrim(p_nombre)) not between 1 and 100
    or p_rut is null or length(btrim(p_rut)) not between 1 and 30
    or p_inicio is null or p_inicio <> date_trunc('month', p_inicio)::date
    or extract(year from p_inicio) not between 2000 and 2100 then
    raise exception 'Completa nombre, RUT y mes de inicio válidos';
  end if;

  perform pg_advisory_xact_lock(834213, 1);
  if not exists (select 1 from cuotas_privado.vecinos where id = p_vecino) then
    raise exception 'Vecino no encontrado';
  end if;
  if exists (
    select 1 from cuotas_privado.aplicaciones ap
    join cuotas_privado.pagos pg on pg.id = ap.pago_id
    where pg.vecino_id = p_vecino and pg.anulado_en is null and ap.mes < p_inicio
  ) then
    raise exception 'No se puede fijar el inicio después de cuotas con pagos vigentes';
  end if;

  begin
    update cuotas_privado.vecinos
      set nombre = btrim(p_nombre), rut = btrim(p_rut), inicio = p_inicio
      where id = p_vecino;
  exception when unique_violation then
    raise exception 'Ya existe un vecino con ese RUT';
  end;
end;
$$;

revoke all on function public.cuotas_editar_vecino(bigint, text, text, date) from public, anon;
grant execute on function public.cuotas_editar_vecino(bigint, text, text, date) to authenticated;
commit;
