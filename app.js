'use strict';

const SUPABASE_URL = 'https://xzjootgfnstlxxdumhsl.supabase.co';
const SUPABASE_KEY = 'sb_publishable_4xGqOhRfPpMpyAUbgjuOUQ_QxYwdWo1';
const $ = (selector) => document.querySelector(selector);
const message = $('#message');
const yearInput = $('#year');
const yearTableInput = $('#year-table');
const money = new Intl.NumberFormat('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 });
const monthNames = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
let session = null;
let refreshPromise = null;
let loadVersion = 0;
let editingNeighbor = null;
let neighbors = [];
let historyVersion = 0;

function showMessage(text, error = false) {
  message.textContent = text;
  message.classList.toggle('error', error);
  message.hidden = false;
}

function setAuthenticated(authenticated) {
  $('#login-section').hidden = authenticated;
  $('#app').hidden = !authenticated;
  $('#logout').hidden = !authenticated;
  if (!authenticated) {
    loadVersion++;
    showView('dashboard');
    $('#portal-password-form').reset();
    resetNeighborForm();
    $('#neighbors-list').replaceChildren();
    $('#neighbors-empty').hidden = true;
    $('#dues').replaceChildren();
    $('#payments').replaceChildren();
    neighbors = [];
    historyVersion++;
    $('#history-search').value = '';
    $('#history-neighbor').replaceChildren(new Option('Selecciona un vecino', ''));
    $('#history-status').textContent = 'Selecciona un vecino para ver sus pagos.';
    $('#payment-form').elements.vecino.replaceChildren();
    $('#year-info').textContent = '';
    $('#summary-neighbors').textContent = '—';
    $('#summary-paid').textContent = '—';
    $('#summary-debt').textContent = '—';
    $('#summary-info').textContent = '';
  }
}

function showView(name) {
  for (const view of document.querySelectorAll('.view')) {
    view.hidden = view.id !== `view-${name}`;
  }
  for (const button of document.querySelectorAll('#treasury-menu [data-view]')) {
    const active = button.dataset.view === name;
    button.classList.toggle('active', active);
    if (active) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  }
}

async function request(path, body, token) {
  const headers = { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  let response;
  try {
    response = await fetch(`${SUPABASE_URL}${path}`, {
      method: 'POST', headers, body: JSON.stringify(body)
    });
  } catch {
    throw new Error('No se pudo confirmar la operación. Revisa la conexión y verifica el resultado antes de intentarlo nuevamente.');
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
    error.code = data?.code;
    throw error;
  }
  return data;
}

function rememberSession(data) {
  if (!data?.access_token || !data?.refresh_token || !data?.expires_in) {
    throw new Error('La respuesta de autenticación no contiene una sesión válida.');
  }
  session = { access: data.access_token, refresh: data.refresh_token, expires: Date.now() + data.expires_in * 1000 };
}

async function accessToken() {
  if (!session) throw new Error('Inicia sesión nuevamente.');
  if (Date.now() < session.expires - 60000) return session.access;
  if (!refreshPromise) {
    const previous = session;
    refreshPromise = request('/auth/v1/token?grant_type=refresh_token', { refresh_token: previous.refresh })
      .then((data) => {
        if (session !== previous) throw new Error('La sesión terminó.');
        rememberSession(data);
        return session.access;
      })
      .catch(() => {
        session = null;
        setAuthenticated(false);
        throw new Error('La sesión venció. Inicia sesión nuevamente.');
      })
      .finally(() => { refreshPromise = null; });
  }
  return refreshPromise;
}

async function rpc(name, parameters) {
  return request(`/rest/v1/rpc/${name}`, parameters, await accessToken());
}

function cell(row, value) {
  const td = document.createElement('td');
  td.textContent = value;
  row.append(td);
  return td;
}

function validRut(value) {
  const formatted = value.toUpperCase().replace(/\s/g, '');
  if (!/^(\d{1,8}|\d{1,3}\.\d{3}|\d{1,2}\.\d{3}\.\d{3})-?[\dK]$/.test(formatted)) return false;
  const normalized = formatted.replace(/[.-]/g, '');
  const body = normalized.slice(0, -1);
  if (Number(body) === 0) return false;
  let sum = 0;
  for (let i = 0; i < body.length; i++) {
    sum += Number(body[body.length - 1 - i]) * (2 + i % 6);
  }
  const digit = (11 - sum % 11) % 11;
  return normalized.at(-1) === (digit === 10 ? 'K' : String(digit));
}

function resetNeighborForm() {
  editingNeighbor = null;
  $('#neighbor-form').reset();
  $('#neighbor-form-title').textContent = 'Agregar vecino';
  $('#neighbor-submit').textContent = 'Guardar vecino';
  $('#neighbor-cancel').hidden = true;
}

function editNeighbor(neighbor) {
  editingNeighbor = { id: neighbor.id, inicio: neighbor.inicio.slice(0, 7) };
  const form = $('#neighbor-form');
  form.elements.nombre.value = neighbor.nombre;
  form.elements.rut.value = neighbor.rut;
  form.elements.inicio.value = editingNeighbor.inicio;
  $('#neighbor-form-title').textContent = 'Modificar vecino';
  $('#neighbor-submit').textContent = 'Guardar cambios';
  $('#neighbor-cancel').hidden = false;
  message.hidden = true;
  form.elements.nombre.focus();
}

function updateHistoryOptions(preserveSelection = false) {
  const select = $('#history-neighbor');
  const selected = preserveSelection ? select.value : '';
  const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es-CL');
  const search = normalize($('#history-search').value.trim());
  const matching = neighbors.filter(neighbor => normalize(neighbor.nombre).includes(search) || String(neighbor.id) === selected);
  select.replaceChildren(new Option(matching.length ? 'Selecciona un vecino' : 'No hay vecinos que coincidan', ''));
  for (const neighbor of matching) {
    select.add(new Option(`${neighbor.nombre} · ${neighbor.rut}`, String(neighbor.id)));
  }
  select.value = matching.some(neighbor => String(neighbor.id) === selected) ? selected : '';
}

async function loadHistory() {
  const selected = $('#history-neighbor').value;
  const version = ++historyVersion;
  const activeSession = session;
  $('#payments').replaceChildren();
  if (!selected || !activeSession) {
    $('#history-status').textContent = 'Selecciona un vecino para ver sus pagos.';
    return;
  }
  $('#history-status').textContent = 'Cargando pagos…';
  try {
    const data = await rpc('cuotas_historial_vecino', { p_vecino: Number(selected) });
    if (version !== historyVersion || session !== activeSession) return;
    const neighbor = neighbors.find(item => String(item.id) === selected);
    for (const payment of data) {
      const row = document.createElement('tr');
      const [year, month, day] = payment.fecha.split('-');
      cell(row, `${day}/${month}/${year}`);
      cell(row, payment.comprobante || '—');
      cell(row, neighbor.nombre);
      cell(row, money.format(payment.monto));
      cell(row, payment.aplicaciones.map(item => `${item.mes.slice(5, 7)}/${item.mes.slice(0, 4)}: ${money.format(item.monto)}`).join(', '));
      cell(row, payment.anulado_en ? `Anulado: ${payment.motivo_anulacion}` : 'Registrado');
      const action = cell(row, '');
      if (!payment.anulado_en) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'danger';
        button.textContent = 'Anular';
        button.addEventListener('click', () => cancelPayment(payment.id, button));
        action.append(button);
      }
      $('#payments').append(row);
    }
    $('#history-status').textContent = data.length ? `Pagos de ${neighbor.nombre}.` : `No hay pagos registrados para ${neighbor.nombre}.`;
  } catch (error) {
    if (version !== historyVersion || session !== activeSession) return;
    $('#payments').replaceChildren();
    $('#history-status').textContent = error.code === 'PGRST202'
      ? 'Para habilitar el historial, ejecuta supabase/historial_vecino.sql en Supabase.'
      : `No se pudo cargar el historial: ${error.message}`;
  }
}

function render(data) {
  const select = $('#payment-form').elements.vecino;
  const selected = select.value;
  const historySelected = $('#history-neighbor').value;
  select.replaceChildren(new Option('Selecciona un vecino', ''));
  neighbors = data.vecinos;
  const neighborsList = $('#neighbors-list');
  neighborsList.replaceChildren();
  $('#neighbors-empty').hidden = data.vecinos.length > 0;
  for (const neighbor of data.vecinos) {
    select.add(new Option(`${neighbor.nombre} · ${neighbor.rut}`, neighbor.id));
    const row = document.createElement('tr');
    cell(row, neighbor.nombre);
    cell(row, neighbor.rut);
    cell(row, `${monthNames[Number(neighbor.inicio.slice(5, 7)) - 1]} ${neighbor.inicio.slice(0, 4)}`);
    const action = cell(row, '');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'outline';
    button.textContent = '✎ Modificar';
    button.setAttribute('aria-label', `Modificar a ${neighbor.nombre}`);
    button.addEventListener('click', () => editNeighbor(neighbor));
    action.append(button);
    neighborsList.append(row);
  }
  select.value = [...select.options].some(option => option.value === selected) ? selected : '';
  updateHistoryOptions(true);
  if (historySelected && !$('#history-neighbor').value) loadHistory();

  const dues = $('#dues');
  dues.replaceChildren();
  let total = 0;
  let paidTotal = 0;
  let unconfigured = false;
  for (const due of data.cuotas) {
    const neighbor = data.vecinos.find(item => item.id === due.vecino_id);
    const row = document.createElement('tr');
    const balance = due.monto === null ? null : Math.max(due.monto - due.pagado, 0);
    if (balance !== null) total += balance;
    else unconfigured = true;
    paidTotal += Number(due.pagado) || 0;
    cell(row, neighbor.nombre);
    cell(row, neighbor.rut);
    cell(row, monthNames[Number(due.mes.slice(5, 7)) - 1]);
    cell(row, due.monto === null ? 'Sin configurar' : money.format(due.monto));
    cell(row, money.format(due.pagado));
    cell(row, balance === null ? '—' : money.format(balance));
    cell(row, balance === null ? 'Sin configurar' : balance === 0 ? 'Pagada' : due.pagado > 0 ? 'Parcial' : 'Pendiente');
    dues.append(row);
  }
  const fee = data.aranceles.find(item => item.anio === Number(yearInput.value));
  $('#summary-neighbors').textContent = String(data.vecinos.length);
  $('#summary-paid').textContent = money.format(paidTotal);
  $('#summary-debt').textContent = money.format(total);
  $('#summary-info').textContent = unconfigured
    ? `Resumen de ${yearInput.value}. Hay cuotas sin monto configurado; la deuda mostrada no las incluye.`
    : `Resumen de ${yearInput.value}. Los montos pagados corresponden a cuotas aplicadas a ese año.`;
  yearTableInput.value = yearInput.value;
  $('#year-info').textContent = fee
    ? `Cuota mensual: ${money.format(fee.monto)}. Saldo del año completo (incluye meses futuros): ${money.format(total)}.`
    : 'No se ha configurado la cuota mensual para este año.';

}

async function load() {
  if (!yearInput.reportValidity()) return;
  const version = ++loadVersion;
  const data = await rpc('cuotas_datos', { p_anio: Number(yearInput.value) });
  if (version === loadVersion && session) render(data);
}

async function withBusy(form, operation) {
  const button = form.querySelector('button[type="submit"]');
  button.disabled = true;
  message.hidden = true;
  try {
    await operation();
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    button.disabled = false;
  }
}

async function updateAfterSave(text) {
  try {
    await load();
    if ($('#history-neighbor').value) await loadHistory();
    showMessage(text);
  } catch (error) {
    showMessage(`${text} No se pudo actualizar la pantalla: ${error.message}`, true);
  }
}

$('#login-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  withBusy(form, async () => {
    const credentials = { email: form.elements.email.value.trim(), password: form.elements.password.value };
    const data = await request('/auth/v1/token?grant_type=password', credentials);
    rememberSession(data);
    form.elements.password.value = '';
    try {
      await load();
    } catch (error) {
      session = null;
      setAuthenticated(false);
      throw error;
    }
    setAuthenticated(true);
    showView('dashboard');
    showMessage('Sesión iniciada.');
  });
});

$('#treasury-menu').addEventListener('click', event => {
  const button = event.target.closest('[data-view]');
  if (button) showView(button.dataset.view);
});

$('#history-search').addEventListener('input', () => {
  updateHistoryOptions();
  loadHistory();
});
$('#history-neighbor').addEventListener('change', () => {
  loadHistory();
});

$('#logout').addEventListener('click', async () => {
  const previous = session;
  session = null;
  setAuthenticated(false);
  message.hidden = true;
  if (!previous) return;
  try {
    await request('/auth/v1/logout', {}, previous.access);
    showMessage('Sesión cerrada.');
  } catch (error) {
    showMessage(`La sesión se cerró en esta página, pero no se pudo cerrar en el servidor: ${error.message}`, true);
  }
});

$('#neighbor-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  if (!validRut(form.elements.rut.value)) {
    showMessage('Ingresa un RUT válido con su dígito verificador.', true);
    form.elements.rut.focus();
    return;
  }
  const neighbor = editingNeighbor;
  if (neighbor && form.elements.inicio.value !== neighbor.inicio
    && !confirm('Cambiar el mes de inicio puede modificar la deuda. Los pagos existentes no se reasignarán. ¿Continuar?')) return;
  withBusy(form, async () => {
    const parameters = {
      p_nombre: form.elements.nombre.value.trim(), p_rut: form.elements.rut.value.trim(),
      p_inicio: `${form.elements.inicio.value}-01`
    };
    if (neighbor) {
      try {
        await rpc('cuotas_editar_vecino', { p_vecino: neighbor.id, ...parameters });
      } catch (error) {
        if (error.code === 'PGRST202') {
          throw new Error('Para habilitar la modificación, ejecuta supabase/editar_vecinos.sql en Supabase.');
        }
        throw error;
      }
    } else {
      await rpc('cuotas_crear_vecino', parameters);
    }
    resetNeighborForm();
    await updateAfterSave(neighbor ? 'Datos del vecino modificados.' : 'Vecino agregado.');
  });
});

$('#neighbor-cancel').addEventListener('click', () => {
  resetNeighborForm();
  message.hidden = true;
  $('#neighbor-form').elements.nombre.focus();
});

$('#fee-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  withBusy(form, async () => {
    await rpc('cuotas_guardar_arancel', { p_anio: Number(form.elements.anio.value), p_monto: Number(form.elements.monto.value) });
    yearInput.value = form.elements.anio.value;
    yearTableInput.value = yearInput.value;
    await updateAfterSave('Monto anual guardado.');
  });
});

$('#portal-password-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  withBusy(form, async () => {
    const password = form.elements.password.value;
    if (password !== form.elements.confirmation.value) {
      throw new Error('Las claves no coinciden.');
    }
    if (new TextEncoder().encode(password).length > 72) {
      throw new Error('La clave es demasiado larga. Usa un máximo de 72 bytes.');
    }
    await rpc('cuotas_cambiar_clave_portal', { p_clave: password });
    form.reset();
    showMessage('Clave común cambiada. Comunícala a los vecinos.');
  });
});

$('#payment-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  withBusy(form, async () => {
    await rpc('cuotas_registrar_pago', {
      p_vecino: Number(form.elements.vecino.value), p_monto: Number(form.elements.monto.value),
      p_fecha: form.elements.fecha.value, p_comprobante: form.elements.comprobante.value
    });
    form.elements.monto.value = '';
    form.elements.comprobante.value = '';
    await updateAfterSave('Pago registrado.');
  });
});

async function cancelPayment(id, button) {
  const reason = prompt('Indica el motivo de la anulación:');
  if (reason === null) return;
  if (!reason.trim()) { showMessage('Debes indicar un motivo de anulación.', true); return; }
  button.disabled = true;
  try {
    await rpc('cuotas_anular_pago', { p_pago: id, p_motivo: reason });
    await updateAfterSave('Pago anulado.');
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    button.disabled = false;
  }
}

function changeYear(value) {
  yearInput.value = value;
  yearTableInput.value = value;
  load().catch(error => showMessage(error.message, true));
}

yearInput.addEventListener('change', () => changeYear(yearInput.value));
yearTableInput.addEventListener('change', () => changeYear(yearTableInput.value));
const today = new Date();
yearInput.value = today.getFullYear();
yearTableInput.value = today.getFullYear();
$('#fee-form').elements.anio.value = today.getFullYear();
$('#payment-form').elements.fecha.value = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
