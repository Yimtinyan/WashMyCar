import {seedPlan,seedProducts} from '../data.js';
export const PREVIEW_KEY='washmycar-home-prototypes-v1';
export const directions=[
 {id:'a',name:'留白',subtitle:'清晰总览 · 轻盈秩序',description:'横向导航与通透留白，把方案、步骤和手表放在同一视野。'},
 {id:'b',name:'驾舱',subtitle:'当前动作 · 沉浸专注',description:'深色侧栏、放大的当前步骤和横向时间线，减少现场的阅读负担。'},
 {id:'c',name:'从容',subtitle:'温润材质 · 旅程叙事',description:'石色与苔绿、衬线标题和非对称双栏，让准备工作有从容的节奏。'}
];
export function sampleState(scene='standard'){
 const state={version:2,products:structuredClone(seedProducts),plan:structuredClone(seedPlan),history:[],session:null};
 if(scene==='empty')state.products=[];
 if(scene==='long'){
  state.plan.name='周末日常洗车 · 长途归来后的车身、轮毂与内饰精细清洁计划';
  state.plan.steps=Array.from({length:24},(_,i)=>({...structuredClone(seedPlan.steps[i%4]),id:'long-'+i,name:i===0?'泡沫预洗：核对亮光漆与透明保护膜的分区施工要求':seedPlan.steps[i%4].name}));
 }
 if(scene==='low')state.products=state.products.map(p=>({...p,remaining:0}));
 return state;
}
export function loadPreview(){try{const s=JSON.parse(localStorage.getItem(PREVIEW_KEY));if(s?.version===2&&Array.isArray(s.products)&&s.plan?.steps?.length)return s;}catch{}return sampleState();}
