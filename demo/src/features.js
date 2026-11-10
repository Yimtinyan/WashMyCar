import {uid} from './data.js';
export const VEHICLE='2024款乐道 L60 · 银色 · 星芒轮毂';
export function makeTemplates(plan){return ['日常养护','雨后洗车','周末精洗'].map((name,i)=>{const steps=structuredClone(plan.steps).map(s=>({...s,note:(i===1?'雨后先检查泥沙与水渍。':i===2?'分区检查，预留更充足的清洁时间。':'')+(s.note||'')}));if(i===1)steps.unshift({id:'rain-rinse',name:'泥沙预冲检查',productId:'',amount:0,water:0,tools:['高压水枪'],note:'先检查并冲走明显泥沙，再进行后续清洁。'});if(i===2){steps.unshift({id:'wheel-check',name:'轮毂分区检查',productId:'',amount:0,water:0,tools:['轮毂刷'],note:'需要药剂时手动选择，并核对本车饰面适用性。'});steps.push({id:'door-check',name:'门框与细节收尾',productId:'',amount:0,water:0,tools:['玻璃毛巾'],note:'分开使用不同区域的毛巾，检查水渍与残留。'});}return {id:'preset-'+i,name,builtIn:true,revision:1,plan:{...structuredClone(plan),name,vehicle:plan.vehicle||VEHICLE,steps}};});}
export function applyTemplate(state,template){if(state.session&&!state.session.done)return state;return {...state,session:null,plan:{...structuredClone(template.plan),vehicle:state.plan.vehicle||template.plan.vehicle,vehicleId:state.plan.vehicleId||template.plan.vehicleId,vehicleModel:state.plan.vehicleModel??null,templateId:template.id,revision:template.revision||1,steps:template.plan.steps.map(s=>({...structuredClone(s),id:uid()}))}};}
export function saveTemplate(state,name,id){
 if(!name.trim()||state.session&&!state.session.done)return state;
 const previous=state.templates?.find(x=>x.id===id);if(previous?.builtIn)return state;
 const revision=(previous?.revision||0)+1;
 const item={id:id||uid(),name:name.trim(),builtIn:false,revision,plan:{...structuredClone(state.plan),name:name.trim(),revision}};
 return {...state,templates:id?state.templates.map(x=>x.id===id?item:x):[...(state.templates||[]),item]};
}
export function phText(product){const ph=product?.ph;if(!ph||ph.value===''||ph.value==null)return 'pH 待填写';return `pH ${ph.value} · ${ph.medium||'原液'}`;}
