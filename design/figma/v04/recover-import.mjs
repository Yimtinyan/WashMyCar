import fs from 'node:fs/promises';import{command}from'../v2/export-previews.mjs';
const root=new URL('./',import.meta.url),c=JSON.parse(await fs.readFile(new URL('../../../tools/figma-local/.runtime/connection.json',import.meta.url),'utf8'));
const receipt=await fetch(c.url+'/v1/results/26c6db05-bb90-40a4-bd95-b315a1e370bb',{headers:{Authorization:'Bearer '+c.token}}).then(r=>r.json());
const error=receipt.error;if(!error?.refs||!error.pageId)throw Error('Missing recovery mapping');
const scene=JSON.parse(await fs.readFile(new URL('iphone-scene.json',root),'utf8'));
await fs.writeFile(new URL('iphone-result.json',root),JSON.stringify({pageId:error.pageId,refs:error.refs,createdNodeIds:error.createdNodeIds,recovered:true},null,2));
await command('wire',{pageId:error.pageId,nodes:[],flowStartingPoints:scene.flowStartingPoints.map(f=>({nodeId:error.refs[f.ref],name:f.name}))});console.log('Recovered complete phone page '+error.pageId);
const ws=JSON.parse(await fs.readFile(new URL('watch-scene.json',root),'utf8'));const flows=ws.flowStartingPoints;delete ws.flowStartingPoints;
const wr=await command('compose',ws);await fs.writeFile(new URL('watch-result.json',root),JSON.stringify(wr,null,2));await command('wire',{pageId:wr.pageId,nodes:[],flowStartingPoints:flows.map(f=>({nodeId:wr.refs[f.ref],name:f.name}))});console.log('Watch page '+wr.pageId);
