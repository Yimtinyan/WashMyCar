import fs from 'node:fs/promises';
const root=new URL('./',import.meta.url);
const conn=JSON.parse(await fs.readFile(new URL('../../../tools/figma-local/.runtime/connection.json',import.meta.url),'utf8'));
if(!/^http:\/\/127\.0\.0\.1:\d+$/.test(conn.url))throw Error('Unexpected bridge host');
async function request(method,path,body){const r=await fetch(conn.url+path,{method,headers:{Authorization:'Bearer '+conn.token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const value=await r.json();if(!r.ok)throw Error(JSON.stringify(value));return value;}
export async function command(op,args){const q=await request('POST','/v1/commands',{op,args,expectedFileKey:conn.fileKey});const deadline=Date.now()+75000;while(Date.now()<deadline){const r=await request('GET','/v1/results/'+q.id);if(r.state==='failed'||r.state==='expired')throw Error(JSON.stringify({id:q.id,state:r.state,error:r.error}));if(r.state==='completed')return r.result;await new Promise(resolve=>setTimeout(resolve,400));}throw Error('Result unknown; inspect command '+q.id+' before repeating');}
if(process.argv[2]==='export'){
 const device=process.argv[3],ids=process.argv.slice(4),mapping=JSON.parse(await fs.readFile(new URL(device+'-result.json',root),'utf8'));
 await fs.mkdir(new URL('previews/',root),{recursive:true});
 for(const ref of ids){const node=mapping.refs[ref];if(!node)throw Error('Unknown reference '+ref);const r=await command('screenshot',{rootId:node,width:device==='watch'?416:880});await fs.writeFile(new URL('previews/'+device+'-'+ref+'.png',root),Buffer.from(r.base64,'base64'));console.log(ref+' exported · '+r.bytes+' bytes');}
}
