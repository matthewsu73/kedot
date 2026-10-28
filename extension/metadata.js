// MAIN-world bridge: only reads public course metadata, never tokens or Chrome APIs.
(() => {
  function publish(kind = 'metadata') {
    const match = location.pathname.match(/^\/video\/(BV[0-9A-Za-z]{10})/);
    if (!match) return;
    const state = window.__INITIAL_STATE__;
    const data = state?.videoData;
    const message = {source:'bili-widget-v22', kind, url:location.href};
    if (data?.bvid === match[1] && Array.isArray(data.pages) && data.pages.length > 0) {
      message.metadata = {url:location.href, courseTitle:String(data.title || '').slice(0,200),
        totalParts:data.pages.length, parts:data.pages.slice(0,1000).map(x=>({page:Number(x.page), title:String(x.part || '').slice(0,120), duration:Number(x.duration) || 0}))};
    }
    window.postMessage(message, location.origin);
  }
  window.addEventListener('bili-widget-request',()=>publish());
  for (const name of ['pushState','replaceState']) {
    const original = history[name];
    history[name] = function(...args) { const result = Reflect.apply(original,this,args); publish('navigation'); return result; };
  }
  window.addEventListener('popstate',()=>publish('navigation'));
})();
