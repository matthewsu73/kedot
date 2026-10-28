const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const directory=path.join(__dirname,'..','extension');
const url='https://www.bilibili.com/video/BV1234567890?p=2';
function makeWorker(initial={}, fail=false) {
  const storage={token:process.env.TEST_TOKEN || 'x'.repeat(43),...initial}; const listeners={},calls=[],writes=[];
  const event=name=>({addListener:fn=>{listeners[name]=fn;}});
  let options=0,failed=fail;
  const chrome={action:{onClicked:event('action')},storage:{onChanged:event('storage'),local:{get:async()=>({...storage}),set:async value=>{writes.push(value);Object.assign(storage,value);}}},
    history:{search:async()=>[{url,title:'课程'},{url:'https://evil.com/video/BV1234567890'}],onVisited:event('visited')},
    runtime:{openOptionsPage:async()=>{options++;},id:'a'.repeat(32),onInstalled:event('installed'),onStartup:event('startup'),onMessage:event('message')},
    alarms:{create:()=>{},onAlarm:event('alarm')}};
  const context=vm.createContext({chrome,URL,Date,AbortController,setTimeout,clearTimeout,console,
    fetch:async(target,options)=>{calls.push({target,options});if(failed)throw new Error('offline');return process.env.TEST_TARGET?fetch(target,options):{ok:true,json:async()=>({ok:true,lowPower:false})};}});
  let code=fs.readFileSync(path.join(directory,'background.js'),'utf8');
  if(process.env.TEST_TARGET)code=code.replace('http://127.0.0.1:8765',process.env.TEST_TARGET);
  vm.runInContext(code,context);
  return {storage,listeners,calls,writes,context,chrome,setFailure:x=>{failed=x;},get options(){return options;}};
}
const sender={id:'a'.repeat(32),tab:{id:1},url};
function message(worker,kind,payload) {return new Promise(resolve=>assert.equal(worker.listeners.message({kind,payload},sender,resolve),true));}
class Target {
  constructor(){this.events={};}
  addEventListener(name,fn,options={}) {
    (this.events[name]??=[]).push(fn);
    options.signal?.addEventListener('abort',()=>{this.events[name]=(this.events[name] || []).filter(x=>x!==fn);});
  }
  dispatchEvent(event){for(const fn of [...(this.events[event.type] || [])])fn(event);return true;}
}
(async()=>{
 const worker=makeWorker();await vm.runInContext('syncHistory()',worker.context);
 assert.equal(JSON.parse(worker.calls[0].options.body).items.length,1);
 assert.equal(worker.calls[0].options.headers.Authorization,'Bearer '+worker.storage.token);
 const progress=await message(worker,'progress',{url,seconds:42,duration:100});assert.equal(progress.ok,true);
 const meta=await message(worker,'metadata',{url,courseTitle:'完整课程',totalParts:60,parts:[{page:1,title:'第一集',duration:100},{page:2,title:'第二集',duration:100}]});assert.equal(meta.ok,true);
 assert.equal(worker.listeners.message({kind:'progress',payload:{url}}, {...sender,id:'evil'},()=>{}),false);
 assert.equal(worker.listeners.message({kind:'progress',payload:{url:'https://evil.com'}},sender,()=>{}),false);
 assert.equal(worker.writes.filter(x=>x.status?.startsWith('同步成功')).length,1,'Do not write status on every playback tick');
 worker.listeners.action();await Promise.resolve();assert.equal(worker.options,1);
 delete worker.storage.token;worker.listeners.storage({token:{newValue:undefined}},'local');
 await assert.rejects(vm.runInContext('syncHistory()',worker.context));assert.match(worker.storage.status,/配对码/);
 const manifest=JSON.parse(fs.readFileSync(path.join(directory,'manifest.json')));
 for(const [size,file] of Object.entries(manifest.icons)){const png=fs.readFileSync(path.join(directory,file));assert.equal(png.readUInt32BE(16),Number(size));assert.equal(png.readUInt32BE(20),Number(size));}
 for(const file of [manifest.background.service_worker,manifest.options_page,...manifest.content_scripts.flatMap(x=>x.js)])assert.ok(fs.existsSync(path.join(directory,file)));
 assert.deepEqual(manifest.permissions.sort(),['alarms','history','storage']);
 assert.equal(manifest.content_scripts.find(x=>x.js.includes('metadata.js')).world,'MAIN');
 if(!process.env.TEST_TARGET) {
   const offline=makeWorker({},true);
   assert.equal((await message(offline,'progress',{url,seconds:1,duration:100,deferSave:true})).queued,true);
   for(let seconds=2;seconds<=20;seconds++)await message(offline,'progress',{url,seconds,duration:100,deferSave:true});
   assert.equal(offline.calls.length,1,'Backoff must avoid repeated network attempts while offline');
   await message(offline,'progress',{url,seconds:21,duration:100,deferSave:false});
   const pending=Object.values(offline.storage.pendingProgress);assert.equal(pending.length,1);assert.equal(pending[0].body.seconds,21);
   const restart=makeWorker(offline.storage,false);await vm.runInContext('drain(true)',restart.context);
   assert.equal(JSON.parse(restart.calls[0].options.body).seconds,21);assert.equal(Object.keys(restart.storage.pendingProgress).length,0);
 }
 // Event-driven content tracking: no interval is allowed in this fixture.
 let clock=100000,video=new Target();Object.assign(video,{duration:100,currentTime:20,readyState:4,isConnected:true,currentSrc:'media1',paused:false,ended:false});
 let power=false;
 const sent=[],win=new Target(),doc=new Target();Object.assign(doc,{querySelector:()=>video,body:{},title:'课程',hidden:false});
 const location={href:url,origin:'https://www.bilibili.com',pathname:'/video/BV1234567890'};
 const page=vm.createContext({document:doc,window:win,location,chrome:{runtime:{sendMessage:async value=>{sent.push(value);return {ok:true,lowPower:power};}}},
   AbortController,Event,MutationObserver:class{observe(){}disconnect(){}},Date:{now:()=>clock},Number,JSON,setInterval:()=>{throw new Error('Unexpected polling');}});
 vm.runInContext(fs.readFileSync(path.join(directory,'content.js'),'utf8'),page);assert.equal(sent.length,1);
 video.currentTime=21;clock+=1000;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,1);
 video.currentTime=22;clock+=1000;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,2);assert.equal(sent[1].payload.deferSave,true);
 video.paused=true;video.dispatchEvent(new Event('pause'));assert.equal(sent.length,3);assert.equal(sent[2].payload.deferSave,false,'Pause must flush even if position did not change');
 for(let i=0;i<100;i++){clock+=1000;video.dispatchEvent(new Event('timeupdate'));}assert.equal(sent.length,3,'Paused player must produce no polling uploads');
 doc.hidden=true;video.paused=false;doc.dispatchEvent(new Event('visibilitychange'));const hiddenCount=sent.length;
 clock+=3000;video.currentTime+=3;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,hiddenCount);
 clock+=10000;video.currentTime+=10;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,hiddenCount+1);
 location.href=url.replace('p=2','p=3');win.dispatchEvent({type:'message',source:win,origin:location.origin,data:{source:'bili-widget-v22',kind:'navigation',url:location.href}});
 const previous=sent.length;clock+=11000;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,previous,'Do not attribute old player to a new part');
 video.currentTime=0;video.dispatchEvent(new Event('loadedmetadata'));assert.equal(sent.at(-1).payload.seconds,0);assert.ok(sent.at(-1).payload.url.endsWith('p=3'));
 doc.hidden=false;power=true;clock+=3000;video.currentTime=3;video.dispatchEvent(new Event('timeupdate'));await Promise.resolve();
 const lowCount=sent.length;clock+=2000;video.currentTime=5;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,lowCount);
 clock+=3000;video.currentTime=8;video.dispatchEvent(new Event('timeupdate'));assert.equal(sent.length,lowCount+1,'Low power mode uses a five-second foreground interval');
 // Public metadata bridge uses full pages length, not maximum visited page.
 const bridge=new Target(),published=[];bridge.__INITIAL_STATE__={videoData:{bvid:'BV1234567890',title:'完整课程',pages:[{page:1,duration:100},{page:2,duration:100},{page:3,duration:100}]}};
 bridge.postMessage=value=>published.push(value);
 const main=vm.createContext({window:bridge,location,history:{pushState(){return 7;},replaceState(){}},Reflect,Number,String,Array});
 vm.runInContext(fs.readFileSync(path.join(directory,'metadata.js'),'utf8'),main);bridge.dispatchEvent(new Event('bili-widget-request'));
 assert.equal(published[0].metadata.totalParts,3);assert.equal(vm.runInContext('history.pushState()',main),7);
 bridge.__INITIAL_STATE__.videoData.bvid='BV0000000000';bridge.dispatchEvent(new Event('bili-widget-request'));assert.equal(published.at(-1).metadata,undefined);
 console.log('PASS: worker auth/routing, metadata, status throttling, offline coalescing/recovery; event-driven content, pause flush, paused idle, hidden throttle, SPA isolation; '+(process.env.TEST_TARGET?'real HTTP':'mock HTTP'));
})().catch(error=>{console.error(error);process.exitCode=1;});
