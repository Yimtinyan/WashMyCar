import fs from 'node:fs/promises';import{command}from'../v2/export-previews.mjs';
const root=new URL('./',import.meta.url),read=async p=>JSON.parse(await fs.readFile(new URL(p,root),'utf8'));
try{await fs.access(new URL('iphone-result.json',root));throw Error('Already imported. Inspect the existing canvas; do not rerun the import.');}catch(e){if(e.code!=='ENOENT')throw e;}
const patch=await read('patch.json');const patched=await command('patch',patch);await fs.writeFile(new URL('patch-result.json',root),JSON.stringify(patched,null,2));
const scene=await read('iphone-scene.json');const result=await command('compose',scene);await fs.writeFile(new URL('iphone-result.json',root),JSON.stringify(result,null,2));console.log(JSON.stringify({pageId:result.pageId,frames:scene.nodes.length,created:result.createdNodeIds.length}));
const old=await read('../v04/iphone-result.json');const additions=[{...(await read('settings-row.json')),parentId:old.refs.P11},...(await read('existing-links.json'))];const created=[];const wires=[];
async function append(n,parentId){const op=n.type==='TEXT'?'createText':'createFrame';const r=await command(op,{parentId,props:n.props});const id=r.node.id;created.push(id);await fs.writeFile(new URL('append-result.json',root),JSON.stringify({createdNodeIds:created,wires},null,2));for(const c of n.children||[])await append(c,id);if(n.reactions)wires.push({id:id,reactions:n.reactions.map(x=>({...x,targetId:x.targetId||result.refs[x.targetRef],targetRef:undefined}))});return id;}
for(const n of additions)await append(n,n.parentId);
wires.push({id:old.refs['frame-309'],reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:result.refs.P37}]});
wires.push({id:old.refs['frame-382'],reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:result.refs.P36}]});
wires.push({id:old.refs['frame-387'],reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:result.refs.P36}]});
const wired=await command('wire',{pageId:result.pageId,nodes:wires});await fs.writeFile(new URL('append-result.json',root),JSON.stringify({createdNodeIds:created,wires,result:wired},null,2));console.log('Linked existing settings, plan, bottle and history pages');
