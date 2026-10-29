(() => {
  let video = null, bindings = null, lastUrl = '', ready = false, lastAt = -Infinity;
  let lastSeconds = -1, lastDuration = -1, lastReason = '', metadataKey = '', lowPower = false;
  let sourceAtNavigation = '';
  const requestMetadata = () => window.dispatchEvent(new Event('bili-widget-request'));
  function route() {
    if (lastUrl === location.href) return false;
    lastUrl = location.href; ready = false; lastAt = -Infinity; lastSeconds = -1; metadataKey = '';
    sourceAtNavigation = video?.currentSrc || '';
    requestMetadata(); return true;
  }
  function send(force = false, reason = 'timeupdate') {
    const changed = route();
    if (!video || !video.isConnected) { bind(); return; }
    if (changed) return;
    if (!ready && video.currentSrc && video.currentSrc !== sourceAtNavigation) ready = true;
    if (!ready || !Number.isFinite(video.duration) || video.duration <= 0 || video.duration >= 86400 || !Number.isFinite(video.currentTime)) return;
    if (!force && (video.paused || video.ended)) return;
    const now = Date.now();
    const interval = document.hidden ? (lowPower ? 15000:10000) : (lowPower ? 5000:2000);
    if (!force && now-lastAt < interval) return;
    if (Math.abs(video.currentTime-lastSeconds)<0.25 && video.duration===lastDuration && (!force || reason===lastReason)) return;
    lastAt = now; lastSeconds = video.currentTime; lastDuration = video.duration; lastReason = reason;
    chrome.runtime.sendMessage({kind:'progress',payload:{url:location.href,title:document.title,seconds:video.currentTime,
      duration:video.duration, playbackRate:video.playbackRate, reason, deferSave:!force}}).then(result=>{
        if (result?.lowPower !== undefined) lowPower = Boolean(result.lowPower);
      }).catch(()=>{});
  }
  function bind() {
    const candidate = document.querySelector('video');
    const first = !video && !lastUrl;
    route();
    if (candidate === video) return;
    bindings?.abort(); bindings = new AbortController(); video = candidate; ready = false;
    if (!video) return;
    const on = (name, fn) => video.addEventListener(name,fn,{signal:bindings.signal});
    const loaded = () => { route(); ready = true; requestMetadata(); send(true,'loaded'); };
    on('loadedmetadata',loaded); on('playing',()=>{ route(); ready=true; requestMetadata(); send(true,'playing'); });
    on('timeupdate',()=>send());
    for (const event of ['pause','ended','seeked','durationchange','ratechange']) on(event,()=>send(true,event));
    if (first && video.readyState>=1) { ready=true; send(true,'initial'); }
  }
  window.addEventListener('message',event=>{
    if (event.source!==window || event.origin!==location.origin || event.data?.source!=='bili-widget-v22') return;
    if (event.data.url!==location.href) return;
    if (event.data.kind==='navigation') { route(); bind(); }
    const metadata = event.data.metadata;
    if (!metadata || !Number.isInteger(metadata.totalParts) || metadata.totalParts<1 || metadata.totalParts>100000 || !Array.isArray(metadata.parts) || metadata.parts.length>1000) return;
    const bvid = location.pathname.split('/')[2];
    if (!metadata.url?.includes('/video/'+bvid)) return;
    const key = JSON.stringify(metadata);
    if (key===metadataKey) return;
    metadataKey=key;
    chrome.runtime.sendMessage({kind:'metadata',payload:metadata}).catch(()=>{});
  });
  const observer = new MutationObserver(()=>{ if (!video || !video.isConnected) bind(); });
  const observe = () => { if (document.body) observer.observe(document.body,{childList:true,subtree:true}); bind(); };
  document.addEventListener('visibilitychange',()=>{ send(true,'visibility'); if (!document.hidden) requestMetadata(); });
  window.addEventListener('pagehide',()=>{ send(true,'pagehide'); observer.disconnect(); });
  window.addEventListener('pageshow',observe);
  observe(); requestMetadata();
})();
