import {migrateState,planIssue} from './session.js';

export const MAX_BACKUP_BYTES=12*1024*1024;
const fail=message=>{throw new Error(message);};
const obj=(x,label)=>{if(!x||typeof x!=='object'||Array.isArray(x))fail(`${label}格式不正确`);};
const str=(x,label,max=4000)=>{if(typeof x!=='string'||x.length>max)fail(`${label}格式不正确`);};
const number=(x,label,min=0,max=Number.MAX_SAFE_INTEGER)=>{if(typeof x!=='number'||!Number.isFinite(x)||x<min||x>max)fail(`${label}不是有效数值`);};
function list(x,label){if(!Array.isArray(x)||x.length>20000)fail(`${label}列表不正确`);}
function ids(items,label){list(items,label);const seen=new Set();for(const x of items){obj(x,label);str(x.id,`${label}ID`,200);if(!x.id||seen.has(x.id))fail(`${label}存在空白或重复ID`);seen.add(x.id);}return seen;}
function optionalText(x,keys){for(const key of keys)if(x[key]!==undefined)str(x[key],key);}
function products(items){
 ids(items,'药剂');for(const p of items){str(p.name,'药剂名称',200);str(p.brand,'品牌',200);optionalText(p,['date','place','use','shape','color','label','code']);number(p.capacity,'容量',0.01);if(p.stockStatus!==undefined&&!['exact','estimated','unknown'].includes(p.stockStatus))fail('库存可信度不正确');if(p.stockStatus!=='unknown')number(p.remaining,'余量',0,p.capacity);else if(p.remaining!==null)number(p.remaining,'余量',0,p.capacity);if(p.price!==''&&p.price!=null)number(p.price,'价格');if(p.instructions!==undefined)str(p.instructions,'使用方法');if(p.ph){obj(p.ph,'pH');optionalText(p.ph,['medium','source']);if(p.ph.value!==''&&p.ph.value!=null)number(p.ph.value,'pH',0,14);}}
}
function plan(p,productIds){
 obj(p,'方案');str(p.name,'方案名称',200);str(p.vehicle,'车辆名称',200);optionalText(p,['location']);ids(p.steps,'步骤');if(!p.steps.length)fail('方案至少需要一个步骤');
 for(const s of p.steps){str(s.name,'步骤名称',200);str(s.productId,'药剂关联',200);if(s.productId&&!productIds.has(s.productId))fail('方案关联了不存在的药剂');if(s.amount!=='')number(s.amount,'原液用量');if(s.water!=='')number(s.water,'清水用量');list(s.tools,'工具');for(const t of s.tools)str(t,'工具名称',200);if(s.note!==undefined)str(s.note,'步骤备注');}
}
function validateData(s){
 obj(s,'资料');if(![2,3,4,5].includes(s.version))fail('不支持此资料版本');
 products(s.products);const pids=new Set(s.products.map(p=>p.id));plan(s.plan,pids);
 ids(s.washes||[],'记录');ids(s.history||[],'使用履历');ids(s.templates||[],'已存方案');ids(s.vehicles||[],'车辆');
 for(const v of s.vehicles||[])str(v.name,'车辆名称',200);
 for(const t of s.templates||[]){str(t.name,'方案名称',200);plan(t.plan,pids);}
 for(const w of s.washes||[]){products(w.products);plan({...w,vehicle:w.vehicle||'我的爱车'},new Set(w.products.map(p=>p.id)));number(w.durationMs,'洗车时长');number(w.finishedAt,'完成时间');obj(w.amounts,'使用汇总');for(const [id,n]of Object.entries(w.amounts)){if(!w.products.some(p=>p.id===id))fail('记录的药剂快照不完整');number(n,'取用量');}if(w.notes!==undefined)str(w.notes,'洗后备注');if(w.noteStatus!==undefined&&!['open','resolved'].includes(w.noteStatus))fail('备注状态不正确');}
 for(const h of s.history||[]){optionalText(h,['location','plan','kind','productId','sessionId']);if(h.amounts){obj(h.amounts,'使用履历');for(const n of Object.values(h.amounts))number(n,'取用量');}if(h.amount!==undefined)number(h.amount,'取用量');str(h.date,'履历时间',100);if(!Number.isFinite(Date.parse(h.date)))fail('履历时间不正确');}
 if(s.session){obj(s.session,'当前流程');str(s.session.id,'流程ID',200);optionalText(s.session,['location','status','egg']);products(s.session.products);plan(s.session.plan,new Set(s.session.products.map(p=>p.id)));if(planIssue(s.session.plan,s.session.products))fail('当前流程的药剂或用量检查未通过');number(s.session.index,'步骤序号',0,s.session.plan.steps.length-1);if(!Number.isInteger(s.session.index)||typeof s.session.done!=='boolean'||typeof s.session.paused!=='boolean')fail('当前流程状态不正确');for(const key of ['startedAt','preparedAt','finishedAt','resumedAt','activeMs'])if(s.session[key]!=null)number(s.session[key],'流程时间');}
 if(s.settings){obj(s.settings,'偏好');if(!['system','light','dark'].includes(s.settings.theme)||!['zh-CN','en'].includes(s.settings.language))fail('外观或语言不正确');for(const key of ['notifications','reducedMotion'])if(typeof s.settings[key]!=='boolean')fail('偏好开关不正确');}
 if(s.deferredNoteIds){list(s.deferredNoteIds,'暂缓提醒');for(const id of s.deferredNoteIds)str(id,'提醒关联',200);}
 if(s.version===5){const vehicles=new Map(s.vehicles.map(v=>[v.id,v.name]));for(const p of [s.plan,...s.washes,...s.templates.map(t=>t.plan),...(s.session?[s.session.plan]:[])])if(vehicles.get(p.vehicleId)!==p.vehicle)fail('车辆关联不完整或名称不一致');}
}
export function createBackup(state,now=Date.now()){
 const data=structuredClone(state);
 for(const w of [...data.washes,...(data.session?[data.session]:[])]){delete w.health;delete w.heartRateSamples;}
 validateData(data);
 return JSON.stringify({format:'WashMyCarBackup',schemaVersion:1,appVersion:5,volumeUnit:'mL',createdAt:new Date(now).toISOString(),healthDataIncluded:false,attachments:[],data},null,2);
}
export function readBackup(text){
 if(new TextEncoder().encode(text).length>MAX_BACKUP_BYTES)fail('备份超过12 MB，请检查文件');
 let b;try{b=JSON.parse(text);}catch{fail('无法读取JSON备份文件');}
 if(b?.format!=='WashMyCarBackup'||b.schemaVersion!==1||b.volumeUnit!=='mL'||b.appVersion>5)fail('备份格式、版本或单位不兼容');
 if(b.healthDataIncluded!==false)fail('当前版本不恢复健康明细');
 if(!Array.isArray(b.attachments)||b.attachments.length)fail('当前版本不支持恢复附件');
 validateData(b.data);const state=migrateState(b.data);validateData(state);
 return {state,createdAt:b.createdAt,summary:{products:state.products.length,washes:state.washes.length,templates:state.templates.length,vehicles:state.vehicles.length}};
}
