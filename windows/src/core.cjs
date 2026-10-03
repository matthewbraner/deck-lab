'use strict';
const key = name => String(name).normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
const entries = deck => ['main','extra','side'].flatMap(zone => deck[zone] || []);
const fresh = (q, now = Date.now()) => !!q?.verified && Number.isFinite(q.checked) && now >= q.checked && now-q.checked < 86400000;
function aggregate(decks, collection = {}) {
  const rows = new Map();
  for (const deck of decks) {
    const seen = new Set();
    for (const zone of ['main','extra','side']) for (const e of deck[zone] || []) {
      const id = key(e.name); let row = rows.get(id);
      if (!row) { row = {id, name:e.name, cardId:e.cardId, main:0, extra:0, side:0, included:0}; rows.set(id,row); }
      row[zone] += e.count; if(e.count>0) seen.add(id);
    }
    for (const id of seen) rows.get(id).included++;
  }
  return [...rows.values()].map(r => {
    const average = (r.main+r.extra+r.side)/decks.length;
    const owned = ownedCount(collection[r.id]);
    return {...r, average, target:Math.round(average), owned, missing:Math.max(0,Math.round(average)-owned), inclusion:r.included/decks.length};
  }).sort((a,b)=>b.included-a.included || a.name.localeCompare(b.name));
}
function ownedCount(holding) { return (holding?.unassigned || 0) + Object.values(holding?.printings || {}).reduce((n,p)=>n+p.count,0); }
function filterDecks(decks, required='', excluded='') {
  const split = s => s.split(/[\n;]/).map(key).filter(Boolean);
  const yes=split(required),no=split(excluded);
  return decks.filter(d=>{const names=new Set(entries(d).filter(e=>e.count>0).map(e=>key(e.name)));return yes.every(n=>names.has(n)) && no.every(n=>!names.has(n));});
}
function choose(n,k) { if(k<0 || k>n) return 0; let r=1; for(let i=1;i<=Math.min(k,n-k);i++) r=r*(n-i+1)/i;return r; }
function hypergeometric(n,k,hand,min=1) {
  if (![n,k,hand,min].every(Number.isInteger)||n<1||n>200||k<0||k>n||hand<0||hand>n||min<0) throw Error('Use whole numbers: successes and hand size cannot exceed deck size.');
  let p=0;for(let i=min;i<=Math.min(k,hand);i++)p+=choose(k,i)*choose(n-k,hand-i)/choose(n,hand);return Math.min(1,p);
}
// Group copies by bucket membership; exact multivariate hypergeometric enumeration.
// A copy may satisfy more than one bucket. Buckets describe opening-hand presence, not consumption.
function comboProbability(deck, buckets, hand, mode='all') {
  const n=deck.main.reduce((s,e)=>s+e.count,0);
  if(!Number.isInteger(hand)||hand<0||hand>n||hand>10||buckets.length<1||buckets.length>4) throw Error('Choose 1–4 buckets and a hand of 0–10 cards within the deck size.');
  const groups=new Map();
  for(const e of deck.main){const mask=buckets.reduce((m,b,i)=>b.map(key).includes(key(e.name))?m|1<<i:m,0);groups.set(mask,(groups.get(mask)||0)+e.count);}
  let dp=new Map([['0,0',1]]);
  for(const [mask,count] of groups){const next=new Map();for(const [state,ways] of dp){const [drawn,met]=state.split(',').map(Number);for(let x=0;x<=Math.min(count,hand-drawn);x++){const k=`${drawn+x},${x?met|mask:met}`;next.set(k,(next.get(k)||0)+ways*choose(count,x));}}dp=next;}
  let success=0;for(const [state,ways] of dp){const [drawn,met]=state.split(',').map(Number);if(drawn===hand&&(mode==='any'?met!==0:met===(1<<buckets.length)-1))success+=ways;}
  return success/choose(n,hand);
}
function parseYdk(text,cards=[]) {
  const index=new Map(cards.flatMap(c=>[...[c.id,...(c.aliases||[])].map(id=>[String(id),c])]));
  const deck={id:require('node:crypto').randomUUID(),name:'Imported deck',format:'TCG',main:[],extra:[],side:[]}; let zone='main';
  for(const raw of text.split(/\r?\n/)){const line=raw.trim();if(line==='#main')zone='main';else if(line==='#extra')zone='extra';else if(line==='!side')zone='side';else if(/^\d+$/.test(line)){const card=index.get(line);const id=String(card?.id||line),old=deck[zone].find(e=>e.cardId===id);if(old)old.count++;else deck[zone].push({cardId:id,name:card?.name||`Unknown card #${id}`,count:1});}else if(line&&!line.startsWith('#'))throw Error('Invalid YDK line.');}
  if(!entries(deck).length||entries(deck).reduce((n,e)=>n+e.count,0)>200)throw Error('Deck must contain 1–200 cards.');return deck;
}
function toYdk(deck){return ['#created by Deck Lab',...['main','extra','side'].flatMap(z=>[z==='side'?'!side':`#${z}`,...deck[z].flatMap(e=>{if(!/^\d+$/.test(String(e.cardId)))throw Error('This card has no known passcode. Load card data before exporting.');return Array(e.count).fill(e.cardId);})])].join('\n');}
function emptyState(){return {schema:1,collection:{},builds:[],hidden:[],favorites:[],buckets:{},quotes:{},priceErrors:{},snapshot:null};}
function validateState(s){
  if(!s||s.schema!==1||!Array.isArray(s.builds)||!Array.isArray(s.hidden)||!Array.isArray(s.favorites)||!s.collection||typeof s.collection!=='object'||!s.buckets||!s.quotes||!s.priceErrors)throw Error('Not a valid Windows Deck Lab backup (schema 1).');
  const count=n=>Number.isInteger(n)&&n>=0&&n<=9999;
  for(const h of Object.values(s.collection)){if(!h||!count(h.unassigned)||!h.printings||typeof h.printings!=='object')throw Error('Invalid collection quantity.');for(const p of Object.values(h.printings))if(!count(p.count)||!p.variant||!Number.isInteger(p.variant.product?.id))throw Error('Invalid printing.');}
  for(const d of [...s.builds,...(s.snapshot?.decks||[])])for(const z of ['main','extra','side']){if(!Array.isArray(d[z]))throw Error('Invalid deck zone.');for(const e of d[z])if(typeof e.name!=='string'||!count(e.count))throw Error('Invalid deck entry.');}
  return s;
}
module.exports={key,entries,fresh,aggregate,ownedCount,filterDecks,choose,hypergeometric,comboProbability,parseYdk,toYdk,emptyState,validateState};
