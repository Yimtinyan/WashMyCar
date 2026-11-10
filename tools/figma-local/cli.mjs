import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const conn=JSON.parse(await fs.readFile(new URL('./.runtime/connection.json',import.meta.url),'utf8'));
if(!/^http:\/\/127\.0\.0\.1:\d+$/.test(conn.url))throw new Error('Refusing non-loopback connection');
const [cmd,...argv]=process.argv.slice(2);
const request=async(method,path,body)=>{const r=await fetch(conn.url+path,{method,headers:{Authorization:'Bearer '+conn.token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const x=await r.json();if(!r.ok)throw new Error(x.error||r.status);return x;};
if(cmd==='status'){console.log(JSON.stringify(await request('GET','/v1/status'),null,2));}
else if(cmd==='command'){
 const op=argv[0],filename=argv[1];const args=filename?JSON.parse(await fs.readFile(filename,'utf8')):{};
 const x=await request('POST','/v1/commands',{op,args,expectedFileKey:conn.fileKey});console.log('Queued '+x.id+' ('+op+').');
 const deadline=Date.now()+65000;while(Date.now()<deadline){const result=await request('GET','/v1/results/'+x.id);if(['completed','failed','expired'].includes(result.state)){if(op==='screenshot'&&result.result?.base64){const destination=argv[2];if(!destination)throw new Error('Screenshot needs an output path as third argument');await fs.writeFile(destination,Buffer.from(result.result.base64,'base64'));result.result={...result.result,base64:undefined,savedTo:destination};}console.log(JSON.stringify(result,null,2));if(result.state!=='completed')process.exitCode=1;break;}await new Promise(resolve=>setTimeout(resolve,500));if(Date.now()>=deadline){console.error('No result yet. A delivered write is NOT automatically retried; inspect status before issuing it again.');process.exitCode=1;}}
}else if(cmd==='result'){console.log(JSON.stringify(await request('GET','/v1/results/'+argv[0]),null,2));}
else if(cmd==='open'){
 const {spawn}=await import('node:child_process');const address=conn.url+'/#token='+encodeURIComponent(conn.token);spawn('explorer.exe',[address],{windowsHide:true,detached:true,stdio:'ignore'}).unref();console.log('Opened the local pairing page.');
}else{console.log('Usage: node cli.mjs status | open | command <operation> [args.json] [screenshot-output.png] | result <id>');process.exitCode=1;}
