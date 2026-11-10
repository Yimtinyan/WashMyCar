import {uid} from './data.js';

export const stockKind=p=>p.stockStatus==='unknown'||p.remaining==null?'unknown':p.stockStatus==='exact'?'exact':'estimated';
export function stockText(p){
 if(stockKind(p)==='unknown')return '余量未知';
 return `${stockKind(p)==='estimated'?'约 ':''}${Number(p.remaining).toLocaleString('zh-CN',{maximumFractionDigits:2})} mL`;
}
export function pendingNotes(state){
 return (state.washes||[]).filter(w=>w.vehicleId===state.plan.vehicleId&&w.notes?.trim()&&w.noteStatus!=='resolved'&&!(state.deferredNoteIds||[]).includes(w.id));
}
export function updateWashNote(state,id,notes,now=Date.now()){
 return {...state,washes:state.washes.map(w=>w.id===id?{...w,notes,noteStatus:'open',notesUpdatedAt:now}:w),deferredNoteIds:(state.deferredNoteIds||[]).filter(x=>x!==id)};
}
export function setNoteStatus(state,id,status){
 if(status==='deferred')return {...state,deferredNoteIds:[...new Set([...(state.deferredNoteIds||[]),id])]};
 return {...state,washes:state.washes.map(w=>w.id===id?{...w,noteStatus:status}:w)};
}
export function addVehicle(state,name){
 const clean=name.trim();if(!clean||state.session&&!state.session.done)return state;
 const vehicle=state.vehicles.find(v=>v.name===clean)||{id:uid(),name:clean,modelKey:null};
 return {...state,vehicles:state.vehicles.some(v=>v.id===vehicle.id)?state.vehicles:[...state.vehicles,vehicle],session:null,plan:{...state.plan,vehicle:vehicle.name,vehicleId:vehicle.id,vehicleModel:vehicle.modelKey}};
}
// A deterministic transfer-integrity check for the local demo, not a security signature.
export function packageChecksum(session){
 const payload=JSON.stringify({version:1,id:session.id,plan:session.plan,products:session.products});
 let hash=2166136261;for(let i=0;i<payload.length;i++){hash^=payload.charCodeAt(i);hash=Math.imul(hash,16777619);}
 return (hash>>>0).toString(16).padStart(8,'0');
}
export function watchReady(session){return !!session&&session.watchPackage?.status==='ready'&&session.watchPackage.checksum===packageChecksum(session)&&session.watchPackage.ackChecksum===session.watchPackage.checksum;}
export function acknowledgeWatch(state,now=Date.now()){
 const s=state.session;if(!s||s.done||Number.isFinite(s.startedAt))return state;
 const checksum=packageChecksum(s),matches=s.watchPackage?.checksum===checksum;
 return {...state,session:{...s,watchPackage:{...s.watchPackage,status:matches?'ready':'error',ackChecksum:matches?checksum:null,acknowledgedAt:matches?now:null,error:matches?'':'流程内容与准备版本不一致，请重新核验。'}}};
}
export function prepareWatchRetry(state){
 const s=state.session;if(!s||s.done||Number.isFinite(s.startedAt))return state;
 return {...state,session:{...s,watchPackage:{version:1,status:'pending',checksum:packageChecksum(s),ackChecksum:null}}};
}
export function normalizeVehicles(state){
 const vehicles=(state.vehicles||[]).map(v=>({...v,modelKey:v.modelKey===undefined?(v.name.includes('乐道 L60')?'onvo-l60':null):v.modelKey}));
 const associate=plan=>{
  const name=plan.vehicle?.trim()||'我的爱车';
  let v=vehicles.find(v=>v.id===plan.vehicleId)||vehicles.find(v=>v.name===name);
  if(!v){v={id:uid(),name,modelKey:name.includes('乐道 L60')?'onvo-l60':null};vehicles.push(v);}
  return {...plan,vehicleId:v.id,vehicle:name,vehicleModel:plan.vehicleModel===undefined?v.modelKey:plan.vehicleModel};
 };
 const plan=associate(state.plan),washes=(state.washes||[]).map(w=>({...associate(w),noteStatus:w.noteStatus||'open'}));
 const templates=(state.templates||[]).map(t=>({...t,builtIn:t.builtIn??t.id.startsWith('preset-'),revision:t.revision||1,plan:associate(t.plan)}));
 const session=state.session?{...state.session,plan:associate(state.session.plan)}:null;
 return {...state,plan,washes,templates,session,vehicles,deferredNoteIds:state.deferredNoteIds||[]};
}
