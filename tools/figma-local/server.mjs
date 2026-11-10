import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

export const DEFAULT_FILE='8ZDZ8qg4qoMJTtnXDQghDr';
export const OPS=new Set(['inspect','selection','fonts','patch','createText','createFrame','navigate','screenshot','overview','compose','wire','paintImage']);
export function createBridge({token=crypto.randomBytes(32).toString('hex'),port=3847,expectedFileKey=DEFAULT_FILE,commandTtlMs=60000,clientTtlMs=15000,now=()=>Date.now()}={}){
 if(typeof token!=='string'||token.length<32)throw new Error('Use a random token of at least 32 characters');
 const clients=new Map(),commands=new Map();let address;
 const error=(status,message)=>Object.assign(new Error(message),{status});
 const validId=x=>typeof x==='string'&&/^[a-zA-Z0-9:_-]{1,128}$/.test(x);
 function expire(){for(const c of commands.values())if(c.state==='queued'&&now()>c.expiresAt){c.state='expired';c.error='Command expired before delivery';}for(const [id,c]of commands)if(now()-c.createdAt>86400000)commands.delete(id);}
 function send(res,status,data){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(data));}
 async function body(req){let size=0,chunks=[];for await(const part of req){size+=part.length;if(size>16*1024*1024)throw error(413,'Request too large');chunks.push(part);}let value;try{value=JSON.parse(Buffer.concat(chunks).toString('utf8')||'{}');}catch{throw error(400,'Invalid JSON');}if(!value||typeof value!=='object'||Array.isArray(value))throw error(400,'JSON body must be an object');return value;}
 function auth(req){const value=Buffer.from(req.headers.authorization||''),expected=Buffer.from('Bearer '+token);return value.length===expected.length&&crypto.timingSafeEqual(value,expected);}
 function hostAllowed(req){const host=req.headers.host||'';return /^(?:127\.0\.0\.1|localhost)(?::\d+)?$/.test(host);}
 const server=http.createServer(async(req,res)=>{
  res.setHeader('Access-Control-Allow-Origin','*');res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');res.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type');res.setHeader('X-Content-Type-Options','nosniff');
  try{
   if(!hostAllowed(req))throw error(403,'Loopback Host required');
   const url=new URL(req.url,'http://127.0.0.1');
   if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
   if(url.pathname==='/healthz'){send(res,200,{ok:true,service:'WashMyCar Local Figma Bridge',version:'1.0.0'});return;}
   if(url.pathname==='/'&&req.method==='GET'){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Content-Security-Policy':"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"});res.end(await fs.readFile(new URL('./dashboard.html',import.meta.url),'utf8'));return;}
   if(!auth(req))throw error(401,'Session token required');
   expire();
   if(req.method==='POST'&&url.pathname==='/v1/connect'){const b=await body(req);if(!validId(b.clientId))throw error(400,'Invalid clientId');send(res,200,{ok:true,expectedFileKey});return;}
   if(req.method==='POST'&&url.pathname==='/v1/clients'){
    const b=await body(req);if(!validId(b.clientId)||typeof b.fileKey!=='string'||b.fileKey.length>128)throw error(400,'Invalid client identity');
    clients.set(b.clientId,{clientId:b.clientId,fileKey:b.fileKey,fileName:String(b.fileName||'').slice(0,200),pageId:String(b.pageId||'').slice(0,100),selection:Array.isArray(b.selection)?b.selection.slice(0,30).map(n=>({id:String(n.id).slice(0,100),name:String(n.name).slice(0,200),type:String(n.type).slice(0,30)})):[],seenAt:now()});send(res,200,{ok:true});return;
   }
   if(req.method==='GET'&&url.pathname==='/v1/status'){send(res,200,{ok:true,expectedFileKey,clients:[...clients.values()].map(c=>({...c,connected:now()-c.seenAt<clientTtlMs})),commands:[...commands.values()].map(({id,op,state,clientId,createdAt,error})=>({id,op,state,clientId,createdAt,error}))});return;}
   if(url.pathname==='/v1/commands'&&req.method==='POST'){
    const b=await body(req);if(!OPS.has(b.op))throw error(400,'Unsupported operation');if(!b.args||typeof b.args!=='object'||Array.isArray(b.args))throw error(400,'args must be an object');if(b.expectedFileKey!==expectedFileKey)throw error(403,'Unexpected target file');if(Buffer.byteLength(JSON.stringify(b.args))>(b.op==='compose'?12*1024*1024:b.op==='paintImage'?8*1024*1024:256*1024))throw error(413,'Command arguments too large');
    const queued=[...commands.values()].filter(c=>c.state==='queued').length;if(queued>=100)throw error(429,'Command queue full');
    const id=crypto.randomUUID(),c={id,op:b.op,args:b.args,expectedFileKey,createdAt:now(),expiresAt:now()+commandTtlMs,state:'queued'};commands.set(id,c);send(res,202,{id,state:c.state,expiresAt:c.expiresAt});return;
   }
   if(url.pathname==='/v1/commands'&&req.method==='GET'){
    const id=url.searchParams.get('clientId'),client=clients.get(id);if(!client||now()-client.seenAt>=clientTtlMs)throw error(409,'Register a live client first');
    const c=[...commands.values()].find(c=>c.state==='queued'&&c.expectedFileKey===client.fileKey);
    if(c){c.state='delivered';c.clientId=id;c.deliveredAt=now();}send(res,200,{command:c?{id:c.id,op:c.op,args:c.args,expectedFileKey:c.expectedFileKey}:null});return;
   }
   if(url.pathname==='/v1/results'&&req.method==='POST'){
    const b=await body(req),c=commands.get(b.id);if(!c)throw error(404,'Unknown command');if(c.clientId!==b.clientId)throw error(403,'Result belongs to another client');if(c.state==='completed'||c.state==='failed'){send(res,200,{ok:true,duplicate:true});return;}if(c.state!=='delivered')throw error(409,'Command has not been delivered');if(typeof b.ok!=='boolean')throw error(400,'ok must be a boolean');
    c.state=b.ok?'completed':'failed';c.completedAt=now();c.result=b.result;c.error=b.ok?undefined:{message:String(b.error?.message||b.error||'Plugin operation failed').slice(0,3000),partial:!!b.error?.partial,mutatedNodeIds:Array.isArray(b.error?.mutatedNodeIds)?b.error.mutatedNodeIds.slice(0,1001):[],createdNodeIds:Array.isArray(b.error?.createdNodeIds)?b.error.createdNodeIds.slice(0,5001):[],...(typeof b.error?.pageId==='string'?{pageId:b.error.pageId,refs:b.error.refs&&typeof b.error.refs==='object'?b.error.refs:{}}:{})};send(res,200,{ok:true});return;
   }
   if(url.pathname.startsWith('/v1/results/')&&req.method==='GET'){
    const c=commands.get(decodeURIComponent(url.pathname.slice(12)));if(!c)throw error(404,'Unknown command');send(res,200,{id:c.id,op:c.op,state:c.state,result:c.result,error:c.error,createdAt:c.createdAt,deliveredAt:c.deliveredAt,completedAt:c.completedAt});return;
   }
   throw error(404,'Unknown endpoint');
  }catch(e){if(!res.headersSent)send(res,e.status||500,{ok:false,error:e.status?e.message:'Internal bridge error'});else res.end();}
 });
 return {server,async start(){await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});address=server.address();return {host:'127.0.0.1',port:address.port};},async stop(){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}};
}

async function main(){const dir=new URL('./.runtime/',import.meta.url);await fs.mkdir(dir,{recursive:true});const token=crypto.randomBytes(32).toString('hex'),bridge=createBridge({token,port:Number(process.env.WMC_FIGMA_PORT||3847)});const address=await bridge.start();const connection={url:`http://127.0.0.1:${address.port}`,token,pid:process.pid,fileKey:DEFAULT_FILE,startedAt:new Date().toISOString()};await fs.writeFile(new URL('connection.json',dir),JSON.stringify(connection,null,2),{mode:0o600});console.log('Local Figma bridge listening on '+connection.url+'; pairing secret saved only to .runtime/connection.json');
 const close=async()=>{await bridge.stop();try{const x=JSON.parse(await fs.readFile(new URL('connection.json',dir),'utf8'));if(x.pid===process.pid)await fs.unlink(new URL('connection.json',dir));}catch{}process.exit(0);};process.once('SIGINT',close);process.once('SIGTERM',close);
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)main().catch(e=>{console.error(e.message);process.exitCode=1;});
