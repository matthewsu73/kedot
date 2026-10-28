const TARGET = 'http://127.0.0.1:8765';
function validUrl(url) {
  try { const u = new URL(url); return u.protocol==='https:' && ['www.bilibili.com','bilibili.com'].includes(u.hostname) && !u.port && !u.username && /^\/video\/BV[0-9A-Za-z]{10}\/?$/.test(u.pathname); } catch { return false; }
}
const queue = new Map();
let token, retryAt=0, failures=0, pump=null, lastStatusAt=0, lastStatus='', lastOfflineAt=0, historyAt=0;
const ready = chrome.storage.local.get(['token','pendingProgress','lastHistorySync','status']).then(data=>{
  token=data.token; historyAt=data.lastHistorySync || 0; lastStatus=data.status || '';
  for(const record of Object.values(data.pendingProgress || {}).slice(-50)) {
    if (['/progress','/metadata'].includes(record?.path) && validUrl(record.body?.url)) queue.set(record.path+record.body.url,record);
  }
  if(queue.size) lastOfflineAt=1;
});
chrome.storage.onChanged.addListener((changes,area)=>{ if(area==='local' && changes.token) { token=changes.token.newValue; retryAt=0; } });
async function status(text, success=false) {
  const now=Date.now();
  if (success && lastStatus.startsWith('同步成功') && now-lastStatusAt<30000) return;
  if (!success && text===lastStatus) return;
  lastStatus=text; lastStatusAt=now; await chrome.storage.local.set({status:text});
}
async function request(path,body) {
  await ready;
  if(!token) throw new Error('请先填写桌面程序的配对码');
  const control=new AbortController(); const timer=setTimeout(()=>control.abort(),3000);
  try {
    const response=await fetch(TARGET+path,{method:'POST',signal:control.signal,headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify(body)});
    if(!response.ok) throw new Error('同步失败 HTTP '+response.status+'（401 表示配对码错误）');
    const result=await response.json(); failures=0; retryAt=0;
    await status('同步成功 '+new Date().toLocaleString(),true); return result;
  } finally { clearTimeout(timer); }
}
async function persistQueue(force=false) {
  if(!force && Date.now()-lastOfflineAt<15000) return;
  lastOfflineAt=Date.now(); await chrome.storage.local.set({pendingProgress:Object.fromEntries(queue)});
}
async function drain(force=false) {
  await ready;
  if(pump) return pump;
  if(!force && Date.now()<retryAt) return {ok:false,queued:true,error:'桌面暂未连接，已缓存进度'};
  pump=(async()=>{
    let result={ok:true};
    try {
      while(queue.size) {
        const [key,record]=queue.entries().next().value;
        result=await request(record.path,record.body);
        if(queue.get(key)===record) queue.delete(key);
      }
      // Clear a previously persisted offline queue only after it has been delivered.
      if(lastOfflineAt) { await chrome.storage.local.set({pendingProgress:{}}); lastOfflineAt=0; }
      return result;
    } catch(error) {
      failures++; retryAt=Date.now()+Math.min(60000,5000*2**Math.min(failures-1,4));
      await persistQueue(true); await status(String(error.message));
      return {ok:false,queued:true,error:error.message};
    }
  })();
  try { return await pump; } finally { pump=null; }
}
async function sendRecord(path,body) {
  await ready;
  queue.set(path+body.url,{path,body});
  while(queue.size>50) queue.delete(queue.keys().next().value);
  const urgent=body.deferSave!==true;
  if(Date.now()<retryAt) { await persistQueue(urgent); return {ok:false,queued:true,error:'桌面暂未连接，已缓存进度'}; }
  return drain();
}
async function syncHistory(force=true) {
  await ready;
  if(force) retryAt=0;
  await drain(force);
  try {
    const result=await chrome.history.search({text:'bilibili.com/video/',maxResults:500,startTime:0});
    const response=await request('/history',{items:result.filter(x=>validUrl(x.url)).map(x=>({url:x.url,title:x.title || ''}))});
    historyAt=Date.now(); await chrome.storage.local.set({lastHistorySync:historyAt}); return response;
  } catch(error) { await status(String(error.message)); throw error; }
}
async function start() {
  chrome.alarms.create('sync',{periodInMinutes:5}); await ready;
  if(Date.now()-historyAt>1800000) await syncHistory(false).catch(()=>{}); else await drain();
}
chrome.runtime.onInstalled.addListener(start); chrome.runtime.onStartup.addListener(start);
chrome.alarms.onAlarm.addListener(async alarm=>{
  if(alarm.name!=='sync') return;
  await ready; await drain(true);
  if(Date.now()-historyAt>1800000) await syncHistory(false).catch(()=>{});
});
chrome.history.onVisited.addListener(item=>{
  if(validUrl(item.url)) request('/history',{items:[{url:item.url,title:item.title || ''}]}).catch(error=>status(error.message));
});
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
  if(sender.id!==chrome.runtime.id) return false;
  if(message.kind==='sync' && !sender.tab) {
    syncHistory().then(()=>respond({ok:true}),error=>respond({error:error.message}));return true;
  }
  if(['progress','metadata'].includes(message.kind) && sender.tab && validUrl(sender.url) && validUrl(message.payload?.url)) {
    if(new URL(sender.url).pathname!==new URL(message.payload.url).pathname) return false;
    sendRecord(message.kind==='progress'?'/progress':'/metadata',message.payload).then(respond,error=>respond({error:error.message}));return true;
  }
  return false;
});
chrome.action.onClicked.addListener(()=>chrome.runtime.openOptionsPage().catch(()=>{}));
