-- Ejecutar solo en una base de prueba después de instalar los scripts.
begin;

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000001', 'tesorero@example.invalid'),
  ('00000000-0000-0000-0000-000000000002', 'otro@example.invalid');
insert into cuotas_privado.autorizados values ('00000000-0000-0000-0000-000000000001');
insert into cuotas_privado.vecinos(id, nombre, rut, inicio) overriding system value values
  (1, 'Ana', '12.345.678-K', '2026-01-01'),
  (2, 'Luis', '11.111.111-1', '2026-01-01');
insert into cuotas_privado.pagos(id, vecino_id, monto, fecha, creado_por) overriding system value values
  (1, 1, 1000, '2026-01-01', '00000000-0000-0000-0000-000000000001');
insert into cuotas_privado.aplicaciones values (1, '2026-01-01', 1000);

set local role anon;
do $$
begin
  begin
    perform public.cuotas_editar_vecino(1, 'Ana', '12345678K', '2026-01-01');
    raise exception 'Se permitió editar sin sesión';
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
    perform public.cuotas_editar_vecino(1, 'Ana', '12345678K', '2026-01-01');
    raise exception 'Se permitió editar sin autorización';
  exception when raise_exception then
    if sqlerrm <> 'Usuario no autorizado' then raise; end if;
  end;
end;
$$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select public.cuotas_editar_vecino(1, ' Ana corregida ', '12345678K', '2025-12-01');
do $$
begin
  begin
    perform public.cuotas_editar_vecino(1, 'Ana', '11.111.111-1', '2026-01-01');
    raise exception 'Se permitió un RUT duplicado';
  exception when raise_exception then
    if sqlerrm <> 'Ya existe un vecino con ese RUT' then raise; end if;
  end;
  begin
    perform public.cuotas_editar_vecino(1, 'Ana', '111111111', '2026-01-01');
    raise exception 'Se permitió un RUT duplicado con otro formato';
  exception when raise_exception then
    if sqlerrm <> 'Ya existe un vecino con ese RUT' then raise; end if;
  end;
  begin
    perform public.cuotas_editar_vecino(1, 'Ana', '12345678K', '2026-02-01');
    raise exception 'Se permitió ocultar un pago vigente';
  exception when raise_exception then
    if sqlerrm <> 'No se puede fijar el inicio después de cuotas con pagos vigentes' then raise; end if;
  end;
  begin
    perform public.cuotas_editar_vecino(999, 'Ana', '12345678K', '2026-01-01');
    raise exception 'Se permitió modificar un vecino inexistente';
  exception when raise_exception then
    if sqlerrm <> 'Vecino no encontrado' then raise; end if;
  end;
  begin
    perform public.cuotas_editar_vecino(1, 'Ana', '12345678K', '2026-01-02');
    raise exception 'Se permitió un inicio que no es el primer día del mes';
  exception when raise_exception then
    if sqlerrm <> 'Completa nombre, RUT y mes de inicio válidos' then raise; end if;
  end;
end;
$$;

reset role;
do $$
begin
  if not exists (
    select 1 from cuotas_privado.vecinos
    where id = 1 and nombre = 'Ana corregida' and rut = '12345678K' and inicio = '2025-12-01'
  ) then raise exception 'La modificación válida no se guardó'; end if;
  if not exists (
    select 1 from cuotas_privado.aplicaciones where pago_id = 1 and mes = '2026-01-01' and monto = 1000
  ) then raise exception 'Se alteró el pago existente'; end if;
end;
$$;
update cuotas_privado.pagos set anulado_en = now() where id = 1;
set local role authenticated;
select public.cuotas_editar_vecino(1, 'Ana corregida', '12345678K', '2026-02-01');
reset role;
do $$
begin
  if not exists (select 1 from cuotas_privado.vecinos where id = 1 and inicio = '2026-02-01') then
    raise exception 'Un pago anulado bloqueó la corrección del inicio';
  end if;
end;
$$;
rollback;
