const statusNode = document.querySelector('#status');
const saveButton = document.querySelector('#save');
const syncButton = document.querySelector('#sync');
function status(text, state = '') { statusNode.textContent = text; statusNode.dataset.state = state; }
function busy(value) { saveButton.disabled = value; syncButton.disabled = value; }
async function show() {
  const data = await chrome.storage.local.get(['token', 'status']);
  document.querySelector('#token').value = data.token || '';
  const text = data.status || '尚未配对，请先填写桌面程序的配对码。';
  status(text, text.startsWith('同步成功') ? 'success' : '');
}
async function sync() {
  busy(true); status('正在连接桌面程序并同步历史…', 'pending');
  try {
    const response = await chrome.runtime.sendMessage({kind: 'sync'});
    if (!response?.ok) status(response?.error || '未收到同步结果，请重试。', 'error');
    else await show();
  } catch (e) { status(e.message, 'error'); }
  finally { busy(false); }
}
document.querySelector('#pair-form').addEventListener('submit', async event => {
  event.preventDefault();
  const token = document.querySelector('#token').value.trim();
  if (token.length < 32) { status('请粘贴完整的桌面程序配对码。', 'error'); return; }
  try { await chrome.storage.local.set({token}); await sync(); }
  catch (e) { status(e.message, 'error'); busy(false); }
});
syncButton.addEventListener('click', sync);
show().catch(e => status(e.message, 'error'));
