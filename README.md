# Control de cuotas

Aplicación para la tesorería de una junta de vecinos. Se accede con usuarios de
Supabase Auth autorizados expresamente. Los datos se guardan en tablas privadas
y solo se accede a ellos mediante las funciones autorizadas.

## Instalación inicial

1. En Supabase, abre **SQL Editor**, copia y ejecuta `supabase/cuotas.sql` una
   sola vez. Es una instalación nueva: no borra ni importa la tabla de prueba
   `tbl_personas`.
2. En **Authentication > Users**, crea un usuario con correo y contraseña
   para cada persona de tesorería. Desactiva el registro público de usuarios
   en la configuración de autenticación.
3. En **SQL Editor**, autoriza cada usuario cambiando el correo en la siguiente
   consulta. La respuesta debe indicar una fila insertada; si indica cero,
   comprueba que el correo y el usuario existen.

   ```sql
   insert into cuotas_privado.autorizados (usuario_id)
   select id from auth.users where email = 'correo@ejemplo.cl'
   on conflict do nothing;
   ```

4. Abre la página publicada e inicia sesión con ese usuario. Configura la cuota
   mensual para cada año necesario, registra los vecinos con su mes de inicio
   y registra los pagos.

Para quitar acceso a un usuario, elimina su fila de `cuotas_privado.autorizados`
desde el SQL Editor. No expongas contraseñas ni claves `service_role` o secretas.
Revisa las políticas de la antigua tabla `tbl_personas` por separado: este
script no las modifica.

## Funcionamiento

- Los importes son pesos chilenos enteros. Cada año tiene una cuota mensual
  común. No se puede modificar un monto anual si existen aplicaciones de pagos
  para ese año, incluso si esos pagos fueron anulados.
- Los pagos parciales o adelantados se aplican a las cuotas pendientes más
  antiguas desde el mes de inicio. Si faltan años o el monto excede las cuotas
  configuradas, se rechaza el pago completo; no se guarda saldo a favor.
- Al anular un pago se conserva su historial y se liberan sus aplicaciones;
  las aplicaciones de otros pagos no se reasignan. El siguiente pago cubre
  primero las cuotas que vuelvan a quedar pendientes.
- El saldo mostrado corresponde al año completo, incluidos meses futuros.
  Los pagos aparecen en el año de su fecha y en los años a cuyas cuotas fueron
  aplicados. Cada sesión se mantiene solo en memoria de la página.