import {uid} from './data.js';

export const DEFAULT_SETTINGS={theme:'system',language:'zh-CN',notifications:false,easterEggs:true,reducedMotion:false};
export const EGGS=['glow','stars','halo'];
export function amountsFor(plan){return plan.steps.reduce((sum,step)=>{if(step.productId)sum[step.productId]=(sum[step.productId]||0)+Number(step.amount);return sum;},{});}
export function planIssue(plan,products){
 if(!plan.name.trim())return '给这次洗车起个名字吧。';
 if(!plan.steps.length)return '至少保留一个步骤。';
 if(plan.steps.some(s=>!s.name.trim()))return '还有步骤没有填写名称。';
 if(plan.steps.some(s=>!Number.isFinite(Number(s.water))||Number(s.water)<0||s.productId&&(!Number.isFinite(Number(s.amount))||Number(s.amount)<=0)))return '请核对原液和清水用量。';
 for(const [id,amount] of Object.entries(amountsFor(plan))){const p=products.find(p=>p.id===id);if(!p)return '有一瓶药剂已不在库存中。';if(amount>p.remaining)return `${p.name} 还差 ${Number((amount-p.remaining).toFixed(2))} mL，请调整用量或核对库存。`;}
 return '';
}
export function beginSession(state,now=Date.now(),id=uid()){
 if(state.session&&!state.session.done||planIssue(state.plan,state.products))return state;
 const amounts=amountsFor(state.plan),plan=structuredClone(state.plan),location=plan.location?.trim()||'未填写地点';
 const usage={id:`prepare:${id}`,sessionId:id,date:new Date(now).toISOString(),kind:'preparation',plan:plan.name,location,vehicle:plan.vehicle,amounts};
 if(state.history.some(h=>h.id===usage.id))return state;
 return {...state,products:state.products.map(p=>({...p,remaining:Number((p.remaining-(amounts[p.id]||0)).toFixed(2))})),history:[usage,...state.history],session:{id,plan,products:structuredClone(state.products),location,index:0,status:'prepared',paused:false,done:false,preparedAt:now,startedAt:null,resumedAt:null,activeMs:0,egg:EGGS[Math.floor(Math.random()*EGGS.length)]}};
}
export function startWashing(state,now=Date.now()){
 const s=state.session;if(!s||s.done||Number.isFinite(s.startedAt))return state;
 return {...state,session:{...s,status:'washing',startedAt:now,resumedAt:now,activeMs:0,paused:false}};
}
export function sessionTime(session,now=Date.now()){
 if(!Number.isFinite(session?.startedAt))return {wall:0,active:0,paused:0};
 const wall=Math.max(0,(session.finishedAt||now)-session.startedAt),active=Math.min(wall,Math.max(0,(session.activeMs||0)+(!session.paused&&!session.done?now-(session.resumedAt||now):0)));
 return {wall,active,paused:Math.max(0,wall-active)};
}
export function togglePause(state,now=Date.now()){
 const s=state.session;if(!s||s.done||!Number.isFinite(s.startedAt))return state;
 return {...state,session:s.paused?{...s,paused:false,resumedAt:now}:{...s,paused:true,activeMs:(s.activeMs||0)+Math.max(0,now-(s.resumedAt||now)),resumedAt:null}};
}
export function confirmStep(state,now=Date.now()){
 const s=state.session;if(!s||s.done||s.paused||!Number.isFinite(s.startedAt))return state;
 if(s.index<s.plan.steps.length-1)return {...state,session:{...s,index:s.index+1}};
 const finished={...s,status:'completed',done:true,finishedAt:now,activeMs:(s.activeMs||0)+Math.max(0,now-(s.resumedAt||now)),resumedAt:null};
 const times=sessionTime(finished,now),amounts=amountsFor(s.plan),record={id:s.id,date:new Date(now).toISOString(),preparedAt:s.preparedAt,startedAt:s.startedAt,finishedAt:now,durationMs:times.wall,activeMs:times.active,pausedMs:times.paused,name:s.plan.name,vehicle:s.plan.vehicle,location:s.location,steps:structuredClone(s.plan.steps),amounts,products:structuredClone(s.products),egg:s.egg};
 return {...state,session:finished,washes:(state.washes||[]).some(w=>w.id===s.id)?state.washes:[record,...(state.washes||[])]};
}
export function manualUsage(state,productId,amount,location,now=Date.now()){
 const p=state.products.find(p=>p.id===productId),n=Number(amount);if(!p||!Number.isFinite(n)||n<=0||n>p.remaining)return state;
 return {...state,products:state.products.map(x=>x.id===p.id?{...x,remaining:Number((x.remaining-n).toFixed(2))}:x),history:[{id:uid(),kind:'usage',productId:p.id,amount:n,location:location?.trim()||'未填写地点',date:new Date(now).toISOString()},...state.history]};
}
export function migrateState(value,fallback){
 const s=value&&Array.isArray(value.products)&&value.plan?.steps?.length?value:fallback;
 const session=s.session?{...s.session}:null;
 if(session&&!session.done){
  if(session.status==='prepared'||Number.isFinite(session.preparedAt)&&!Number.isFinite(session.startedAt)){session.status='prepared';session.startedAt=null;session.resumedAt=null;session.activeMs=0;session.paused=false;}
  else if(Number.isFinite(session.startedAt)){session.status='washing';}
  else{session.status='washing';session.startedAt=Date.now();session.resumedAt=session.paused?null:session.startedAt;session.activeMs=0;session.timingRestored=true;}
 }
 return {...s,version:3,plan:{...s.plan,location:s.plan.location||''},history:s.history||[],washes:s.washes||[],settings:{...DEFAULT_SETTINGS,...s.settings},session};
}
export function timeText(ms){const seconds=Math.floor(Math.max(0,ms)/1000),hours=Math.floor(seconds/3600),minutes=Math.floor(seconds%3600/60);return hours?`${hours}小时${minutes}分`:minutes?`${minutes}分${String(seconds%60).padStart(2,'0')}秒`:`${seconds}秒`;}
export function clockText(ms){const s=Math.floor(Math.max(0,ms)/1000);return `${Math.floor(s/60).toString().padStart(2,'0')}:${String(s%60).padStart(2,'0')}`;}
