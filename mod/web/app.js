const el = (id) => document.getElementById(id);

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

async function postJson(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

function pretty(v) {
  return JSON.stringify(v, null, 2);
}

function parseJsonInput(raw, fallback) {
  const text = (raw || '').trim();
  if (!text) return fallback;
  return JSON.parse(text);
}

async function refresh() {
  try {
    const [health, state, legal, history] = await Promise.all([
      getJson('/health'),
      getJson('/state'),
      getJson('/legal_actions'),
      getJson('/action_history?limit=20'),
    ]);

    el('health').textContent = `status=${health.status} paused=${health.paused}`;
    el('phase').textContent = pretty({
      phase: state.phase,
      turn_index: state.turn_index,
      action_points: state.action_points,
      blind: state.blind,
    });
    el('resources').textContent = pretty(state.resources || {});
    el('hand').textContent = pretty(state.hand || []);
    el('jokers').textContent = pretty(state.jokers || []);
    el('shop').textContent = pretty(state.shop || {});
    el('legal-actions').textContent = pretty(legal.actions || []);
    el('history').textContent = pretty(history.history || []);
  } catch (err) {
    el('health').textContent = `error: ${String(err)}`;
  }
}

async function executeAction() {
  const actionType = el('action-type').value.trim();
  const paramsRaw = el('action-params').value.trim();
  let params = {};
  if (paramsRaw) {
    params = JSON.parse(paramsRaw);
  }
  const result = await postJson('/execute_action', {
    action_type: actionType,
    params,
  });
  el('action-result').textContent = pretty(result);
  await refresh();
}

async function quick(url) {
  const result = await postJson(url, {});
  el('action-result').textContent = pretty(result);
  await refresh();
}

el('btn-execute').addEventListener('click', async () => {
  try {
    await executeAction();
  } catch (err) {
    el('action-result').textContent = String(err);
  }
});

el('btn-pause').addEventListener('click', async () => {
  try { await quick('/pause_control'); } catch (err) { el('action-result').textContent = String(err); }
});

el('btn-resume').addEventListener('click', async () => {
  try { await quick('/resume_control'); } catch (err) { el('action-result').textContent = String(err); }
});

el('btn-refresh').addEventListener('click', async () => {
  try { await quick('/request_snapshot'); } catch (err) { el('action-result').textContent = String(err); }
});
refresh();
setInterval(refresh, 500);
