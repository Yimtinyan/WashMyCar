import fs from 'node:fs/promises';
import {command} from './export-previews.mjs';
const root=new URL('./',import.meta.url),device=process.argv[2]||'iphone',pageId=process.argv[3];
if(!pageId)throw Error('Usage: recover-and-wire.mjs iphone|watch pageId');
const scene=JSON.parse(await fs.readFile(new URL(device+'-scene.json',root),'utf8'));
const observed=await command('inspect',{rootId:pageId,depth:4,limit:3000});
if(observed.truncated)throw Error('Incomplete canvas read; will not infer IDs');
await fs.writeFile(new URL(device+'-inspection.json',root),JSON.stringify(observed,null,2));
const children=new Map();for(const n of observed.nodes){if(!children.has(n.parentId))children.set(n.parentId,[]);children.get(n.parentId).push(n);}
const refs={};
function match(expected,actual){if(expected.props.name!==actual.name)throw Error('Canvas/source mismatch: '+expected.ref+' / '+expected.props.name+' != '+actual.name);refs[expected.ref]=actual.id;if(expected.type==='FRAME'){const list=children.get(actual.id)||[];if(list.length!==(expected.children||[]).length)throw Error('Child count mismatch for '+expected.ref);for(let i=0;i<list.length;i++)match(expected.children[i],list[i]);}}
const actualRoots=children.get(pageId)||[];
for(const n of scene.nodes){const a=actualRoots.find(a=>a.name===n.props.name);if(!a)throw Error('Missing root '+n.ref);match(n,a);}
const result={pageId,refs,nodeCount:observed.nodes.length,recoveredFromCanvas:true};await fs.writeFile(new URL(device+'-result.json',root),JSON.stringify(result,null,2));
const nodes=[];function walk(n){if(n.reactions)nodes.push({id:refs[n.ref],reactions:n.reactions.map(r=>({...r,targetRef:undefined,...(r.targetRef?{targetId:refs[r.targetRef]}:{})}))});for(const c of n.children||[])walk(c);}scene.nodes.forEach(walk);
const flows=scene.flowStartingPoints.map(f=>({nodeId:refs[f.ref],name:f.name}));
const wire=await command('wire',{pageId,nodes,flowStartingPoints:flows});await fs.writeFile(new URL(device+'-wire-result.json',root),JSON.stringify(wire,null,2));console.log(JSON.stringify({pageId,mappedRefs:Object.keys(refs).length,links:nodes.length,flows:flows.length,mutated:wire.mutatedNodeIds?.length}));
