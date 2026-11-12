// 心臓人狼のサービスワーカー：オフラインでもCPU戦を遊べるようにする
// ページ本体はネット優先（更新がすぐ届く）、絵や音などは保存したものを先に使い、裏で新しくする
const CACHE='sj-v1';
const CORE=['./','./index.html','./manifest.webmanifest','./icons/icon-192.png','./icons/icon-512.png','./icons/apple-touch-icon.png',
  './scenes/back.png','./scenes/home_a.png','./scenes/home_b.png','./scenes/win.png','./scenes/lose.png','./scenes/pack.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const req=e.request;if(req.method!=='GET')return;
  const url=new URL(req.url);
  const same=url.origin===location.origin,font=/fonts\.(googleapis|gstatic)\.com$/.test(url.hostname);
  if(!same&&!font)return; // ログインや対戦の通信は触らない
  const page=same&&/\/(index\.html)?$/.test(url.pathname); // ゲームのページだけ。ほかのページ（規約・モニター）を開いても、ゲームの控えを書きかえない
  if(page){
    e.respondWith(fetch(req).then(r=>{const cp=r.clone();caches.open(CACHE).then(c=>c.put('./index.html',cp));return r}).catch(()=>caches.match('./index.html').then(r=>r||caches.match('./'))));
    return;
  }
  e.respondWith(caches.match(req).then(hit=>{
    const net=fetch(req).then(r=>{if(r&&(r.ok||r.type==='opaque')){const cp=r.clone();caches.open(CACHE).then(c=>c.put(req,cp))}return r}).catch(()=>hit);
    return hit||net;
  }));
});
