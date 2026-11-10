import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs/promises';

const source=await fs.readFile(new URL('../plugin/code.js',import.meta.url),'utf8');
function harness(){
  const messages=[],nodes=new Map(),events={},fonts=[],mutations=[];
  const page={id:'0:1',name:'Page',type:'PAGE',selection:[],children:[],appendChild(n){this.children.push(n);n.parent=this;}};nodes.set(page.id,page);
  const figma={fileKey:'test-file',root:{name:'Design',children:[page]},currentPage:page,mixed:Symbol('mixed'),ui:{postMessage:m=>messages.push(m)},showUI(){},on:(event,fn)=>events[event]=fn,getNodeByIdAsync:async id=>nodes.get(id)||null,loadFontAsync:async f=>{fonts.push({...f});},listAvailableFontsAsync:async()=>[{fontName:{family:'Inter',style:'Regular'}}],setCurrentPageAsync:async p=>{figma.currentPage=p;}};
  function node(id,type='FRAME'){
    let name=id;
    const n={id,type,x:0,y:0,width:100,height:50,visible:true,fills:[],strokes:[],strokeWeight:1,effects:[],opacity:1,constraints:{},layoutPositioning:'AUTO',layoutSizingHorizontal:'FIXED',layoutSizingVertical:'FIXED',cornerRadius:0,clipsContent:true,layoutMode:'NONE',itemSpacing:0,paddingTop:0,paddingRight:0,paddingBottom:0,paddingLeft:0,children:[],resize(w,h){mutations.push([id,'resize',w,h]);this.width=w;this.height=h;},appendChild(child){this.children.push(child);child.parent=this;},setReactionsAsync:async function(value){this.reactions=value;},exportAsync:async()=>new Uint8Array([137,80,78,71])};
    Object.defineProperty(n,'name',{get:()=>name,set:v=>{mutations.push([id,'name',v]);name=v;},enumerable:true});
    if(type==='TEXT')Object.assign(n,{characters:'old',fontName:{family:'Inter',style:'Regular',variationSettings:{wght:400,wdth:100}},fontSize:17,lineHeight:{unit:'PIXELS',value:22},letterSpacing:{unit:'PIXELS',value:0},paragraphSpacing:0,textAlignVertical:'TOP',textAlignHorizontal:'LEFT',textAutoResize:'NONE',getStyledTextSegments:()=>[{fontName:n.fontName}]});
    nodes.set(id,n);return n;
  }
  let next=1;figma.createFrame=()=>node('new:'+next++);figma.createText=()=>node('new:'+next++,'TEXT');figma.createRectangle=()=>node('new:'+next++,'RECTANGLE');figma.createEllipse=()=>node('new:'+next++,'ELLIPSE');
  figma.createPage=()=>{const p=node('new:'+next++,'PAGE');p.selection=[];p.flowStartingPoints=[];figma.root.children.push(p);return p;};figma.createImage=bytes=>({hash:'image:'+bytes.length});figma.createNodeFromSvg=()=>{const n=node('new:'+next++);n.appendChild(node('new:'+next++,'VECTOR'));return n;};
  vm.runInNewContext(source,{figma,__html__:'<div>Test plugin</div>'},{filename:'figma-local-plugin.js'});
  const send=async command=>{await figma.ui.onmessage({type:'command',command});return messages.filter(m=>m.type==='result').at(-1).response;};
  const bind=()=>figma.ui.onmessage({type:'bind'});
  return {figma,page,nodes,node,messages,fonts,mutations,send,bind};
}
const command=(id,op,args={},file='test-file')=>({id,op,args,expectedFileKey:file});

test('writes require binding to the actual file and reject mismatched targets',async()=>{
  const h=harness(),n=h.node('n1');
  assert.equal((await h.send(command('a','patch',{nodes:[{id:n.id,props:{name:'changed'}}]}))).ok,false);
  assert.equal(n.name,'n1');await h.bind();
  const mismatch=await h.send(command('b','patch',{nodes:[{id:n.id,props:{name:'changed'}}]},'other-file'));
  assert.equal(mismatch.ok,false);assert.match(mismatch.error.message,/Target file/);assert.equal(n.name,'n1');
  h.figma.fileKey=undefined;assert.equal((await h.send(command('c','createFrame',{parentId:'0:1',props:{}}))).ok,false);
});

test('patch validates every node and property before mutating any node',async()=>{
  const h=harness(),n=h.node('n1');await h.bind();
  const missing=await h.send(command('a','patch',{nodes:[{id:n.id,props:{name:'changed'}},{id:'missing',props:{name:'bad'}}]}));
  assert.equal(missing.ok,false);assert.equal(n.name,'n1');assert.equal(h.mutations.length,0);
  const forbidden=await h.send(command('b','patch',{nodes:[{id:n.id,props:{name:'changed'}},{id:n.id,props:{pluginData:'bad'}}]}));
  assert.equal(forbidden.ok,false);assert.equal(n.name,'n1');
  const dangerous=await h.send(command('c','patch',{nodes:[{id:n.id,props:{fills:[{type:'SOLID',color:{r:4,g:0,b:0}}]}}]}));
  assert.equal(dangerous.ok,false);assert.equal(h.mutations.length,0);
});

test('font preflight strips variation axes and a font-load failure prevents all writes',async()=>{
  const h=harness(),frame=h.node('frame'),text=h.node('text','TEXT');await h.bind();
  h.figma.loadFontAsync=async f=>{h.fonts.push({...f});if(f.family==='Missing')throw new Error('Font missing');};
  const failed=await h.send(command('a','patch',{nodes:[{id:frame.id,props:{name:'changed'}},{id:text.id,props:{fontName:{family:'Missing',style:'Regular'},characters:'new'}}]}));
  assert.equal(failed.ok,false);assert.match(failed.error.message,/Font missing/);assert.equal(frame.name,'frame');assert.equal(text.characters,'old');
  assert.ok(h.fonts.every(f=>Object.keys(f).sort().join(',')==='family,style'));
});

test('a file switch during asynchronous font loading cancels the pending write',async()=>{
  const h=harness(),text=h.node('text','TEXT');await h.bind();
  h.figma.loadFontAsync=async()=>{h.figma.fileKey='different-file';};
  const response=await h.send(command('a','patch',{nodes:[{id:text.id,props:{characters:'new'}}]}));
  assert.equal(response.ok,false);assert.equal(text.characters,'old');assert.equal(h.mutations.length,0);
});

test('duplicate and concurrent command IDs execute once and return the original result',async()=>{
  const h=harness(),n=h.node('n1');await h.bind();const c=command('same','patch',{nodes:[{id:n.id,props:{name:'first'}}]});
  await Promise.all([h.send(c),h.send(c)]);
  assert.equal(n.name,'first');assert.equal(h.mutations.filter(m=>m[1]==='name').length,1);
  const replay=await h.send(c);assert.equal(replay.ok,true);assert.equal(n.name,'first');
  const mismatch=await h.send({...c,args:{nodes:[{id:n.id,props:{name:'third'}}]}});assert.equal(mismatch.ok,false);assert.match(mismatch.error.message,/different contents/);assert.equal(n.name,'first');
});

test('runtime mutation failures disclose partial changes and do not rerun on replay',async()=>{
  const h=harness(),n=h.node('n1');await h.bind();n.resize=()=>{throw new Error('Resize rejected');};
  const c=command('partial','patch',{nodes:[{id:n.id,props:{name:'changed',width:200}}]});const result=await h.send(c);
  assert.equal(result.ok,false);assert.equal(result.error.partial,true);assert.equal(n.name,'changed');assert.deepEqual(Array.from(result.error.mutatedNodeIds),['n1']);
  const count=h.mutations.length;await h.send(c);assert.equal(h.mutations.length,count);
});

test('inspection is bounded and screenshot returns image bytes without executing scripts',async()=>{
  const h=harness(),n=h.node('frame');h.page.appendChild(n);n.appendChild(h.node('text','TEXT'));await h.bind();
  const inspect=await h.send(command('a','inspect',{rootId:'0:1',depth:4,limit:2}));assert.equal(inspect.ok,true);assert.equal(inspect.result.nodes.length,2);assert.equal(inspect.result.truncated,true);
  const image=await h.send(command('b','screenshot',{rootId:n.id,width:300}));assert.equal(image.ok,true);assert.equal(image.result.base64,'iVBORw==');
  const forbidden=await h.send(command('c','eval',{code:'figma.root.remove()'}));assert.equal(forbidden.ok,false);assert.match(forbidden.error.message,/Operation not allowed/);
});

const png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII=';
const scene=()=>({pageName:'V2 · iPhone',assets:{hero:{mimeType:'image/png',base64:png}},nodes:[
  {ref:'home',type:'FRAME',props:{name:'Home',width:440,height:956,layoutMode:'VERTICAL'},children:[
    {ref:'title',type:'TEXT',props:{characters:'洗车计划',fontName:{family:'Inter',style:'Regular'},fontSize:28,letterSpacing:{unit:'PIXELS',value:-0.5},textAlignVertical:'CENTER',layoutSizingHorizontal:'FILL'},reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetRef:'detail',transition:{type:'DISSOLVE',duration:0.2}}]},
    {ref:'photo',type:'RECTANGLE',props:{width:200,height:140,cornerRadius:16},image:{assetRef:'hero',scaleMode:'FIT'}},
    {ref:'dot',type:'ELLIPSE',props:{width:8,height:8,fills:[{type:'SOLID',color:{r:0.2,g:0.4,b:0.5}}]}},
    {ref:'icon',type:'SVG',svg:'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000"><path d="M2 2L20 20" /></svg>',props:{width:20,height:20}}
  ]},
  {ref:'detail',type:'FRAME',props:{name:'Detail',width:440,height:956,x:520,layoutMode:'NONE'}}
],flowStartingPoints:[{ref:'home',name:'主流程'},{ref:'detail',name:'药剂检视'}]});

test('compose builds native nested scenes, PNG fills, SVG icons, links and multiple flow starts',async()=>{
  const h=harness();await h.bind();const response=await h.send(command('scene','compose',scene()));assert.equal(response.ok,true,response.error?.message);
  const {refs,pageId,createdNodeIds}=response.result,p=h.nodes.get(pageId);assert.equal(p.name,'V2 · iPhone');assert.equal(p.children.length,2);assert.equal(h.page.children.length,0);
  assert.equal(h.nodes.get(refs.home).width,440);assert.equal(h.nodes.get(refs.title).characters,'洗车计划');assert.equal(h.nodes.get(refs.photo).fills[0].type,'IMAGE');assert.equal(h.nodes.get(refs.photo).fills[0].scaleMode,'FIT');
  assert.equal(h.nodes.get(refs.title).reactions[0].actions[0].destinationId,refs.detail);assert.equal(p.flowStartingPoints.length,2);assert.equal(new Set(createdNodeIds).size,createdNodeIds.length);assert.equal(createdNodeIds.length,8);
  const repeat=await h.send(command('scene','compose',scene()));assert.equal(repeat.ok,true);assert.equal(h.figma.root.children.length,2);
});

test('compose preflights every node, ref, image, destination, SVG and font before canvas creation',async()=>{
  const invalids=[
    s=>s.nodes.push({ref:'home',type:'FRAME'}),
    s=>s.nodes[1].props.remove=true,
    s=>s.nodes[0].children[0].reactions[0].targetRef='missing',
    s=>s.nodes[0].children[1].image.assetRef='missing',
    s=>s.assets.hero.base64='a'.repeat(100),
    s=>s.nodes[0].children[3].svg='<svg><script>alert(1)</script></svg>',
    s=>s.nodes[0].children[3].svg='<svg><use href="http://example.com/x" /></svg>',
    s=>s.nodes[0].children[3].svg='<svg><path onclick="oops()" d="M0 0" /></svg>',
    s=>s.nodes[1].props.layoutSizingHorizontal='FILL',
    s=>s.flowStartingPoints.push({ref:'title',name:'invalid'})
  ];
  for(let i=0;i<invalids.length;i++){const h=harness();await h.bind();const args=scene();invalids[i](args);const r=await h.send(command('invalid'+i,'compose',args));assert.equal(r.ok,false,'case '+i);assert.equal(h.figma.root.children.length,1);assert.equal(h.nodes.size,1);assert.equal(h.mutations.length,0);}
  const h=harness();await h.bind();h.figma.loadFontAsync=async()=>{throw new Error('Missing font');};const r=await h.send(command('font-fail','compose',scene()));assert.equal(r.ok,false);assert.equal(h.nodes.size,1);
});

test('compose appends without replacing old nodes and validates cross-batch links and image reuse',async()=>{
  const h=harness(),old=h.node('old');old.fills=[{type:'IMAGE',imageHash:'old-hash',scaleMode:'FILL'}];h.page.appendChild(old);await h.bind();
  const r=await h.send(command('append','compose',{pageId:h.page.id,nodes:[{ref:'new',type:'FRAME',props:{width:208,height:248},children:[{ref:'photo',type:'RECTANGLE',image:{nodeId:old.id},reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:old.id}]}]}]}));
  assert.equal(r.ok,true,r.error?.message);assert.equal(h.page.children.length,2);assert.equal(h.nodes.get(r.result.refs.photo).fills[0].imageHash,'old-hash');assert.equal(h.page.children[0],old);
  const other=h.node('other-page','PAGE');h.nodes.set(other.id,other);old.parent=other;const denied=await h.send(command('cross-page','compose',{pageId:h.page.id,nodes:[{ref:'new',type:'FRAME',reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:old.id}]}]}));assert.equal(denied.ok,false);assert.match(denied.error.message,/compose page/);
});

test('compose reports every created id on runtime failure, and replay never creates a second page',async()=>{
  const h=harness();await h.bind();h.figma.createRectangle=()=>{throw new Error('Native factory rejected');};const c=command('partial-scene','compose',scene());const r=await h.send(c);assert.equal(r.ok,false);assert.equal(r.error.partial,true);assert.equal(r.error.createdNodeIds.length,3);assert.equal(Object.keys(r.error.refs).length,2);assert.ok(r.error.pageId);
  await h.send(c);assert.equal(h.figma.root.children.length,2);
});

test('compose node budget and identity checks reject writes while overview remains bounded',async()=>{
  const h=harness();await h.bind();const denied=await h.send(command('wrong','compose',scene(),'other'));assert.equal(denied.ok,false);assert.equal(h.nodes.size,1);
  const huge=await h.send(command('huge','compose',{nodes:Array.from({length:5001},(_,i)=>({ref:'n'+i,type:'ELLIPSE'}))}));assert.equal(huge.ok,false);assert.match(huge.error.message,/5000/);assert.equal(h.nodes.size,1);
  const overview=await h.send(command('overview','overview'));assert.equal(overview.ok,true);assert.equal(overview.result.pages.length,1);assert.equal(overview.result.pages[0].id,h.page.id);
});

test('compose diagnostics identify image and font API failures without disclosing asset data',async()=>{
  const h=harness();await h.bind();h.figma.createImage=()=>{throw new Error('not an object');};
  const image=await h.send(command('native-image','compose',scene()));assert.equal(image.ok,false);assert.match(image.error.message,/createImage \[hero, \d+ bytes\]: not an object/);assert.equal(image.error.partial,false);assert.equal(h.nodes.size,1);assert.equal(image.error.message.includes(png),false);
  const f=harness();await f.bind();f.figma.loadFontAsync=async()=>{throw Object.freeze({message:'Native font rejected'});};const font=await f.send(command('native-font','compose',scene()));assert.equal(font.ok,false);assert.match(font.error.message,/compose preflight: font preload \[Inter \/ Regular\]: Native font rejected/);assert.equal(f.nodes.size,1);
});

test('compose wraps primitive or non-extensible native failures before adding partial metadata',async()=>{
  const h=harness();await h.bind();h.figma.createPage=()=>{throw null;};const response=await h.send(command('primitive','compose',scene()));assert.equal(response.ok,false);assert.equal(response.error.partial,false);assert.match(response.error.message,/compose canvas: createPage: null/);assert.equal(response.error.createdNodeIds.length,0);
});

test('wire replaces existing reactions and flow starts without creating nodes, and can be repeated',async()=>{
  const h=harness(),home=h.node('home'),detail=h.node('detail'),button=h.node('button','TEXT');h.page.appendChild(home);h.page.appendChild(detail);home.appendChild(button);await h.bind();const before=h.nodes.size;
  const args={pageId:h.page.id,nodes:[{id:button.id,reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:detail.id,transition:{type:'SMART_ANIMATE',duration:0.2}}]}],flowStartingPoints:[{nodeId:home.id,name:'主流程'},{nodeId:detail.id,name:'详情'}]};
  const wired=await h.send(command('wire1','wire',args));assert.equal(wired.ok,true,wired.error?.message);assert.equal(button.reactions[0].actions[0].destinationId,detail.id);assert.equal(h.page.flowStartingPoints.length,2);assert.equal(h.nodes.size,before);
  assert.equal((await h.send(command('wire2','wire',args))).ok,true);assert.equal(h.page.flowStartingPoints.length,2);assert.equal(h.nodes.size,before);
  assert.equal((await h.send(command('clear','wire',{pageId:h.page.id,nodes:[{id:button.id,reactions:[]}],flowStartingPoints:[]}))).ok,true);assert.equal(button.reactions.length,0);assert.equal(h.page.flowStartingPoints.length,0);
});

test('wire preflights all destinations and sources on the declared page before changing anything',async()=>{
  const h=harness(),home=h.node('home'),button=h.node('button','TEXT'),other=h.node('other','PAGE'),foreign=h.node('foreign');h.page.appendChild(home);home.appendChild(button);other.appendChild(foreign);await h.bind();
  const response=await h.send(command('bad-wire','wire',{pageId:h.page.id,nodes:[{id:button.id,reactions:[]},{id:home.id,reactions:[{trigger:'ON_CLICK',navigation:'NAVIGATE',targetId:foreign.id}]}]}));assert.equal(response.ok,false);assert.equal(button.reactions,undefined);assert.equal(home.reactions,undefined);
  const source=await h.send(command('foreign-source','wire',{pageId:h.page.id,nodes:[{id:foreign.id,reactions:[]}]}));assert.equal(source.ok,false);assert.match(source.error.message,/declared page/);
});

test('wire and compose link failures retain affected ids and an explicit reaction stage',async()=>{
  const h=harness(),home=h.node('home');h.page.appendChild(home);await h.bind();home.setReactionsAsync=async()=>{throw Object.freeze({message:'not an object'});};
  const wired=await h.send(command('wire-fail','wire',{pageId:h.page.id,nodes:[{id:home.id,reactions:[]}]}));assert.equal(wired.ok,false);assert.equal(wired.error.partial,true);assert.match(wired.error.message,/wire reactions \[home\]: not an object/);assert.deepEqual(Array.from(wired.error.mutatedNodeIds),['home']);assert.equal(wired.error.pageId,h.page.id);
  const c=harness();await c.bind();const create=c.figma.createText;c.figma.createText=()=>{const n=create();n.setReactionsAsync=async()=>{throw new Error('Native link error');};return n;};const composed=await c.send(command('compose-links','compose',scene()));assert.equal(composed.ok,false);assert.equal(composed.error.partial,true);assert.match(composed.error.message,/reactions \[title, new:/);assert.equal(composed.error.createdNodeIds.length,8);assert.equal(Object.keys(composed.error.refs).length,6);assert.ok(composed.error.pageId);
});

test('inspection supports 3000 nodes with parent ids for recovering a completed scene',async()=>{
  const h=harness();for(let i=0;i<400;i++)h.page.appendChild(h.node('child:'+i));const response=await h.send(command('recover','inspect',{rootId:h.page.id,depth:4,limit:3000}));assert.equal(response.ok,true);assert.equal(response.result.nodes.length,401);assert.equal(response.result.truncated,false);assert.equal(response.result.nodes[1].parentId,h.page.id);
});

test('result transport failure preserves the completed operation ids instead of suggesting a clean failure',async()=>{
  const h=harness();await h.bind();const post=h.figma.ui.postMessage;let failed=false;h.figma.ui.postMessage=m=>{if(m.type==='result'&&m.response.ok&&!failed){failed=true;throw new Error('Native transport rejected');}post(m);};
  const response=await h.send(command('transport','compose',scene()));assert.equal(response.ok,false);assert.equal(response.error.partial,true);assert.equal(response.error.createdNodeIds.length,8);assert.equal(Object.keys(response.error.refs).length,6);assert.ok(response.error.pageId);assert.match(response.error.message,/Result transport failed/);
});

test('paintImage replaces a native shape fill while preserving every child and creating no UI nodes',async()=>{
  const h=harness(),bottle=h.node('bottle'),vector=h.node('vector','VECTOR');h.page.appendChild(bottle);bottle.appendChild(vector);await h.bind();const size=h.nodes.size;
  const r=await h.send(command('paint','paintImage',{nodeId:bottle.id,asset:{mimeType:'image/png',base64:png},scaleMode:'FIT'}));assert.equal(r.ok,true,r.error?.message);assert.deepEqual(Array.from(r.result.mutatedNodeIds),[bottle.id]);assert.equal(bottle.fills[0].type,'IMAGE');assert.equal(bottle.fills[0].scaleMode,'FIT');assert.equal(h.nodes.size,size);assert.equal(bottle.children[0],vector);assert.equal(vector.visible,true);
});

test('paintImage rejects target identity, node type and invalid PNG before native image creation',async()=>{
  const h=harness(),frame=h.node('frame'),text=h.node('text','TEXT');await h.bind();let imageCalls=0;h.figma.createImage=()=>{imageCalls++;return {hash:'hash'};};
  const args={nodeId:frame.id,asset:{mimeType:'image/png',base64:png},scaleMode:'FILL'};
  assert.equal((await h.send(command('wrong-file-paint','paintImage',args,'wrong'))).ok,false);
  assert.equal((await h.send(command('text-paint','paintImage',{...args,nodeId:text.id}))).ok,false);
  assert.equal((await h.send(command('invalid-png-paint','paintImage',{...args,asset:{mimeType:'image/png',base64:'AAAA'}}))).ok,false);
  assert.equal((await h.send(command('invalid-mode-paint','paintImage',{...args,scaleMode:'CROP'}))).ok,false);
  assert.equal(imageCalls,0);assert.equal(frame.fills.length,0);
});

test('paintImage discloses a partial fill-write failure and deduplicates command replay',async()=>{
  const h=harness(),frame=h.node('frame');await h.bind();let writes=0;Object.defineProperty(frame,'fills',{get:()=>[],set:()=>{writes++;throw Object.freeze({message:'Native fill rejected'});}});const c=command('paint-fail','paintImage',{nodeId:frame.id,asset:{mimeType:'image/png',base64:png},scaleMode:'FIT'});
  const r=await h.send(c);assert.equal(r.ok,false);assert.equal(r.error.partial,true);assert.deepEqual(Array.from(r.error.mutatedNodeIds),[frame.id]);assert.match(r.error.message,/paintImage set fills \[frame\]: Native fill rejected/);await h.send(c);assert.equal(writes,1);
});
