import fs from 'node:fs/promises';
import {command} from './export-previews.mjs';
const root=new URL('./',import.meta.url),scene=JSON.parse(await fs.readFile(new URL('iphone-scene.json',root),'utf8')),pageId='15:97';
const current=await command('inspect',{rootId:pageId,depth:1,limit:100});
const existing=Object.fromEntries(current.nodes.filter(n=>/^P\d\d \//.test(n.name)).map(n=>[n.name.slice(0,3),n.id]));
const additions=scene.nodes.filter(n=>['P20','P21'].includes(n.ref)&&!existing[n.ref]);
if(additions.length){const imported=structuredClone(additions),newRefs=new Set(imported.map(n=>n.ref));function resolve(n){for(const r of n.reactions||[])if(r.targetRef&&!newRefs.has(r.targetRef)){if(!existing[r.targetRef])throw Error('Missing linked root '+r.targetRef);r.targetId=existing[r.targetRef];delete r.targetRef;}for(const c of n.children||[])resolve(c);}imported.forEach(resolve);const result=await command('compose',{pageId,assets:{fireball:scene.assets.fireball},nodes:imported});await fs.writeFile(new URL('phone-additions-result.json',root),JSON.stringify(result,null,2));console.log('Added '+additions.length+' bottle states.');}else console.log('Bottle states already present.');
