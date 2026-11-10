-- Ejecutar después de cuotas.sql, también en instalaciones existentes.
begin;

create or replace function public.cuotas_historial_vecino(p_vecino bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare resultado jsonb;
begin
  perform cuotas_privado.verificar_acceso();
  if p_vecino is null or not exists (
    select 1 from cuotas_privado.vecinos where id = p_vecino
  ) then raise exception 'Vecino no encontrado'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'monto', p.monto, 'fecha', p.fecha,
    'anulado_en', p.anulado_en, 'motivo_anulacion', p.motivo_anulacion,
    'aplicaciones', coalesce((
      select jsonb_agg(jsonb_build_object('mes', ap.mes, 'monto', ap.monto) order by ap.mes)
      from cuotas_privado.aplicaciones ap where ap.pago_id = p.id
    ), '[]'::jsonb)
  ) order by p.fecha desc, p.id desc), '[]'::jsonb)
  into resultado
  from cuotas_privado.pagos p
  where p.vecino_id = p_vecino;
  return resultado;
end;
$$;

revoke all on function public.cuotas_historial_vecino(bigint) from public, anon;
grant execute on function public.cuotas_historial_vecino(bigint) to authenticated;
commit;
