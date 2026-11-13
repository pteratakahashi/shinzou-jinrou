/* 多言語対応（2026-11-14）。
   ゲームの中身（index.html）は日本語のまま動かし、画面に出た文を、出た直後に選んだ言語へ差しかえる。
   ・文の対応表は i18n/言語.json（{日本語: 訳}。{0}{1}…は名前や数が入る穴）。作り方は ~/shinzou-jinrou/i18n/extract.py
   ・言語は SV.lang（設定の「言語」）。まだ選んでいなければ、端末の言語から決める（日本語／韓国語／中国語、ほかは英語）
   ・対戦のログやカードの効果も、画面に出るときに差しかえる。相手と言語がちがっても、それぞれ自分の言語で見える
   ・プレイヤーの名前、お知らせ（日本語のみ）、入力らんは差しかえない */
(()=>{
  const LANGS={ja:'日本語',en:'English','zh-Hans':'简体中文','zh-Hant':'繁體中文',ko:'한국어'};
  const JA=/[぀-ヿ一-鿿]/;
  const SKIP='.atb,.glyph,.dmA:not(.pl),.updT,.hmEvt>span,.bdName,.vsNm,.hmId>b,.menuName,.pName,input,textarea,select,script,style,[data-noi18n],#rpcBar .rcT';
  const ATTRS=['aria-label','title','placeholder','alt'];
  const FONT={ko:['Noto+Serif+KR:wght@500;700;900','Noto+Sans+KR:wght@400;500;700','"Noto Serif KR"','"Noto Sans KR"'],
    'zh-Hans':['Noto+Serif+SC:wght@500;700;900','Noto+Sans+SC:wght@400;500;700','"Noto Serif SC"','"Noto Sans SC"'],
    'zh-Hant':['Noto+Serif+TC:wght@500;700;900','Noto+Sans+TC:wght@400;500;700','"Noto Serif TC"','"Noto Sans TC"']};
  function pick(){
    try{if(typeof SV!=='undefined'&&SV.lang&&LANGS[SV.lang])return SV.lang}catch(e){}
    const ls=(navigator.languages&&navigator.languages.length?navigator.languages:[navigator.language||'ja']).map(x=>String(x).toLowerCase());
    for(const l of ls){
      if(l.startsWith('ja'))return'ja';
      if(l.startsWith('ko'))return'ko';
      if(l.startsWith('zh'))return /tw|hk|mo|hant/.test(l)?'zh-Hant':'zh-Hans';
      if(l.startsWith('en'))return'en';
    }
    return'en';
  }
  const lang=pick();
  window.I18N={lang,langs:LANGS,on:false,t:s=>s};
  // 設定の「言語」
  document.addEventListener('change',e=>{const t=e.target;if(t&&t.id==='stLang'&&LANGS[t.value]){try{SV.lang=t.value;save()}catch(_){}location.reload()}});
  if(lang==='ja')return;
  document.documentElement.lang=lang;

  const esc=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  let exact=new Map(),pats=[],subs=[],cache=new Map();
  const names=()=>{const a=[];try{a.push(netName());if(NET.opp)a.push(NET.opp);if(NET.watchNames)a.push(NET.watchNames.me,NET.watchNames.cpu);if(typeof S!=='undefined'&&S&&S.names)a.push(S.names.me,S.names.cpu);if(SV.nick)a.push(SV.nick)}catch(e){}return a.filter(Boolean)};
  const fill=(tr,caps)=>tr.replace(/\{(\d+)\}/g,(m,i)=>caps[+i]!=null?caps[+i]:'');
  const MISS=new Set();window.I18N.miss=MISS;
  const EFF=/(条件：|コスト：|効果：|共鳴：|襲撃：|呪い（[^）]*）：)/;
  const SP=lang==='en';   // 英語は、つないだ文のあいだに空白を入れる
  function tr(str,depth=0){
    if(!str||!JA.test(str))return str;
    const m=str.match(/^(\s*)([\s\S]*?)(\s*)$/),core=m[2].replace(/\s*\n\s*/g,'');
    if(!core)return str;
    const hit=cache.get(core);if(hit!==undefined)return m[1]+hit+m[3];
    let out=core;
    const nm=names();
    if(nm.includes(core)){return str}
    const e=exact.get(core);
    if(e!==undefined)out=e;
    else{
      let done=false;
      for(const p of pats){const r=p.re.exec(core);if(r){out=fill(p.tr,r.slice(1).map(c=>nm.includes(c)||depth>5?c:tr(c,depth+1)));done=true;break}}
      if(!done){
        // 飾りを外して中身だけ訳す：先頭の記号、うしろの（3/10）、かっこで包んだ名前
        let r;
        if((r=core.match(/^((?:🔒|[★☆●○◆▶✓\s])+)([\s\S]+)$/u))&&r[2]!==core){out=r[1]+tr(r[2],depth+1);done=true}
        else if((r=core.match(/^([\s\S]+?)(（\d+\/\d+）)$/))){out=tr(r[1],depth+1)+' ('+r[2].slice(1,-1)+')';done=true}
        else if((r=core.match(/^([〈「『【])([^〈〉「」『』【】]+)([〉」』】])$/))){const q=lang==='en'&&r[1]==='「'?['“','”']:lang==='en'&&r[1]==='【'?['[',']']:[r[1],r[3]];out=q[0]+tr(r[2],depth+1)+q[1];done=true}
        else if(EFF.test(core)&&depth<6){out=core.split(EFF).map(x=>x?tr(x,depth+1):'').join(SP?' ':'').trim();done=true}
        else{
          // ならび（・や／で区切った言葉）は、1つずつ訳す
          const parts=core.split(/(\s*[・／·]\s*)/);
          if(parts.length>=3&&depth<6&&parts.every((x,i)=>i%2===1||x.length<=22)){
            out=parts.map((x,i)=>i%2===1?(lang==='en'?(/／/.test(x)?' / ':' · '):x):(x?tr(x,depth+1):'')).join('');done=true;
          }
        }
      }
      if(!done){
        if(depth===0&&MISS.size<4000)MISS.add(core);
        // 文のつなぎ合わせ：長い文から順に、中にふくまれる文を差しかえる
        let s=core;
        for(const p of subs){
          if(!JA.test(s))break;
          if(p.re){if(p.lit&&!s.includes(p.lit))continue;s=s.replace(p.re,(...a)=>(SP?' ':'')+fill(p.tr,a.slice(1,1+p.n).map(c=>nm.includes(c)||depth>5?c:tr(c,depth+1)))+(SP?' ':''))}
          else if(s.includes(p.ja))s=s.split(p.ja).join((SP?' ':'')+p.tr+(SP?' ':''));
        }
        if(SP)s=s.replace(/ {2,}/g,' ').replace(/ ([.,!?:;)\]〉])/g,'$1').replace(/([(\[〈]) /g,'$1').trim();
        out=s;
      }
    }
    if(SP)out=out.replace(/\bYou's\b/g,'Your').replace(/\bYou (is|has|was)\b/g,(m,v)=>'You '+({is:'are',has:'have',was:'were'})[v]).replace(/\bYou (\w+?)s\b(?= )/g,'You $1');
    if(cache.size>6000)cache.clear();
    if(!nm.length||depth===0)cache.set(core,out);
    return m[1]+out+m[3];
  }
  function build(src){
    exact=new Map();pats=[];subs=[];
    const dict={...src};
    // 文のはしの穴は、画面では部品（太字やボタン）になって文が分かれることがある。はしの穴を外した形も足す
    for(const ja in src){
      const t=src[ja];if(typeof t!=='string'||!/^\{\d+\}|\{\d+\}$/.test(ja))continue;
      let k=ja,v=t,cut=[];
      for(let g=0;g<8;g++){const a=k.match(/^\{(\d+)\}/),b=k.match(/\{(\d+)\}$/);if(a){k=k.slice(a[0].length);cut.push(a[1])}else if(b){k=k.slice(0,-b[0].length);cut.push(b[1])}else break}
      if(k.length<2||!JA.test(k)||/\{\d+\}/.test(k)||dict[k]!==undefined)continue;
      cut.forEach(i=>{v=v.split('{'+i+'}').join('')});
      v=v.replace(/\s{2,}/g,' ').trim();if(v)dict[k]=v;
    }
    for(const ja in dict){
      const t=dict[ja];if(typeof t!=='string'||!t)continue;
      if(/^[.#][a-zA-Z]/.test(ja))continue;   // 目印（CSS セレクタ）は文ではない
      const lit=ja.replace(/\{\d+\}/g,'');
      if(!/\{\d+\}/.test(ja)){exact.set(ja,t);if(ja.length>=2&&JA.test(ja))subs.push({ja,tr:t,len:ja.length});continue}
      // 穴の番号は、文に出てくる順に 0,1,2…（extract.py がそう作る）
      const body=esc(ja).replace(/\\\{\d+\\\}/g,'\u0001');
      const n=(ja.match(/\{\d+\}/g)||[]).length;
      if(!JA.test(lit.replace(/[・／、：（）「」]/g,''))&&!/[A-Za-z]/.test(lit))continue;   // 区切りだけの形（{0}・{1}）は、ならびとして1つずつ訳す
      try{
        pats.push({re:new RegExp('^'+body.split('\u0001').join('([\\s\\S]*?)')+'$'),tr:t,len:lit.length});
        // つなぎ合わせ用：穴は短い言葉だけ（文をまたいで食べないように）
        const longest=lit.split(/\s+/).sort((a,b)=>b.length-a.length)[0]||'';
        if(lit.length>=3&&JA.test(lit.replace(/[・／、：（）「」]/g,''))){
          // はしにある穴は、区切り（、。・：（）など）まで広げて取る。中の穴は短い言葉だけ
          const ps=body.split('\u0001'),EDGE='([^、。！？\\n・：（）「」／]{1,30})',MID='([^、。！？\\n]{1,24}?)';
          let rs='';ps.forEach((x,i)=>{rs+=x;if(i<ps.length-1)rs+=((i===0&&x==='')||(i===ps.length-2&&ps[ps.length-1]===''))?EDGE:MID});
          subs.push({re:new RegExp(rs,'g'),tr:t,n,len:lit.length,lit:ja.split(/\{\d+\}/).sort((a,b)=>b.length-a.length)[0]||longest});
        }
      }catch(e){}
    }
    pats.sort((a,b)=>b.len-a.len);subs.sort((a,b)=>b.len-a.len);
    cache=new Map();
  }
  // ---- 画面の差しかえ
  const lastOut=new WeakMap(),attrOut=new WeakMap();
  function doText(n){
    const p=n.parentElement;if(!p||p.closest(SKIP))return;
    const v=n.data;if(lastOut.get(n)===v)return;
    let o=tr(v);
    if(SP&&o!==v){if(n.previousSibling&&!/^[\s.,!?:;)\]〉’”]/.test(o))o=' '+o;if(n.nextSibling&&!/[\s(\[〈‘“]$/.test(o))o+=' '}
    lastOut.set(n,o);if(o!==v)n.data=o;
  }
  function doAttrs(el){
    if(el.closest&&el.closest(SKIP)&&!el.matches('input,textarea'))return;
    // 手札のカード（.hc）の aria-label は、チュートリアルが目印に使うので差しかえない
    let m=attrOut.get(el);
    for(const a of ATTRS){if(a==='aria-label'&&el.classList&&el.classList.contains('hc'))continue;const v=el.getAttribute(a);if(v&&JA.test(v)&&!(m&&m[a]===v)){const o=tr(v);if(!m){m={};attrOut.set(el,m)}m[a]=o;if(o!==v)el.setAttribute(a,o)}}
  }
  function walk(root){
    if(root.nodeType===3)return doText(root);
    if(root.nodeType!==1)return;
    if(root.matches('script,style'))return;
    doAttrs(root);
    const w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT|NodeFilter.SHOW_ELEMENT);
    let n;while((n=w.nextNode())){if(n.nodeType===3){if(JA.test(n.data))doText(n)}else doAttrs(n)}
  }
  function start(dict,css){
    build(dict);
    window.I18N.on=true;window.I18N.t=s=>tr(String(s));
    // CSS の中の文（content）
    if(css&&css.length){const st=document.createElement('style');st.textContent=css.map(([sel,ja])=>dict[ja]?`${sel}{content:${JSON.stringify(dict[ja])}!important}`:'').join('\n');document.head.appendChild(st)}
    const f=FONT[lang];
    if(f){const l=document.createElement('link');l.rel='stylesheet';l.href=`https://fonts.googleapis.com/css2?family=${f[0]}&family=${f[1]}&display=swap`;document.head.appendChild(l);
      const st=document.createElement('style');st.textContent=`:root{--pcf:"Shippori Mincho B1",${f[2]},serif!important;--game:"Shippori Mincho B1",${f[2]},serif!important;--display:"Shippori Mincho B1",${f[2]},serif!important;--body:"Zen Kaku Gothic New",${f[3]},sans-serif!important}`;document.head.appendChild(st)}
    // 言葉が長くなる言語向けの、見た目の合わせ
    {const st=document.createElement('style');st.textContent=`.fLab{width:auto!important;min-width:0!important;white-space:nowrap}.hmLogo,.hmLogo *{letter-spacing:.02em!important}${lang==='en'?'.hmLogo h1{font-size:clamp(26px,8.6vw,46px)!important;line-height:1.1!important}html.fit-wide .hmLogo h1{font-size:clamp(34px,4.4vw,64px)!important}.bt .btAct .b{letter-spacing:0!important;font-size:12px}.hmMain .miTag{font-size:9px!important;letter-spacing:0!important}.hmMain b{font-size:17px!important;letter-spacing:.04em!important}':''}`;document.head.appendChild(st)}
    if(document.title&&JA.test(document.title))document.title=tr(document.title);
    walk(document.body);
    new MutationObserver(recs=>{
      for(const r of recs){
        if(r.type==='characterData')doText(r.target);
        else if(r.type==='attributes')doAttrs(r.target);
        else r.addedNodes.forEach(walk);
      }
    }).observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:ATTRS});
  }
  const ver=(typeof APP_VER!=='undefined'?APP_VER:Date.now());
  Promise.all([fetch(`i18n/${lang}.json?${ver}`).then(r=>{if(!r.ok)throw new Error(r.status);return r.json()}),fetch(`i18n/css.json?${ver}`).then(r=>r.ok?r.json():[]).catch(()=>[])])
    .then(([d,css])=>start(d,css)).catch(e=>console.error('i18n',e));
})();
