-- Ejecutar solo en una base de prueba después de cuotas.sql e historial_vecino.sql.
begin;

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000001', 'tesorero@example.invalid'),
  ('00000000-0000-0000-0000-000000000002', 'otro@example.invalid');
insert into cuotas_privado.autorizados values ('00000000-0000-0000-0000-000000000001');
insert into cuotas_privado.vecinos(id, nombre, rut, inicio) overriding system value values
  (1, 'Ana', '12.345.678-K', '2024-01-01'),
  (2, 'Luis', '11.111.111-1', '2024-01-01');
insert into cuotas_privado.pagos(id, vecino_id, monto, fecha, creado_por, anulado_en, motivo_anulacion)
overriding system value values
  (1, 1, 1000, '2024-03-05', '00000000-0000-0000-0000-000000000001', null, null),
  (2, 1, 2000, '2026-04-06', '00000000-0000-0000-0000-000000000001', now(), 'Error'),
  (3, 2, 3000, '2025-01-01', '00000000-0000-0000-0000-000000000001', null, null);
insert into cuotas_privado.aplicaciones values (1, '2024-03-01', 1000), (2, '2026-04-01', 2000);

set local role anon;
do $$
begin
  begin
    perform public.cuotas_historial_vecino(1);
    raise exception 'Se permitió consultar sin sesión';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
do $$
begin
  begin
    perform public.cuotas_historial_vecino(1);
    raise exception 'Se permitió consultar sin autorización';
  exception when raise_exception then
    if sqlerrm <> 'Usuario no autorizado' then raise; end if;
  end;
end;
$$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
declare resultado jsonb;
begin
  resultado := public.cuotas_historial_vecino(1);
  if jsonb_array_length(resultado) <> 2
    or resultado->0->>'fecha' <> '2026-04-06'
    or resultado->0->>'motivo_anulacion' <> 'Error'
    or resultado->1->>'fecha' <> '2024-03-05'
    or resultado->1->'aplicaciones'->0->>'mes' <> '2024-03-01' then
    raise exception 'Historial incorrecto: %', resultado;
  end if;
  if jsonb_array_length(public.cuotas_historial_vecino(2)) <> 1 then
    raise exception 'El historial contiene pagos de otro vecino';
  end if;
  begin
    perform public.cuotas_historial_vecino(999);
    raise exception 'Se permitió consultar un vecino inexistente';
  exception when raise_exception then
    if sqlerrm <> 'Vecino no encontrado' then raise; end if;
  end;
end;
$$;
reset role;
insert into cuotas_privado.vecinos(id, nombre, rut, inicio) overriding system value
values (4, 'Sin pagos', '44.444.444-4', '2024-01-01');
set local role authenticated;
do $$
begin
  if public.cuotas_historial_vecino(4) <> '[]'::jsonb then
    raise exception 'El historial vacío es incorrecto';
  end if;
end;
$$;
rollback;
