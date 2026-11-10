export const categories=['全部用途','预洗','正洗','轮毂','内饰','保护'];
export const tools=['PA壶','雾化壶','洗车桶','洗车手套','预洗手套','轮毂刷','玻璃毛巾','长绒擦车巾','高压水枪'];
export const seedProducts=[
 {id:'reset',brand:'CARPRO',name:'Reset',use:'正洗',capacity:500,remaining:340,color:'#2e6b61',label:'#e66e2c',code:'WASH 01',shape:'round',date:'2026-10-12',place:'品牌旗舰店',price:128},
 {id:'gsf',brand:'Koch-Chemie',name:'Gentle Snow Foam',use:'预洗',capacity:1000,remaining:760,color:'#dfd4ae',label:'#c7b990',code:'Gsf',shape:'koch',date:'2026-10-15',place:'汽车用品店',price:139},
 {id:'beast',brand:'SONAX',name:'Beast Wheel Cleaner',use:'轮毂',capacity:1000,remaining:620,color:'#a7768a',label:'#c24c7f',code:'WHEEL 03',shape:'spray',date:'2026-10-18',place:'品牌旗舰店',price:108},
 {id:'xpress',brand:'P&S',name:'Xpress Interior Cleaner',use:'内饰',capacity:500,remaining:280,color:'#b5a078',label:'#d6a453',code:'INSIDE 04',shape:'spray',date:'2026-10-20',place:'本地美容店',price:69},
 {id:'ironx',brand:'CARPRO',name:'IronX',use:'轮毂',capacity:500,remaining:210,color:'#75a4a4',label:'#588a9f',code:'IRON 05',shape:'spray',date:'2026-10-22',place:'品牌旗舰店',price:118},
 {id:'wetcoat',brand:'GYEON',name:'Q²M WetCoat',use:'保护',capacity:500,remaining:380,color:'#8c819d',label:'#866ca8',code:'COAT 06',shape:'spray',date:'2026-10-25',place:'汽车用品店',price:99},
 {id:'hydro',brand:'Fireball',name:'HydroShampoo',use:'正洗',capacity:500,remaining:410,color:'#217766',label:'#81928b',code:'HYDRO',shape:'fireball',date:'2026-11-01',place:'品牌旗舰店',price:''}
];
export const seedPlan={name:'周末日常洗车',vehicle:'我的爱车 · 亮光漆',steps:[
 {id:'s1',name:'泡沫预洗',productId:'gsf',amount:20,water:1000,tools:['PA壶'],note:'按本瓶标签核对配液和冲洗要求，保持板面湿润。'},
 {id:'s2',name:'车身正洗',productId:'reset',amount:30,water:15000,tools:['洗车桶','洗车手套'],note:'先从较干净区域开始，保持手套清洁。'},
 {id:'s3',name:'冲洗车身',productId:'',amount:0,water:0,tools:['高压水枪'],note:'冲净残留，确认各个区域。'},
 {id:'s4',name:'擦干收尾',productId:'',amount:0,water:0,tools:['长绒擦车巾'],note:'使用干净的擦车巾，轻柔擦干。'}
]};
export const STORE_KEY='washmycar-demo-v2';
export function initialState(){try{const x=JSON.parse(localStorage.getItem(STORE_KEY));if([2,3].includes(x?.version)&&Array.isArray(x.products)&&x.plan?.steps?.length)return x;}catch{}return {version:2,products:structuredClone(seedProducts),plan:structuredClone(seedPlan),history:[],session:null};}
export const ml=n=>Number(Number(n).toFixed(2)).toLocaleString('zh-CN',{maximumFractionDigits:2});
export const uid=()=>globalThis.crypto?.randomUUID?.()||'id'+Date.now()+Math.random().toString(16).slice(2);
