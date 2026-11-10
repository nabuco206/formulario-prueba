-- Ejecutar después de cuotas.sql; no elimina datos. Luego vuelve a ejecutar
-- historial_vecino.sql y portal_vecinos.sql para mostrar el comprobante.
begin;

alter table cuotas_privado.pagos add column if not exists comprobante text;
alter table cuotas_privado.pagos drop constraint if exists pagos_comprobante_check;
alter table cuotas_privado.pagos add constraint pagos_comprobante_check
  check (comprobante is null or comprobante ~ '^[A-Za-z0-9][A-Za-z0-9./-]{0,29}$');
-- Un mismo comprobante no puede usarse en dos pagos vigentes.
create unique index if not exists pagos_comprobante_vigente_uidx
  on cuotas_privado.pagos (upper(comprobante))
  where anulado_en is null and comprobante is not null;

create or replace function public.cuotas_registrar_pago(
  p_vecino bigint, p_monto bigint, p_fecha date, p_comprobante text
) returns bigint language plpgsql security definer set search_path = '' as $$
declare v_comp text := upper(btrim(p_comprobante)); pago_id bigint;
begin
  perform cuotas_privado.verificar_acceso();
  if v_comp is null or v_comp !~ '^[A-Z0-9][A-Z0-9./-]{0,29}$' then
    raise exception 'El número de comprobante es obligatorio (letras, números, punto, guion o barra; máximo 30)';
  end if;
  if exists (select 1 from cuotas_privado.pagos
    where upper(comprobante) = v_comp and anulado_en is null) then
    raise exception 'El número de comprobante ya está registrado en otro pago';
  end if;
  pago_id := public.cuotas_registrar_pago(p_vecino, p_monto, p_fecha);
  update cuotas_privado.pagos set comprobante = v_comp
    where id = pago_id;
  return pago_id;
end;
$$;

-- Se exige comprobante: la versión anterior ya no puede llamarse desde la página.
revoke all on function public.cuotas_registrar_pago(bigint, bigint, date) from public, anon, authenticated;
revoke all on function public.cuotas_registrar_pago(bigint, bigint, date, text) from public, anon;
grant execute on function public.cuotas_registrar_pago(bigint, bigint, date, text) to authenticated;
commit;
