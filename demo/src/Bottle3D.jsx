import {stockKind,stockText} from './reliability.js';
import React,{useEffect,useRef,useState,memo} from 'react';
import * as T from 'three';
import {RoomEnvironment} from 'three/addons/environments/RoomEnvironment.js';

// Volume-integrated profile: the fill height includes the narrower shoulder.
const profile=[[0,.07],[.61,.07],[.68,.14],[.69,.3],[.69,1.87],[.67,2.03],[.55,2.18],[.27,2.3],[.24,2.36],[.24,2.53],[0,2.53]];
function radius(y){if(y<.14)return .61+(y-.07)/.07*.07;if(y<=1.87)return .69;for(let i=4;i<profile.length-2;i++){let [r0,y0]=profile[i],[r1,y1]=profile[i+1];if(y>=y0&&y<=y1)return r0+(r1-r0)*(y-y0)/(y1-y0);}return .24;}
export function liquidHeight(fraction){const slices=250,dy=2.27/slices;let total=0,vol=[];for(let i=0;i<slices;i++){total+=Math.PI*radius(.08+(i+.5)*dy)**2*dy;vol.push(total);}const target=total*Math.max(0,Math.min(1,fraction));const i=vol.findIndex(v=>v>=target);return fraction<=0?.08:.08+(i<0?slices:i+1)*dy;}
function texture(product){const c=document.createElement('canvas');c.width=768;c.height=512;const x=c.getContext('2d'),koch=product.shape==='koch'||product.brand==='Koch-Chemie',fireball=product.shape==='fireball'||product.brand==='Fireball';x.fillStyle=koch?'#f0efe4':fireball?'#b2bbae':'#18372f';x.fillRect(0,0,768,512);x.fillStyle=koch||fireball?'#253d31':'#edf1e7';x.font='400 45px Arial';x.fillText(product.brand,38,78);x.fillStyle=koch?'#d5d18a':fireball?'#718c79':'#91a998';x.fillRect(39,117,690,5);x.fillStyle=koch||fireball?'#253d31':'#edf1e7';x.font=koch?'500 128px Arial':fireball?'400 57px Arial':'400 52px Arial';x.fillText(koch?'Gsf':fireball?'HYDROSHAMPOO':product.name.slice(0,22),35,koch?276:253);x.font='28px Arial';x.fillText(koch?product.name:fireball?'PREMIUM CAR CARE':'PRIVATE CAR CARE',38,347);x.font='22px Arial';x.fillStyle=koch||fireball?'#63796a':'#b2c8b8';x.fillText(koch?'EXCELLENCE FOR EXPERTS':'PERSONAL DETAILING COLLECTION',38,406);x.fillText(product.capacity+' mL',38,469);const t=new T.CanvasTexture(c);t.colorSpace=T.SRGBColorSpace;return t;}
const Bottle3D=memo(function Bottle3D({product,large=false,liquidPreview=false}){
 const host=useRef(null),sceneRef=useRef(null),[unavailable,setUnavailable]=useState(false);
 useEffect(()=>{
  if(!host.current)return;let renderer;try{renderer=new T.WebGLRenderer({antialias:true,alpha:true,powerPreference:'low-power'});}catch{setUnavailable(true);return;}
  const node=host.current;renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setClearColor(0x000000,0);renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.1;node.appendChild(renderer.domElement);
  const scene=new T.Scene(),camera=new T.PerspectiveCamera(32,1,.1,40);camera.position.set(.25,1.8,6.3);camera.lookAt(0,1.4,0);
  const pmrem=new T.PMREMGenerator(renderer),env=new RoomEnvironment(),map=pmrem.fromScene(env,.04);scene.environment=map.texture;
  scene.add(new T.HemisphereLight(0xffffff,0x888888,.8));let key=new T.DirectionalLight(0xffffff,2);key.position.set(-3,6,5);scene.add(key);
  const koch=product.shape==='koch'||product.brand==='Koch-Chemie',fireball=product.shape==='fireball'||product.brand==='Fireball',opaque=koch&&!liquidPreview;
  const group=new T.Group();group.rotation.y=-.12;if(fireball)group.scale.set(.86,1,.86);scene.add(group);
  function mesh(geometry,material,x=0,y=0,z=0){const m=new T.Mesh(geometry,material);m.position.set(x,y,z);group.add(m);return m;}
  const shell=new T.MeshPhysicalMaterial({color:koch?'#eeeee2':fireball?'#d0e4d8':'#e2ece5',metalness:0,roughness:opaque?.38:.08,transparent:!opaque,opacity:opaque?1:.27,transmission:opaque?0:.88,thickness:.12,side:T.DoubleSide,depthWrite:opaque,envMapIntensity:1});
  mesh(new T.LatheGeometry(profile.map(p=>new T.Vector2(...p)),80),shell);
  const capMat=new T.MeshStandardMaterial({color:koch?'#a4a9a0':fireball?'#ced7d0':'#252e28',metalness:fireball?.85:.2,roughness:fireball?.19:.4});
  mesh(new T.CylinderGeometry(.31,.31,.34,64),capMat,0,2.55,0);
  if(!fireball)for(let i=0;i<40;i++){const a=i*Math.PI/20;mesh(new T.CylinderGeometry(.009,.009,.29,4),capMat,Math.sin(a)*.313,2.55,Math.cos(a)*.313);}
  if(fireball){const ribMat=new T.MeshPhysicalMaterial({color:'#d6eadc',transparent:true,opacity:.22,roughness:.12,depthWrite:false});for(let i=0;i<32;i++){const a=i*Math.PI/16;mesh(new T.CylinderGeometry(.008,.008,1.56,4),ribMat,Math.sin(a)*.693,1.03,Math.cos(a)*.693);}}
  if(product.shape==='spray'){
    mesh(new T.BoxGeometry(.86,.27,.31),capMat,.17,2.83,0);
    const trigger=mesh(new T.BoxGeometry(.08,.44,.16),capMat,.29,2.55,.03);trigger.rotation.z=-.3;
    mesh(new T.CylinderGeometry(.075,.075,.04,20),capMat,.61,2.83,0).rotation.z=Math.PI/2;
  }
  const label=texture(product);const lm=new T.MeshBasicMaterial({map:label,side:T.FrontSide,toneMapped:false,depthTest:false,transparent:true,opacity:1,depthWrite:false});
  const panel=mesh(new T.CylinderGeometry(.704,.704,koch?1.25:1.05,64,1,true,-.99,1.98),lm,0,1.08,0);panel.rotation.y=.05;panel.renderOrder=10;
  const liquidMaterial=new T.MeshPhysicalMaterial({color:product.color,roughness:.08,metalness:0,transparent:true,opacity:.93,transmission:.18,envMapIntensity:.55});let liquid;
  const draw=()=>renderer.render(scene,camera);
  function update(p){if(liquid){group.remove(liquid);liquid.geometry.dispose();}const h=liquidHeight(p.remaining/p.capacity);let pts=[new T.Vector2(0,.09)];for(let y=.09;y<h;y+=.025)pts.push(new T.Vector2(Math.max(0,radius(y)-.035),y));pts.push(new T.Vector2(Math.max(0,radius(h)-.035),h),new T.Vector2(0,h));liquid=new T.Mesh(new T.LatheGeometry(pts,64),liquidMaterial);liquid.visible=stockKind(p)!=='unknown'&&p.remaining>0&&!opaque;group.add(liquid);draw();}
  const resize=()=>{const {width,height}=node.getBoundingClientRect();renderer.setSize(width||250,height||250);camera.aspect=(width||250)/(height||250);camera.updateProjectionMatrix();draw();};
  const observer=new ResizeObserver(resize);observer.observe(node);sceneRef.current={update,draw,group};update(product);resize();
  let dragging=false,startX=0,startRot=0;const down=e=>{dragging=true;startX=e.clientX;startRot=group.rotation.y;node.setPointerCapture(e.pointerId);};const move=e=>{if(dragging){group.rotation.y=startRot+(e.clientX-startX)/100;draw();}};const up=()=>dragging=false;
  const keyboard=e=>{if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();group.rotation.y+=e.key==='ArrowLeft'?-.2:.2;draw();}};
  node.addEventListener('pointerdown',down);node.addEventListener('pointermove',move);node.addEventListener('pointerup',up);node.addEventListener('pointercancel',up);node.addEventListener('keydown',keyboard);
  return()=>{observer.disconnect();node.removeEventListener('pointerdown',down);node.removeEventListener('pointermove',move);node.removeEventListener('pointerup',up);node.removeEventListener('pointercancel',up);node.removeEventListener('keydown',keyboard);sceneRef.current=null;scene.traverse(o=>{if(o.isMesh){o.geometry.dispose();const mats=Array.isArray(o.material)?o.material:[o.material];mats.forEach(m=>m.dispose());}});label.dispose();map.dispose();env.dispose();pmrem.dispose();renderer.dispose();renderer.forceContextLoss();renderer.domElement.remove();};
 },[product.id,product.brand,product.name,product.capacity,product.shape,product.label,product.code,product.color,liquidPreview]);
 useEffect(()=>{sceneRef.current?.update(product);},[product.remaining,product.stockStatus]);
 return <div className={'bottle-model '+(large?'large':'')} ref={host} role="img" aria-label={`${product.brand} ${product.name} 立体瓶型，${stockText(product)}；拖动或方向键旋转`} tabIndex={large?0:-1}>{unavailable?<div className="model-fallback">{product.name}<br/>当前设备无法显示3D模型<br/>{stockText(product)} / {product.capacity} mL</div>:null}</div>;
});
export default Bottle3D;
