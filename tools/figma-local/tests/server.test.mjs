import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {createBridge} from '../server.mjs';

const TOKEN='a'.repeat(64);
async function fixture(t,options={}){
  let clock=1000;
  const bridge=createBridge({token:TOKEN,port:0,expectedFileKey:'test-file',now:()=>clock,...options});
  const address=await bridge.start();t.after(()=>bridge.stop());
  const request=(method,path,body,headers={})=>new Promise((resolve,reject)=>{
    const payload=body===undefined?null:typeof body==='string'?body:JSON.stringify(body);
    const req=http.request({hostname:'127.0.0.1',port:address.port,method,path,headers:{Authorization:'Bearer '+TOKEN,...payload!==null?{'Content-Type':'application/json','Content-Length':Buffer.byteLength(payload)}:{},...headers}},res=>{
      let data='';res.setEncoding('utf8');res.on('data',x=>data+=x);res.on('end',()=>{let parsed;try{parsed=JSON.parse(data);}catch{}resolve({status:res.statusCode,headers:res.headers,body:parsed,raw:data});});
    });req.on('error',reject);req.end(payload);
  });
  const register=(id='plugin-one',fileKey='test-file')=>request('POST','/v1/clients',{clientId:id,fileKey,fileName:'Test design',pageId:'0:1',selection:[]});
  const enqueue=(op='inspect',args={})=>request('POST','/v1/commands',{op,args,expectedFileKey:'test-file'});
  return {bridge,address,request,register,enqueue,advance:n=>{clock+=n;}};
}

test('binds loopback only; status and commands require the session token',async t=>{
  const f=await fixture(t);assert.equal(f.bridge.server.address().address,'127.0.0.1');
  for(const [method,path,body] of [['GET','/v1/status'],['GET','/v1/commands?clientId=plugin-one'],['POST','/v1/commands',{op:'inspect',args:{},expectedFileKey:'test-file'}]]){
    assert.equal((await f.request(method,path,body,{Authorization:''})).status,401);
  }
  assert.equal((await f.request('GET','/v1/status')).status,200);
  assert.equal((await f.request('GET','/v1/status',undefined,{Authorization:'Bearer '+'é'.repeat(64)})).status,401);
  const health=await f.request('GET','/healthz',undefined,{Authorization:''});assert.equal(health.status,200);assert.equal('token' in health.body,false);assert.equal('clients' in health.body,false);
});

test('rejects hostile Host headers and permits authenticated null-origin plugin requests',async t=>{
  const f=await fixture(t);
  assert.equal((await f.request('GET','/v1/status',undefined,{Host:'attacker.example'})).status,403);
  assert.equal((await f.request('GET','/v1/status',undefined,{Host:'localhost.attacker.example'})).status,403);
  const preflight=await f.request('OPTIONS','/v1/commands',undefined,{Authorization:'',Origin:'null','Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,content-type'});
  assert.equal(preflight.status,204);assert.equal(preflight.headers['access-control-allow-origin'],'*');assert.match(preflight.headers['access-control-allow-headers'],/Authorization/i);
  assert.equal(preflight.headers['access-control-allow-credentials'],undefined);
  assert.equal((await f.request('GET','/v1/status',undefined,{Origin:'null'})).status,200);
});

test('validates malformed requests, unsupported operations and target identity',async t=>{
  const f=await fixture(t);
  assert.equal((await f.request('POST','/v1/connect',{clientId:'bad id'})).status,400);
  assert.equal((await f.request('POST','/v1/commands','{broken')).status,400);
  assert.equal((await f.request('POST','/v1/commands','null')).status,400);
  assert.equal((await f.request('POST','/v1/commands','[]')).status,400);
  assert.equal((await f.request('POST','/v1/commands',{op:'eval',args:{code:'bad'},expectedFileKey:'test-file'})).status,400);
  assert.equal((await f.request('POST','/v1/commands',{op:'patch',args:[],expectedFileKey:'test-file'})).status,400);
  assert.equal((await f.request('POST','/v1/commands',{op:'patch',args:{},expectedFileKey:'other-file'})).status,403);
  assert.equal((await f.request('POST','/v1/commands',{op:'inspect',args:{query:'x'.repeat(262145)},expectedFileKey:'test-file'})).status,413);
});

test('only a live matching-file client receives a command; delivered commands are not redelivered',async t=>{
  const f=await fixture(t);await f.register('wrong-file','other-file');await f.register();
  const queued=await f.enqueue('patch',{nodes:[{id:'1:2',props:{name:'new'}}]});assert.equal(queued.status,202);
  assert.equal((await f.request('GET','/v1/commands?clientId=wrong-file')).body.command,null);
  const delivered=await f.request('GET','/v1/commands?clientId=plugin-one');assert.equal(delivered.body.command.id,queued.body.id);
  assert.deepEqual(delivered.body.command.args,{nodes:[{id:'1:2',props:{name:'new'}}]});
  assert.equal((await f.request('GET','/v1/commands?clientId=plugin-one')).body.command,null);
  assert.equal((await f.request('GET','/v1/commands?clientId=missing')).status,409);
  f.advance(15001);assert.equal((await f.request('GET','/v1/commands?clientId=plugin-one')).status,409);
  await f.register();assert.equal((await f.request('GET','/v1/commands?clientId=plugin-one')).body.command,null);
});

test('result ownership and duplicate acknowledgements preserve the first final result',async t=>{
  const f=await fixture(t);await f.register();const q=await f.enqueue();await f.request('GET','/v1/commands?clientId=plugin-one');
  assert.equal((await f.request('POST','/v1/results',{clientId:'other',id:q.body.id,ok:true,result:{stolen:true}})).status,403);
  assert.equal((await f.request('POST','/v1/results',{clientId:'plugin-one',id:q.body.id,ok:'yes'})).status,400);
  assert.equal((await f.request('POST','/v1/results',{clientId:'plugin-one',id:q.body.id,ok:true,result:{nodes:[{id:'1:2'}]}})).status,200);
  const duplicate=await f.request('POST','/v1/results',{clientId:'plugin-one',id:q.body.id,ok:false,error:'overwrite'});assert.equal(duplicate.body.duplicate,true);
  const result=await f.request('GET','/v1/results/'+q.body.id);assert.equal(result.body.state,'completed');assert.deepEqual(result.body.result,{nodes:[{id:'1:2'}]});assert.equal(result.body.error,undefined);
});

test('queued commands expire; delayed delivered writes remain non-retryable',async t=>{
  const f=await fixture(t,{commandTtlMs:50});await f.register();const q=await f.enqueue();f.advance(51);
  assert.equal((await f.request('GET','/v1/commands?clientId=plugin-one')).body.command,null);
  assert.equal((await f.request('GET','/v1/results/'+q.body.id)).body.state,'expired');
  const q2=await f.enqueue('patch',{nodes:[]});const c=await f.request('GET','/v1/commands?clientId=plugin-one');assert.equal(c.body.command.id,q2.body.id);f.advance(100);
  assert.equal((await f.request('GET','/v1/commands?clientId=plugin-one')).body.command,null);
  assert.equal((await f.request('GET','/v1/results/'+q2.body.id)).body.state,'delivered');
});

test('the queue is bounded and status never exposes the bearer token',async t=>{
  const f=await fixture(t);for(let i=0;i<100;i++)assert.equal((await f.enqueue()).status,202);
  assert.equal((await f.enqueue()).status,429);
  const status=await f.request('GET','/v1/status');assert.equal(status.body.commands.length,100);assert.equal(JSON.stringify(status.body).includes(TOKEN),false);
});

test('compose accepts large declarative payloads up to 12 MiB while patch stays small',async t=>{
  const f=await fixture(t);const large={nodes:[],assets:{sample:{mimeType:'image/png',base64:'a'.repeat(300000)}}};
  assert.equal((await f.enqueue('compose',large)).status,202);assert.equal((await f.enqueue('patch',large)).status,413);
  assert.equal((await f.enqueue('compose',{nodes:[],padding:'x'.repeat(12*1024*1024)})).status,413);
  assert.equal((await f.enqueue('overview',{})).status,202);
  assert.equal((await f.enqueue('wire',{pageId:'0:1',nodes:[]})).status,202);
});

test('partial compose results preserve all created ids and reference mapping',async t=>{
  const f=await fixture(t);await f.register();const q=await f.enqueue('compose',{nodes:[]});await f.request('GET','/v1/commands?clientId=plugin-one');
  const ids=Array.from({length:5001},(_,i)=>'new:'+i),mutated=ids.slice(0,1001),refs={home:'new:1',detail:'new:2'};
  assert.equal((await f.request('POST','/v1/results',{clientId:'plugin-one',id:q.body.id,ok:false,error:{message:'Native error',partial:true,pageId:'new:0',createdNodeIds:ids,mutatedNodeIds:mutated,refs}})).status,200);
  const result=await f.request('GET','/v1/results/'+q.body.id);assert.equal(result.body.error.partial,true);assert.deepEqual(result.body.error.createdNodeIds,ids);assert.deepEqual(result.body.error.mutatedNodeIds,mutated);assert.deepEqual(result.body.error.refs,refs);assert.equal(result.body.error.pageId,'new:0');
});

test('paintImage has a dedicated 8 MiB command limit without widening other operations',async t=>{
  const f=await fixture(t);const args={nodeId:'1:2',asset:{mimeType:'image/png',base64:'a'.repeat(300000)},scaleMode:'FIT'};assert.equal((await f.enqueue('paintImage',args)).status,202);assert.equal((await f.enqueue('patch',args)).status,413);assert.equal((await f.enqueue('paintImage',{...args,padding:'x'.repeat(8*1024*1024)})).status,413);
});
