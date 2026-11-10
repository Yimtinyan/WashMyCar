import test from 'node:test';
import assert from 'node:assert/strict';
import {beginSession,startWashing,confirmStep,togglePause,sessionTime,manualUsage,migrateState,planIssue} from './session.js';

function fixture(){return {version:2,products:[{id:'bottle',name:'Shampoo',remaining:100,capacity:500}],plan:{name:'Weekend',vehicle:'My car',location:'North wash bay',steps:[{id:'a',name:'Prewash',productId:'bottle',amount:20,water:1000,tools:[]},{id:'b',name:'Rinse',productId:'',amount:0,water:0,tools:[]}]},history:[],washes:[],session:null};}
test('preparation debits the summed bottle once, even on repeated start actions',()=>{
 let state=fixture();state.plan.steps.push({...state.plan.steps[0],id:'c',amount:10});state=beginSession(state,1000,'wash-1');
 assert.equal(state.products[0].remaining,70);assert.equal(state.history.length,1);assert.equal(state.history[0].amounts.bottle,30);
 assert.equal(beginSession(state,1100,'wash-2'),state);assert.equal(state.session.products[0].remaining,100);
});
test('pause preserves wall time and excludes pause duration from active time',()=>{
 let state=startWashing(beginSession(fixture(),500,'wash-1'),1000);state=togglePause(state,5000);assert.deepEqual(sessionTime(state.session,8000),{wall:7000,active:4000,paused:3000});
 assert.equal(confirmStep(state,8000),state);state=togglePause(state,9000);state=confirmStep(state,10000);state=confirmStep(state,11000);
 assert.equal(state.washes[0].durationMs,10000);assert.equal(state.washes[0].activeMs,6000);assert.equal(state.washes[0].pausedMs,4000);
});
test('completion keeps one immutable summary without a second inventory debit',()=>{
 let state=startWashing(beginSession(fixture(),500,'wash-1'),1000);state=confirmStep(state,2000);state=confirmStep(state,3000);const next=confirmStep(state,4000);
 assert.equal(next,state);assert.equal(next.washes.length,1);assert.equal(next.products[0].remaining,80);assert.equal(next.history.length,1);assert.equal(next.washes[0].location,'North wash bay');
 const oldName=next.washes[0].steps[0].name;next.plan.steps[0].name='Updated';assert.equal(next.washes[0].steps[0].name,oldName);
});
test('insufficient stock, missing bottles and invalid numbers block preparation',()=>{
 const state=fixture();state.plan.steps[0].amount=101;assert.ok(planIssue(state.plan,state.products));assert.equal(beginSession(state),state);
 state.plan.steps[0].amount=NaN;assert.equal(beginSession(state),state);state.plan.steps[0].amount=20;state.products=[];assert.equal(beginSession(state),state);
});
test('manual usage validates against current inventory and includes location and time',()=>{
 const state=fixture();assert.equal(manualUsage(state,'bottle',101,'Bay'),state);assert.equal(manualUsage(state,'bottle',-2,'Bay'),state);
 const next=manualUsage(state,'bottle',12.5,'East bay',1000);assert.equal(next.products[0].remaining,87.5);assert.equal(next.history[0].location,'East bay');assert.equal(next.history[0].date,'1970-01-01T00:00:01.000Z');
});
test('v2 migration preserves user inventory and existing usage history',()=>{
 const state=fixture();state.history=[{id:'old-entry',kind:'usage',amount:7}];state.products[0].remaining=73;
 state.session={id:'legacy',plan:state.plan,index:1,paused:false,done:false,startedAt:123000,resumedAt:124000,activeMs:1000};
 const migrated=migrateState(state);assert.equal(migrated.version,3);assert.equal(migrated.products,state.products);assert.equal(migrated.history,state.history);assert.equal(migrated.products[0].remaining,73);assert.deepEqual(migrated.washes,[]);assert.equal(migrated.settings.theme,'system');assert.equal(migrated.session.startedAt,123000);assert.equal(migrated.session.resumedAt,124000);assert.equal(migrated.session.status,'washing');
});
test('prepared sessions do not count travel time and restore as ready after refresh',()=>{
 const prepared=beginSession(fixture(),1000,'wash-1');assert.equal(prepared.session.preparedAt,1000);assert.equal(prepared.session.startedAt,null);assert.deepEqual(sessionTime(prepared.session,3601000),{wall:0,active:0,paused:0});
 assert.equal(confirmStep(prepared,3000),prepared);assert.equal(togglePause(prepared,3000),prepared);
 const restored=migrateState(JSON.parse(JSON.stringify(prepared)));assert.equal(restored.session.status,'prepared');assert.equal(restored.session.preparedAt,1000);assert.equal(restored.session.startedAt,null);assert.equal(restored.products[0].remaining,80);assert.equal(restored.history.length,1);
});
test('starting a prepared wash never debits again and completion excludes the preparation interval',()=>{
 const prepared=beginSession(fixture(),1000,'wash-1'),started=startWashing(prepared,3601000);assert.equal(started.products,prepared.products);assert.equal(started.history,prepared.history);assert.equal(started.session.startedAt,3601000);assert.equal(startWashing(started,3602000),started);
 let finished=confirmStep(started,3602000);finished=confirmStep(finished,3603000);assert.equal(finished.washes[0].durationMs,2000);assert.equal(finished.washes[0].preparedAt,1000);assert.equal(finished.products[0].remaining,80);assert.equal(finished.history.length,1);
});
