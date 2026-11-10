-- Ejecutar solo en una base de prueba después de cuotas.sql y comprobante.sql.
begin;
insert into auth.users(id, email) values ('00000000-0000-0000-0000-000000000001', 't@example.invalid');
insert into cuotas_privado.autorizados values ('00000000-0000-0000-0000-000000000001');
insert into cuotas_privado.vecinos(id, nombre, rut, inicio) overriding system value values (1, 'Ana', '11.111.111-1', '2026-01-01');
insert into cuotas_privado.aranceles(anio, monto) values (2026, 1000) on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
declare id1 bigint; v bigint := 1;
begin
  begin
    perform public.cuotas_registrar_pago(v, 1000, current_date);
    raise exception 'Se permitió pago sin comprobante vía función antigua';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.cuotas_registrar_pago(v, 1000, current_date, '  ');
    raise exception 'Se aceptó comprobante vacío';
  exception when raise_exception then
    if sqlerrm not like 'El número de comprobante es obligatorio%' then raise; end if;
  end;
  id1 := public.cuotas_registrar_pago(v, 1000, current_date, ' ab-123 ');
  perform set_config('test.pago', id1::text, true);
  begin
    perform public.cuotas_registrar_pago(v, 1000, current_date, 'ab-123');
    raise exception 'Se aceptó comprobante repetido';
  exception when raise_exception then
    if sqlerrm not like 'El número de comprobante ya%' then raise; end if;
  end;
  perform public.cuotas_anular_pago(id1, 'Error');
  perform public.cuotas_registrar_pago(v, 1000, current_date, 'AB-123');
end;
$$;
reset role;
do $$
begin
  if (select comprobante from cuotas_privado.pagos where id = current_setting('test.pago')::bigint) <> 'AB-123' then
    raise exception 'Comprobante mal guardado';
  end if;
end;
$$;
rollback;
