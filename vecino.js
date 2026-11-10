'use strict';

const SUPABASE_URL = 'https://xzjootgfnstlxxdumhsl.supabase.co';
const SUPABASE_KEY = 'sb_publishable_4xGqOhRfPpMpyAUbgjuOUQ_QxYwdWo1';
const $ = selector => document.querySelector(selector);
const message = $('#message');
const yearSelect = $('#year');
const money = new Intl.NumberFormat('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 });
const monthNames = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
let session = null;
let requestVersion = 0;

function showMessage(text, error = false) {
  message.textContent = text;
  message.classList.toggle('error', error);
  message.hidden = false;
}

function signedOut() {
  requestVersion++;
  session = null;
  $('#login-section').hidden = false;
  $('#account').hidden = true;
  $('#logout').hidden = true;
  $('#welcome').textContent = '';
  $('#status').textContent = '';
  $('#balance').textContent = '';
  $('#dues').replaceChildren();
  $('#payments').replaceChildren();
  yearSelect.replaceChildren();
}

async function request(path, body) {
  const headers = { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' };
  let response;
  try {
    response = await fetch(`${SUPABASE_URL}${path}`, { method: 'POST', headers, body: JSON.stringify(body), cache: 'no-store' });
  } catch {
    throw new Error('No se pudo confirmar la operación. Revisa tu conexión.');
  }
  const text = await response.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    throw new Error('El servidor devolvió una respuesta inesperada.');
  }
  if (!response.ok) {
    const error = new Error(data?.msg || data?.message || data?.error_description || `Error del servidor (${response.status}).`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function loadYear(year, expectedSession) {
  const version = ++requestVersion;
  const data = await request('/rest/v1/rpc/vecino_mis_cuotas', {
    p_anio: year, p_rut: expectedSession.rut, p_clave: expectedSession.password
  });
  if (version !== requestVersion || session !== expectedSession) return;
  if (data?.error) {
    const error = new Error(data.error);
    error.code = data.codigo;
    throw error;
  }
  const currentYear = Number(data.anio_actual);
  yearSelect.replaceChildren();
  for (let yearOption = Number(data.anio_inicio); yearOption <= currentYear; yearOption++) {
    yearSelect.add(new Option(String(yearOption), String(yearOption)));
  }
  yearSelect.value = String(year);
  $('#welcome').textContent = `Hola, ${data.vecino.nombre}`;
  $('#status').textContent = data.configuracion_completa
    ? data.deuda_hasta_hoy === 0 ? 'Estado: Al día' : 'Estado: Pendiente'
    : 'Estado: Pendiente · Hay cuotas anuales sin monto configurado. Contacta a la directiva.';
  $('#status').classList.toggle('overdue', !data.configuracion_completa || data.deuda_hasta_hoy > 0);
  $('#balance').textContent = data.configuracion_completa
    ? data.deuda_hasta_hoy === 0
      ? 'No tienes cuotas pendientes hasta el mes actual.'
      : `Saldo pendiente hasta ${monthNames[Number(data.mes_actual.slice(5, 7)) - 1]} ${data.mes_actual.slice(0, 4)}: ${money.format(data.deuda_hasta_hoy)}.`
    : 'No es posible calcular el saldo completo mientras haya cuotas anuales sin configurar.';

  const dues = $('#dues');
  dues.replaceChildren();
  for (const due of data.cuotas) {
    const row = document.createElement('tr');
    const balance = due.monto === null ? null : due.monto - due.pagado;
    for (const value of [
      monthNames[Number(due.mes.slice(5, 7)) - 1],
      due.monto === null ? 'Sin configurar' : money.format(due.monto),
      money.format(due.pagado),
      balance === null ? '—' : money.format(balance),
      balance === null ? 'Sin configurar' : balance === 0 ? 'Pagada' : due.pagado > 0 ? 'Parcial' : 'Pendiente'
    ]) {
      const cell = document.createElement('td');
      cell.textContent = value;
      row.append(cell);
    }
    dues.append(row);
  }

  const payments = $('#payments');
  payments.replaceChildren();
  for (const payment of data.pagos) {
    const row = document.createElement('tr');
    const values = [
      payment.fecha,
      money.format(payment.monto),
      payment.aplicaciones.map(item => `${item.mes.slice(0, 7)}: ${money.format(item.monto)}`).join(', '),
      payment.anulado_en ? `Anulado: ${payment.motivo_anulacion}` : 'Registrado'
    ];
    for (const value of values) {
      const cell = document.createElement('td');
      cell.textContent = value;
      row.append(cell);
    }
    payments.append(row);
  }
}

$('#login-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector('button');
  const rut = form.elements.rut.value.trim().toUpperCase().replace(/[^0-9K]/g, '');
  const password = form.elements.password.value;
  if (!/^[0-9]{1,8}[0-9K]$/.test(rut)) {
    showMessage('Ingresa un RUT válido.', true);
    return;
  }
  button.disabled = true;
  message.hidden = true;
  (async () => {
    try {
      session = { rut, password };
      form.elements.password.value = '';
      const activeSession = session;
      await loadYear(new Date().getFullYear(), activeSession);
      if (session !== activeSession) return;
      $('#login-section').hidden = true;
      $('#account').hidden = false;
      $('#logout').hidden = false;
    } catch (error) {
      showMessage(error.message, true);
      if (session) signedOut();
    } finally {
      button.disabled = false;
    }
  })();
});

$('#logout').addEventListener('click', () => {
  signedOut();
  showMessage('Sesión cerrada.');
});

yearSelect.addEventListener('change', () => {
  if (!session) return;
  const activeSession = session;
  loadYear(Number(yearSelect.value), activeSession).catch(error => {
    if (error.code === 'credenciales') signedOut();
    showMessage(error.message, true);
  });
});
