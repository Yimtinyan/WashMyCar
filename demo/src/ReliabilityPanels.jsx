import React,{useRef,useState} from 'react';
import {applyTemplate,saveTemplate,phText} from './features.js';
import {addVehicle,pendingNotes,setNoteStatus,stockText,watchReady,acknowledgeWatch,prepareWatchRetry} from './reliability.js';
import {createBackup,readBackup,MAX_BACKUP_BYTES} from './backup.js';
import {STORE_KEY} from './data.js';

export function PlanLibrary({state,setState,onOpenNote}){
 const [name,setName]=useState(''),[selected,setSelected]=useState('');
 const locked=!!state.session&&!state.session.done,template=state.templates.find(t=>t.id===selected),notes=pendingNotes(state);
 return <section className="r-feature"><h2>选择洗车方式</h2><div className="r-preset-list">{state.templates.map(t=><button disabled={locked} aria-pressed={selected===t.id} key={t.id} onClick={()=>{setState(s=>applyTemplate(s,t));setSelected(t.id);setName(t.name);}}>{t.name}</button>)}</div><p className="r-help">内置方案保留原稿。选择后可调整，另存成自己的方案；配液量需核对本瓶标签。</p><label className="r-field"><span>保存方案名称</span><input aria-label="保存方案名称" value={name} maxLength={50} onChange={e=>setName(e.target.value)}/></label><div className="r-feature-actions"><button disabled={locked||!name.trim()} onClick={()=>{setState(s=>saveTemplate(s,name));setSelected('');}}>另存为新方案</button>{template&&!template.builtIn?<button disabled={locked||!name.trim()} onClick={()=>setState(s=>saveTemplate(s,name,selected))}>更新选中方案</button>:null}</div>{template?<small className="r-help">{template.builtIn?'内置参考':'我的方案'} · 版本 {template.revision||1}</small>:null}
 {notes.length?<div className="r-note-group"><h3>这辆车，上次留下的提醒</h3>{notes.map(w=><aside className="r-next-note" key={w.id}><small>{w.name} · {w.location||'未填写地点'}</small><p>{w.notes}</p><div className="r-feature-actions"><button onClick={()=>setState(s=>setNoteStatus(s,w.id,'resolved'))}>已处理</button><button onClick={()=>setState(s=>setNoteStatus(s,w.id,'deferred'))}>下次再提醒</button>{onOpenNote?<button onClick={()=>onOpenNote(w.id)}>查看原记录</button>:null}</div></aside>)}<p className="r-help">仅显示这辆车尚未处理的事项。“下次再提醒”会在本轮洗车完成后重新出现。</p></div>:null}</section>;
}

export function VehicleSelect({state,setState,disabled}){
 const [adding,setAdding]=useState(false),[name,setName]=useState('');
 return <div className="r-vehicle-picker"><label className="r-field"><span>本次车辆</span><select aria-label="本次车辆" disabled={disabled} value={state.plan.vehicleId} onChange={e=>{const v=state.vehicles.find(v=>v.id===e.target.value);setState(s=>s.session&&!s.session.done?s:{...s,session:null,plan:{...s.plan,vehicleId:v.id,vehicle:v.name,vehicleModel:v.modelKey}});}}>{state.vehicles.map(v=><option key={v.id} value={v.id}>{v.name}</option>)}</select></label><button className="r-text-button" disabled={disabled} onClick={()=>setAdding(v=>!v)}>{adding?'取消添加':'添加另一辆车'}</button>{adding?<div className="r-vehicle-add"><input aria-label="新增车辆名称" value={name} maxLength={70} placeholder="例如：家里的另一辆车" onChange={e=>setName(e.target.value)}/><button className="r-secondary" disabled={disabled||!name.trim()} onClick={()=>{setState(s=>addVehicle(s,name));setName('');setAdding(false);}}>保存车辆</button></div>:null}</div>;
}

export function PreparationNotes({state,setState}){
 const notes=pendingNotes(state);if(!notes.length)return null;
 return <section className="r-note-group"><h3>这辆车，别忘了这些</h3>{notes.map(w=><aside className="r-next-note" key={w.id}><p>{w.notes}</p><div className="r-feature-actions"><button onClick={()=>setState(s=>setNoteStatus(s,w.id,'resolved'))}>已处理</button><button onClick={()=>setState(s=>setNoteStatus(s,w.id,'deferred'))}>下次再提醒</button></div></aside>)}</section>;
}

export function WatchTransfer({state,setState}){
 const s=state.session;if(!s||s.done||Number.isFinite(s.startedAt))return null;
 const ready=watchReady(s),error=s.watchPackage?.status==='error';
 return <section className="r-transfer" aria-label="手表方案准备状态"><span className="r-eyebrow">APPLE WATCH · 交互模拟</span><h2>{ready?'方案已在本机核验':'还差一次接收确认'}</h2><p>{ready?'本机模拟副本已确认，可以演示离线开始。':'已记录本次取用；接收方案后，再在表盘开始计时。'}</p><ol className="r-transfer-states"><li>准备清单已保存</li><li className={!ready?'muted':''}>{ready?'方案版本与内容已核验':'等待模拟手表接收'}</li><li className={!ready?'muted':''}>{ready?'离线演示已就绪':'离线演示尚未就绪'}</li></ol>{error?<p className="r-error" role="alert">{s.watchPackage.error}</p>:null}{!ready?<button className="r-secondary" onClick={()=>setState(s=>acknowledgeWatch(error?prepareWatchRetry(s):s))}>{error?'重新核验方案':'模拟接收至手表'}</button>:null}<small>尚未连接真实 Apple Watch；原生版需要手表实际保存并返回确认。</small></section>;
}

export function DataBackup({state,onRestore}){
 const [pending,setPending]=useState(null),[message,setMessage]=useState(''),[error,setError]=useState(''),[reading,setReading]=useState(false),generation=useRef(0);
 const locked=!!state.session&&!state.session.done;
 const download=()=>{try{const content=createBackup(state),url=URL.createObjectURL(new Blob([content],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=`WashMyCar-backup-${new Date().toISOString().slice(0,10)}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);setMessage('备份文件已生成，请保存在自己的设备中。');setError('');}catch(e){setError(e.message);}};
 return <section className="r-feature r-backup"><h2>资料与备份</h2><p className="r-help">把车辆、药剂、购买标签、使用履历、方案和洗车记录一起带走。备份含你填写的地点与备注，请自行保管。</p><div className="r-feature-actions"><button onClick={download}>导出完整备份</button><label className={'r-file-button'+(locked||reading?' disabled':'')}>选择备份文件<input aria-label="选择备份文件" type="file" accept=".json,application/json" disabled={locked||reading} onChange={async e=>{const file=e.target.files?.[0],g=++generation.current;e.target.value='';setPending(null);setError('');setMessage('');if(!file)return;setReading(true);try{if(file.size>MAX_BACKUP_BYTES)throw Error('备份超过12 MB，请检查文件');const data=readBackup(await file.text());if(g===generation.current)setPending(data);}catch(err){if(g===generation.current)setError(err.message);}finally{if(g===generation.current)setReading(false);}}}/></label></div>{locked?<p className="r-help">当前流程结束后可以恢复资料；现在仍可导出备份。</p>:null}{pending?<div className="r-restore-preview"><h3>核对这份备份</h3><p>{pending.summary.vehicles} 辆车 · {pending.summary.products} 瓶药剂<br/>{pending.summary.templates} 个方案 · {pending.summary.washes} 次洗车</p><p>恢复将替换本机全部资料，不合并重复记录。建议先导出当前资料。</p><div className="r-feature-actions"><button disabled={locked} onClick={()=>{try{if(locked)throw Error('请先完成当前洗车');localStorage.setItem(STORE_KEY+':before-restore',JSON.stringify(state));localStorage.setItem(STORE_KEY,JSON.stringify(pending.state));onRestore(pending.state);setPending(null);setMessage('恢复完成。车辆、库存与记录已一起更新。');setError('');}catch(err){setError('恢复未完成，原资料保留。'+err.message);}}}>确认替换本机资料</button><button onClick={()=>setPending(null)}>取消恢复</button></div></div>:null}{reading?<p role="status">正在检查备份…</p>:null}{message?<p role="status">{message}</p>:null}{error?<p role="alert" className="r-error">{error}</p>:null}<p className="r-help">本版使用 mL；照片附件与健康明细不包含在备份中。不支持的版本、单位或异常关联会阻止恢复。</p></section>;
}

export function SnapshotDetails({wash,productId}){
 const p=wash.products.find(p=>p.id===productId);if(!p)return <p>这瓶药剂的历史快照缺失。</p>;
 return <div className="r-snapshot"><p className="r-eyebrow">本次洗车 · 历史快照</p><h3>{p.brand} · {p.name}</h3><p className="r-help">保留准备时的用法和配液记录，后续编辑药剂资料不会改写这里。</p><dl><div><dt>取用总量</dt><dd>{wash.amounts[productId]} mL</dd></div><div><dt>准备前库存</dt><dd>{stockText(p)}</dd></div><div><dt>酸碱度</dt><dd>{phText(p)}</dd></div></dl>{p.ph?.source?<p className="r-help">pH 依据：{p.ph.source}</p>:null}<h3>个人记录的使用方法</h3><p className="r-preserve-text">{p.instructions||'当时尚未填写。'}</p><h3>当时的步骤与配液</h3>{wash.steps.filter(s=>s.productId===productId).map(s=><div className="r-snapshot-step" key={s.id}><strong>{s.name}</strong><p>原液 {s.amount} mL ＋ 另加清水 {s.water} mL</p><small>{s.tools.join(' · ')}</small>{s.note?<p>{s.note}</p>:null}</div>)}</div>;
}
