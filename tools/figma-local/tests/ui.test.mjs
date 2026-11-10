import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs/promises';

const html = await fs.readFile(new URL('../plugin/ui.html', import.meta.url), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
function harness() {
  const fields = new Map(), outgoing = [];
  const parent = { postMessage: (...args) => outgoing.push(args) };
  const context = vm.createContext({
    parent, window: {}, console, setTimeout, clearTimeout, AbortController,
    document: { getElementById(id) { if (!fields.has(id)) fields.set(id, { textContent: '', value: '', disabled: false }); return fields.get(id); } },
    fetch: async () => { throw new Error('No network request expected'); }
  });
  vm.runInContext(source, context);
  const receive = (message, source = null) => context.window.onmessage({ source, data: { pluginMessage: message } });
  return { fields, context, outgoing, receive };
}
const metadata = { fileKey: 'fixture-file', fileName: 'WashMyCar', pageId: '3:87', selection: [] };

test('Figma metadata is accepted through an intermediate WindowProxy', () => {
  const h = harness();
  h.receive({ type: 'metadata', metadata }, { notTheDirectParent: true });
  assert.equal(h.fields.get('fileName').textContent, 'WashMyCar');
  assert.equal(h.fields.get('fileKey').textContent, 'fixture-file');
  assert.equal(h.fields.get('pageId').textContent, '3:87');
  assert.equal(h.outgoing[0][0].pluginMessage.type, 'metadata');
});

test('a bound acknowledgement resolves the pending connection handshake', () => {
  const h = harness();
  vm.runInContext("globalThis.wasBound=false;waiting.set('bind',{resolve:()=>{globalThis.wasBound=true}})", h.context);
  h.receive({ type: 'bound', metadata });
  assert.equal(h.context.wasBound, true);
  assert.equal(vm.runInContext("waiting.has('bind')", h.context), false);
});

test('results must have a known pending id and a boolean outcome', () => {
  const h = harness();
  vm.runInContext("globalThis.received=null;waiting.set('job-1',{resolve:r=>{globalThis.received=r}})", h.context);
  h.receive({ type: 'result', response: { id: 'unknown', ok: true } });
  assert.equal(h.context.received, null);
  h.receive({ type: 'result', response: { id: 'job-1', ok: 'true' } });
  assert.equal(h.context.received, null);
  h.receive({ type: 'result', response: { id: 'job-1', ok: true, result: { nodes: [] } } });
  assert.equal(h.context.received.ok, true);
  assert.equal(vm.runInContext("waiting.has('job-1')", h.context), false);
});

test('malformed envelopes, metadata and unknown message types are ignored', () => {
  const h = harness();
  h.receive({ type: 'metadata', metadata });
  h.context.window.onmessage({ data: null });
  h.context.window.onmessage({ data: 'unexpected' });
  h.receive({ type: 'metadata', metadata: { fileKey: 42 } });
  h.receive({ type: 'execute', code: 'untrusted text' });
  assert.equal(h.fields.get('fileKey').textContent, 'fixture-file');
  assert.equal(h.fields.get('fileName').textContent, 'WashMyCar');
});
