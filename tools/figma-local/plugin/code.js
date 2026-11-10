/* Local development plugin. Structured operations only: no remote JavaScript execution. */
figma.showUI(__html__, { width: 380, height: 440, themeColors: true });
const WRITE_OPS = new Set(['patch', 'createText', 'createFrame', 'navigate', 'compose', 'wire', 'paintImage']);
const SUPPORTED_OPS = new Set(['inspect', 'selection', 'fonts', 'patch', 'createText', 'createFrame', 'navigate', 'screenshot', 'overview', 'compose', 'wire', 'paintImage']);
const PATCH_KEYS = new Set(['name', 'x', 'y', 'width', 'height', 'visible', 'characters', 'fontName', 'fontSize', 'lineHeight', 'letterSpacing', 'paragraphSpacing', 'itemSpacing', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'clipsContent', 'fills', 'strokes', 'effects', 'cornerRadius', 'topLeftRadius', 'topRightRadius', 'bottomLeftRadius', 'bottomRightRadius', 'opacity', 'textAutoResize', 'textAlignHorizontal', 'textAlignVertical', 'layoutMode', 'layoutPositioning', 'overflowDirection', 'constraints', 'primaryAxisSizingMode', 'counterAxisSizingMode', 'primaryAxisAlignItems', 'counterAxisAlignItems', 'layoutSizingHorizontal', 'layoutSizingVertical', 'strokeWeight']);
const ENUMS = {
  textAutoResize: ['NONE', 'WIDTH_AND_HEIGHT', 'HEIGHT', 'TRUNCATE'],
  textAlignHorizontal: ['LEFT', 'CENTER', 'RIGHT', 'JUSTIFIED'],
  textAlignVertical: ['TOP', 'CENTER', 'BOTTOM'],
  layoutMode: ['NONE', 'HORIZONTAL', 'VERTICAL'],
  layoutPositioning: ['AUTO', 'ABSOLUTE'], overflowDirection: ['NONE', 'HORIZONTAL', 'VERTICAL', 'BOTH'],
  primaryAxisSizingMode: ['FIXED', 'AUTO'], counterAxisSizingMode: ['FIXED', 'AUTO'],
  primaryAxisAlignItems: ['MIN', 'CENTER', 'MAX', 'SPACE_BETWEEN'], counterAxisAlignItems: ['MIN', 'CENTER', 'MAX', 'BASELINE'],
  layoutSizingHorizontal: ['FIXED', 'HUG', 'FILL'], layoutSizingVertical: ['FIXED', 'HUG', 'FILL']
};
const cache = new Map(), pending = new Map(), retiredIds = new Set();
let queue = Promise.resolve(), boundFileKey = null, cachedCharacters = 0;

function fileKey() { try { return figma.fileKey || null; } catch (_) { return null; } }
function metadata() { return { fileKey: fileKey(), fileName: figma.root.name, pageId: figma.currentPage.id, selection: figma.currentPage.selection.slice(0, 50).map(n => ({ id: n.id, name: n.name, type: n.type })) }; }
function post(type, payload) { figma.ui.postMessage(JSON.parse(JSON.stringify({ type, ...payload }))); }
function cleanFont(f) { return { family: f.family, style: f.style }; }
function object(v, label) { if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error(label + ' must be an object'); return v; }
function finite(v, low, high, label) { if (typeof v !== 'number' || !Number.isFinite(v) || v < low || v > high) throw new Error(label + ' is outside its allowed range'); }
function string(v, max, label) { if (typeof v !== 'string' || v.length > max) throw new Error(label + ' must be a string (max ' + max + ')'); }
function keys(v, allowed, label) { object(v, label); for (const key of Object.keys(v)) if (!allowed.includes(key)) throw new Error(label + ': unsupported property ' + key); }
function contextualError(stage, error) {
  // Native Plugin API errors are not guaranteed to be extensible Error objects.
  // Wrap rather than modifying them, and never include scene/image payloads.
  let message = 'Unknown error'; try { message = error && typeof error.message === 'string' ? error.message : String(error); } catch (_) {}
  return new Error(stage + ': ' + message);
}
function inStage(stage, run) { try { return run(); } catch (error) { throw contextualError(stage, error); } }
async function inAsyncStage(stage, run) { try { return await run(); } catch (error) { throw contextualError(stage, error); } }
function color(v, alpha, label) { keys(v, alpha ? ['r', 'g', 'b', 'a'] : ['r', 'g', 'b'], label); for (const c of alpha ? ['r', 'g', 'b', 'a'] : ['r', 'g', 'b']) finite(v[c], 0, 1, label + '.' + c); }
function paints(v, label) {
  if (!Array.isArray(v) || v.length > 6) throw new Error(label + ' must contain at most 6 SOLID paints');
  for (const p of v) { keys(p, ['type', 'color', 'opacity', 'visible'], label); if (p.type !== 'SOLID') throw new Error('Only SOLID paints are allowed in props'); color(p.color, false, label + '.color'); if (p.opacity !== undefined) finite(p.opacity, 0, 1, 'opacity'); if (p.visible !== undefined && typeof p.visible !== 'boolean') throw new Error('paint.visible requires boolean'); }
}
function summary(n) {
  const r = { id: n.id, name: n.name, type: n.type, parentId: n.parent ? n.parent.id : null };
  for (const key of ['x', 'y', 'width', 'height', 'visible', 'clipsContent', 'layoutMode', 'itemSpacing', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft']) if (key in n) r[key] = n[key];
  if ('children' in n) r.childCount = n.children.length;
  if (n.type === 'TEXT') { r.characters = n.characters.slice(0, 2000); r.charactersTruncated = n.characters.length > 2000; r.fontName = n.fontName === figma.mixed ? 'MIXED' : cleanFont(n.fontName); r.fontSize = n.fontSize === figma.mixed ? 'MIXED' : n.fontSize; r.lineHeight = n.lineHeight === figma.mixed ? 'MIXED' : n.lineHeight; }
  return r;
}
async function nodeById(id) { string(id, 160, 'node id'); const n = await figma.getNodeByIdAsync(id); if (!n) throw new Error('Node not found: ' + id); return n; }
function validateProps(n, props) {
  object(props, 'props');
  for (const [key, v] of Object.entries(props)) {
    if (!PATCH_KEYS.has(key)) throw new Error('Property not allowed: ' + key);
    if (!(key in n)) throw new Error('Property ' + key + ' is not supported by ' + n.type);
    if (ENUMS[key]) {
      if (!ENUMS[key].includes(v)) throw new Error('Invalid ' + key + ' value');
      if (key.startsWith('text') && n.type !== 'TEXT') throw new Error(key + ' requires TEXT');
      if ((key === 'layoutSizingHorizontal' || key === 'layoutSizingVertical') && v !== 'FIXED') {
        const parentAuto = n.parent && 'layoutMode' in n.parent && ['HORIZONTAL', 'VERTICAL'].includes(n.parent.layoutMode);
        const ownAuto = ['HORIZONTAL', 'VERTICAL'].includes(props.layoutMode || ('layoutMode' in n ? n.layoutMode : undefined));
        if (v === 'FILL' && (!parentAuto || (props.layoutPositioning || n.layoutPositioning) === 'ABSOLUTE')) throw new Error('FILL requires an auto-layout parent and non-absolute positioning');
        if (v === 'HUG' && !(ownAuto || (n.type === 'TEXT' && parentAuto))) throw new Error('HUG requires an auto-layout frame or TEXT in auto-layout');
      }
    }
    else if (key === 'name') string(v, 200, key);
    else if (key === 'characters') { if (n.type !== 'TEXT') throw new Error('characters requires TEXT'); string(v, 20000, key); }
    else if (key === 'visible' || key === 'clipsContent') { if (typeof v !== 'boolean') throw new Error(key + ' requires boolean'); }
    else if (key === 'fontName') { object(v, key); string(v.family, 100, 'font family'); string(v.style, 100, 'font style'); if (!v.family || !v.style || Object.keys(v).some(k => !['family', 'style'].includes(k))) throw new Error('fontName accepts family/style only'); }
    else if (key === 'lineHeight') { keys(v, ['unit', 'value'], key); if (v.unit === 'AUTO') { if (Object.keys(v).some(k => k !== 'unit')) throw new Error('AUTO lineHeight takes no value'); } else { if (!['PIXELS', 'PERCENT'].includes(v.unit)) throw new Error('Invalid lineHeight unit'); finite(v.value, 1, 1000, key); } }
    else if (key === 'letterSpacing') { keys(v, ['unit', 'value'], key); if (!['PIXELS', 'PERCENT'].includes(v.unit)) throw new Error('Invalid letterSpacing unit'); finite(v.value, -100, 1000, key); }
    else if (key === 'constraints') { keys(v, ['horizontal', 'vertical'], key); for (const axis of ['horizontal', 'vertical']) if (!['MIN', 'CENTER', 'MAX', 'STRETCH', 'SCALE'].includes(v[axis])) throw new Error('Invalid constraint ' + axis); }
    else if (key === 'fills' || key === 'strokes') paints(v, key);
    else if (key === 'effects') {
      if (!Array.isArray(v) || v.length > 4) throw new Error('effects takes at most 4 DROP_SHADOW effects');
      for (const e of v) { keys(e, ['type', 'color', 'offset', 'radius', 'spread', 'visible', 'blendMode', 'showShadowBehindNode'], 'effect'); if (e.type !== 'DROP_SHADOW' || e.blendMode !== 'NORMAL') throw new Error('Only NORMAL DROP_SHADOW effects are allowed'); color(e.color, true, 'shadow color'); keys(e.offset, ['x', 'y'], 'shadow offset'); finite(e.offset.x, -1000, 1000, 'shadow x'); finite(e.offset.y, -1000, 1000, 'shadow y'); finite(e.radius, 0, 1000, 'shadow radius'); if (e.spread !== undefined) finite(e.spread, -1000, 1000, 'shadow spread'); if (typeof e.visible !== 'boolean' || (e.showShadowBehindNode !== undefined && typeof e.showShadowBehindNode !== 'boolean')) throw new Error('Shadow visibility requires boolean'); }
    } else if (key === 'opacity') finite(v, 0, 1, key);
    else if (key === 'cornerRadius' || key.endsWith('Radius')) finite(v, 0, 100000, key);
    else if (key === 'strokeWeight') finite(v, 0, 1000, key);
    else if (key === 'fontSize') finite(v, 1, 200, key);
    else if (key === 'width' || key === 'height') finite(v, 0.01, 100000, key);
    else if (key === 'x' || key === 'y') finite(v, -1000000, 1000000, key);
    else finite(v, 0, 10000, key);
  }
}
async function loadFonts(n, props) {
  if (n.type !== 'TEXT') return;
  // Full-node font replacement only needs the new font. In particular, loading a
  // missing old font would prevent the very repair this operation is meant to do.
  // applyProps assigns fontName before characters or any other layout property.
  if (props.fontName) { await figma.loadFontAsync(cleanFont(props.fontName)); return; }
  const fonts = new Map();
  if (n.characters) for (const seg of n.getStyledTextSegments(['fontName'])) { const f = cleanFont(seg.fontName); fonts.set(f.family + '\n' + f.style, f); }
  else if (n.fontName !== figma.mixed) { const f = cleanFont(n.fontName); fonts.set(f.family + '\n' + f.style, f); }
  await Promise.all([...fonts.values()].map(f => figma.loadFontAsync(f)));
}
function applyProps(n, props) {
  // Set font and content before the final explicit dimensions. Changing the font may reflow text.
  if (props.layoutMode !== undefined) n.layoutMode = props.layoutMode;
  if (props.fontName) n.fontName = cleanFont(props.fontName);
  const delayed = ['fontName', 'layoutMode', 'width', 'height', 'x', 'y', 'layoutSizingHorizontal', 'layoutSizingVertical', 'primaryAxisSizingMode', 'counterAxisSizingMode'];
  for (const [key, value] of Object.entries(props)) if (!delayed.includes(key)) n[key] = value;
  if (props.width !== undefined || props.height !== undefined) n.resize(props.width === undefined ? n.width : props.width, props.height === undefined ? n.height : props.height);
  // resize resets sizing modes, so restore the explicitly requested modes last.
  for (const key of ['primaryAxisSizingMode', 'counterAxisSizingMode', 'layoutSizingHorizontal', 'layoutSizingVertical']) if (props[key] !== undefined) n[key] = props[key];
  if (props.x !== undefined) n.x = props.x;
  if (props.y !== undefined) n.y = props.y;
}
function checkFile(command) {
  const actual = fileKey(), expected = command.expectedFileKey;
  if (expected !== undefined && (typeof expected !== 'string' || !expected || expected !== actual)) throw new Error('Target file does not match expectedFileKey');
  if (WRITE_OPS.has(command.op) && (!actual || !expected || actual !== boundFileKey)) throw new Error('Writes require a verified fileKey bound by the Connect action');
}
function bytesToBase64(bytes) { const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'; let out = ''; for (let i = 0; i < bytes.length; i += 3) { const n = bytes[i] * 65536 + (bytes[i + 1] || 0) * 256 + (bytes[i + 2] || 0); out += chars[(n >>> 18) & 63] + chars[(n >>> 12) & 63] + (i + 1 < bytes.length ? chars[(n >>> 6) & 63] : '=') + (i + 2 < bytes.length ? chars[n & 63] : '='); } return out; }
function capability(type, parent) {
  const n = { type, parent, name: '', x: 0, y: 0, width: 100, height: 100, visible: true, fills: [], strokes: [], strokeWeight: 1, opacity: 1, effects: [], constraints: {}, layoutPositioning: 'AUTO', layoutSizingHorizontal: 'FIXED', layoutSizingVertical: 'FIXED' };
  if (type === 'TEXT') Object.assign(n, { characters: '', fontName: { family: 'Inter', style: 'Regular' }, fontSize: 17, lineHeight: {}, letterSpacing: {}, paragraphSpacing: 0, textAutoResize: 'WIDTH_AND_HEIGHT', textAlignHorizontal: 'LEFT', textAlignVertical: 'TOP' });
  if (type === 'FRAME' || type === 'RECTANGLE') Object.assign(n, { cornerRadius: 0, topLeftRadius: 0, topRightRadius: 0, bottomLeftRadius: 0, bottomRightRadius: 0 });
  if (type === 'FRAME') Object.assign(n, { itemSpacing: 0, paddingTop: 0, paddingRight: 0, paddingBottom: 0, paddingLeft: 0, clipsContent: true, layoutMode: 'NONE', primaryAxisSizingMode: 'FIXED', counterAxisSizingMode: 'FIXED', primaryAxisAlignItems: 'MIN', counterAxisAlignItems: 'MIN', overflowDirection: 'NONE' });
  return n;
}
function pngBytes(asset) {
  keys(asset, ['mimeType', 'base64'], 'asset'); if (asset.mimeType !== 'image/png') throw new Error('Only local base64 image/png assets are allowed');
  const data = asset.base64; string(data, Math.ceil(4 * 1024 * 1024 / 3) * 4, 'asset.base64');
  if (!data || data.length % 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(data)) throw new Error('Invalid PNG base64');
  const length = data.length / 4 * 3 - (data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0);
  if (length > 4 * 1024 * 1024 || length < 33) throw new Error('PNG must be 33 bytes to 4 MiB');
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', out = new Uint8Array(length); let at = 0;
  for (let i = 0; i < data.length; i += 4) { const n = (chars.indexOf(data[i]) << 18) | (chars.indexOf(data[i + 1]) << 12) | (Math.max(0, chars.indexOf(data[i + 2])) << 6) | Math.max(0, chars.indexOf(data[i + 3])); if (at < length) out[at++] = n >>> 16 & 255; if (at < length) out[at++] = n >>> 8 & 255; if (at < length) out[at++] = n & 255; }
  const signature = [137, 80, 78, 71, 13, 10, 26, 10]; if (signature.some((v, i) => out[i] !== v) || String.fromCharCode(...out.slice(12, 16)) !== 'IHDR') throw new Error('PNG signature / IHDR is invalid');
  const uint32 = i => out[i] * 16777216 + out[i + 1] * 65536 + out[i + 2] * 256 + out[i + 3];
  for (const size of [uint32(16), uint32(20)]) if (!size || size > 4096) throw new Error('PNG dimensions must be 1–4096 pixels');
  return out;
}
function validateSvg(svg) {
  string(svg, 32768, 'svg');
  if (!/^\s*<svg\b/i.test(svg) || /<!|<\?|&|url\s*\(|javascript\s*:|data\s*:|\b(?:href|style|on[a-z]+)\s*=/i.test(svg)) throw new Error('SVG accepts static local geometry only');
  const tags = new Set(['svg', 'g', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon']);
  const attrs = new Set(['xmlns', 'class', 'viewBox', 'width', 'height', 'fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'stroke-dasharray', 'stroke-dashoffset', 'opacity', 'fill-opacity', 'stroke-opacity', 'fill-rule', 'clip-rule', 'd', 'points', 'x', 'y', 'x1', 'x2', 'y1', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'transform']);
  let count = 0, at = 0; const stack = []; const tag = /<\/?([a-zA-Z][a-zA-Z0-9:-]*)([^<>]*)>/g; let m;
  while ((m = tag.exec(svg))) {
    if (svg.slice(at, m.index).trim() || !tags.has(m[1])) throw new Error('Unsupported SVG content or tag'); at = tag.lastIndex;
    if (m[0].startsWith('</')) { if (m[2].trim() || stack.pop() !== m[1]) throw new Error('Invalid SVG closing tag'); continue; }
    if ((!count && m[1] !== 'svg') || (count && !stack.length)) throw new Error('SVG requires a single svg root');
    if (!/\/\s*>$/.test(m[0])) stack.push(m[1]);
    count++; let rest = m[2].replace(/\/\s*$/, ''); const attr = /\s+([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g; let pos = 0, a;
    const seenAttrs = new Set(); while ((a = attr.exec(rest))) { if (rest.slice(pos, a.index).trim() || !attrs.has(a[1]) || seenAttrs.has(a[1])) throw new Error('Unsupported or duplicate SVG attribute'); seenAttrs.add(a[1]); const value = a[2] === undefined ? a[3] : a[2]; if (a[1] === 'xmlns' ? value !== 'http://www.w3.org/2000/svg' : /https?:|\/\//i.test(value)) throw new Error('SVG external references are prohibited'); pos = attr.lastIndex; }
    if (rest.slice(pos).trim()) throw new Error('Malformed SVG attributes');
  }
  if (svg.slice(at).trim() || stack.length || !count || count > 100) throw new Error('SVG must contain 1–100 balanced static geometry elements'); return count;
}
async function prepareCompose(args) {
  keys(args, ['pageId', 'pageName', 'assets', 'nodes', 'flowStartingPoints'], 'compose args');
  if (args.pageId !== undefined && args.pageName !== undefined) throw new Error('Use pageId to append or pageName to create a new page');
  let page = null; if (args.pageId !== undefined) { page = await nodeById(args.pageId); if (page.type !== 'PAGE') throw new Error('compose pageId must identify a PAGE'); }
  if (args.pageName !== undefined) { string(args.pageName, 200, 'pageName'); if (!args.pageName.trim()) throw new Error('pageName cannot be empty'); }
  const assets = new Map(); if (args.assets !== undefined) { object(args.assets, 'assets'); if (Object.keys(args.assets).length > 30) throw new Error('At most 30 PNG assets per compose'); for (const [key, asset] of Object.entries(args.assets)) { string(key, 100, 'asset key'); assets.set(key, inStage('asset decode [' + key + ']', () => pngBytes(asset))); } }
  if (!Array.isArray(args.nodes) || !args.nodes.length) throw new Error('compose nodes must be a nonempty array');
  const flat = [], refs = new Map(), fonts = new Map(), images = new Map(); let count = 0;
  function visit(item, parent, depth) {
    keys(item, ['ref', 'type', 'props', 'image', 'children', 'reactions', 'svg'], 'scene node'); string(item.ref, 100, 'node ref');
    if (!/^[A-Za-z0-9._:-]+$/.test(item.ref) || refs.has(item.ref)) throw new Error('Node refs must be unique nonempty keys');
    if (!['FRAME', 'TEXT', 'RECTANGLE', 'ELLIPSE', 'SVG'].includes(item.type)) throw new Error('Unsupported scene node type'); if (depth > 40 || ++count > 5000) throw new Error('compose is limited to 5000 nodes and depth 40');
    if (item.type === 'SVG') { count += validateSvg(item.svg); if (count > 5000) throw new Error('SVG geometry exceeds the 5000 node budget'); } else if (item.svg !== undefined) throw new Error('svg requires type SVG');
    const props = item.props || {}, shell = capability(item.type, parent ? parent.shell : page || { type: 'PAGE' });
    if (item.type === 'SVG') { keys(props, ['name', 'x', 'y', 'width', 'height', 'opacity'], 'SVG props'); }
    validateProps(shell, props); Object.assign(shell, props);
    if (props.layoutPositioning === 'ABSOLUTE' && !['HORIZONTAL', 'VERTICAL'].includes(shell.parent.layoutMode)) throw new Error('ABSOLUTE requires an auto-layout parent');
    const entry = { item, shell, parent, props }; flat.push(entry); refs.set(item.ref, entry);
    if (item.type === 'TEXT') { const f = props.fontName || { family: 'Inter', style: 'Regular' }; fonts.set(f.family + '\n' + f.style, cleanFont(f)); }
    if (item.image !== undefined) { keys(item.image, ['assetRef', 'nodeId', 'scaleMode'], 'image'); if (item.type === 'TEXT' || item.type === 'SVG' || (typeof item.image.assetRef === 'string') === (typeof item.image.nodeId === 'string')) throw new Error('image requires exactly one assetRef or nodeId on FRAME/RECTANGLE/ELLIPSE'); if (props.fills !== undefined) throw new Error('Use image or props.fills, not both'); if (item.image.assetRef !== undefined && !assets.has(item.image.assetRef)) throw new Error('Unknown image assetRef'); if (item.image.scaleMode !== undefined && !['FILL', 'FIT', 'CROP'].includes(item.image.scaleMode)) throw new Error('Invalid image scaleMode'); }
    if (item.children !== undefined) { if (item.type !== 'FRAME' || !Array.isArray(item.children)) throw new Error('Only FRAME nodes can contain children'); for (const child of item.children) visit(child, entry, depth + 1); }
  }
  for (const item of args.nodes) visit(item, null, 0);
  for (const entry of flat) {
    const item = entry.item;
    if (item.image && item.image.nodeId !== undefined) { const source = await nodeById(item.image.nodeId); const paint = 'fills' in source && Array.isArray(source.fills) && source.fills.find(p => p.type === 'IMAGE' && p.imageHash); if (!paint) throw new Error('Image source node has no IMAGE fill'); images.set(item.ref, { ...paint }); }
    if (item.reactions !== undefined) {
      if (!Array.isArray(item.reactions) || item.reactions.length > 10 || item.type === 'SVG') throw new Error('reactions takes at most 10 links on a native scene node');
      for (const r of item.reactions) {
        keys(r, ['targetRef', 'targetId', 'trigger', 'navigation', 'transition'], 'reaction'); if (r.trigger !== 'ON_CLICK' || !['NAVIGATE', 'OVERLAY', 'BACK'].includes(r.navigation)) throw new Error('Unsupported reaction trigger/navigation');
        if (r.navigation === 'BACK') { if (r.targetRef !== undefined || r.targetId !== undefined || r.transition !== undefined) throw new Error('BACK takes no destination or transition'); continue; }
        if ((typeof r.targetRef === 'string') === (typeof r.targetId === 'string')) throw new Error('Reaction requires exactly one targetRef or targetId');
        if (r.targetRef !== undefined) { const target = refs.get(r.targetRef); if (!target || target.parent || target.item.type !== 'FRAME') throw new Error('targetRef must be a top-level FRAME in this compose'); }
        else { const target = await nodeById(r.targetId); if (!page || target.type !== 'FRAME' || !target.parent || target.parent.id !== page.id) throw new Error('targetId must be a top-level FRAME on the compose page'); }
        if (r.transition !== undefined) { keys(r.transition, ['type', 'duration'], 'transition'); if (!['DISSOLVE', 'SMART_ANIMATE'].includes(r.transition.type)) throw new Error('Unsupported transition'); finite(r.transition.duration, 0, 2, 'transition duration'); }
      }
    }
  }
  if (args.flowStartingPoints !== undefined) { if (!Array.isArray(args.flowStartingPoints) || args.flowStartingPoints.length > 100) throw new Error('At most 100 flow starting points'); const seen = new Set(); for (const f of args.flowStartingPoints) { keys(f, ['ref', 'name'], 'flow starting point'); string(f.name, 100, 'flow name'); const target = refs.get(f.ref); if (!target || target.parent || target.item.type !== 'FRAME' || seen.has(f.ref)) throw new Error('Flow refs must be unique top-level FRAMEs'); seen.add(f.ref); } }
  await Promise.all([...fonts.values()].map(f => inAsyncStage('font preload [' + f.family + ' / ' + f.style + ']', () => figma.loadFontAsync({ family: f.family, style: f.style }))));
  return { page, assets, flat, images };
}
async function compose(command, args) {
  const plan = await inAsyncStage('compose preflight', () => prepareCompose(args)); checkFile(command);
  const imageHashes = new Map(); for (const [key, bytes] of plan.assets) {
    const hash = inStage('createImage [' + key + ', ' + bytes.length + ' bytes]', () => {
      const image = figma.createImage(bytes);
      if (!image || typeof image.hash !== 'string' || !image.hash) throw new Error('Native API did not return an image hash');
      return image.hash;
    }); imageHashes.set(key, hash);
  }
  checkFile(command); const createdNodeIds = [], refs = {}; let page = plan.page;
  try {
    if (!page) { page = inStage('createPage', () => figma.createPage()); createdNodeIds.push(page.id); inStage('name page [' + page.id + ']', () => { page.name = args.pageName || 'WashMyCar · Local composition'; }); }
    await inAsyncStage('activate page [' + page.id + ']', () => figma.setCurrentPageAsync(page)); checkFile(command);
    for (const entry of plan.flat) {
      checkFile(command); const { item, props, parent } = entry;
      const n = inStage('create node [' + item.ref + ', ' + item.type + ']', () => item.type === 'FRAME' ? figma.createFrame() : item.type === 'TEXT' ? figma.createText() : item.type === 'RECTANGLE' ? figma.createRectangle() : item.type === 'ELLIPSE' ? figma.createEllipse() : figma.createNodeFromSvg(item.svg));
      entry.node = n; Object.defineProperty(refs, item.ref, { value: n.id, enumerable: true, writable: true, configurable: true }); createdNodeIds.push(n.id);
      if (item.type === 'SVG') { const work = 'children' in n ? [...n.children] : []; while (work.length) { const child = work.pop(); createdNodeIds.push(child.id); if ('children' in child) work.push(...child.children); } }
      inStage('append node [' + item.ref + ']', () => (parent ? parent.node : page).appendChild(n));
      if (item.type === 'TEXT') n.fontName = cleanFont(props.fontName || { family: 'Inter', style: 'Regular' });
      inStage('apply properties [' + item.ref + ']', () => applyProps(n, props));
      if (item.image) { const paint = item.image.assetRef !== undefined ? { type: 'IMAGE', imageHash: imageHashes.get(item.image.assetRef), scaleMode: 'FILL' } : { ...plan.images.get(item.ref) }; if (item.image.scaleMode) paint.scaleMode = item.image.scaleMode; if (paint.scaleMode === 'CROP' && !paint.imageTransform) paint.imageTransform = [[1, 0, 0], [0, 1, 0]]; n.fills = [paint]; }
    }
    for (const entry of plan.flat) if (entry.item.reactions && entry.item.reactions.length) {
      checkFile(command); await inAsyncStage('reactions [' + entry.item.ref + ', ' + entry.node.id + ']', () => entry.node.setReactionsAsync(entry.item.reactions.map(r => reactionValue(r, r.targetRef !== undefined ? refs[r.targetRef] : r.targetId))));
    }
    checkFile(command);
    if (args.flowStartingPoints) inStage('flow starting points [' + page.id + ']', () => { page.flowStartingPoints = [...(page.flowStartingPoints || []), ...args.flowStartingPoints.map(f => ({ nodeId: refs[f.ref], name: f.name }))]; });
    return { pageId: page.id, createdNodeIds, refs, nodeCount: createdNodeIds.length };
  } catch (error) { const e = contextualError('compose canvas', error); e.partial = createdNodeIds.length > 0; e.createdNodeIds = createdNodeIds; e.pageId = page && page.id; e.refs = refs; throw e; }
}
function reactionValue(r, destinationId) { return { trigger: { type: 'ON_CLICK' }, actions: [r.navigation === 'BACK' ? { type: 'BACK' } : { type: 'NODE', destinationId, navigation: r.navigation, transition: r.transition ? { ...r.transition, easing: { type: 'EASE_IN_AND_OUT' } } : null }] }; }
function owningPage(n) { let current = n; for (let i = 0; current && i < 100; i++, current = current.parent) if (current.type === 'PAGE') return current; return null; }
async function wire(command, args) {
  keys(args, ['pageId', 'nodes', 'flowStartingPoints'], 'wire args'); const page = await nodeById(args.pageId); if (page.type !== 'PAGE') throw new Error('wire pageId must be a PAGE');
  if (!Array.isArray(args.nodes) || args.nodes.length > 1000) throw new Error('wire nodes must contain 0–1000 existing nodes');
  const prepared = [], seen = new Set();
  async function targetFrame(id) { const target = await nodeById(id); if (target.type !== 'FRAME' || !target.parent || target.parent.id !== page.id) throw new Error('wire destination must be a top-level FRAME on the declared page'); return target; }
  for (const item of args.nodes) {
    keys(item, ['id', 'reactions'], 'wire node'); if (seen.has(item.id)) throw new Error('Duplicate wire node id'); seen.add(item.id); const n = await nodeById(item.id);
    if (!owningPage(n) || owningPage(n).id !== page.id || typeof n.setReactionsAsync !== 'function') throw new Error('wire source must support reactions and belong to the declared page');
    if (!Array.isArray(item.reactions) || item.reactions.length > 10) throw new Error('wire reactions takes 0–10 links per node');
    const reactions = [];
    for (const r of item.reactions) {
      keys(r, ['targetId', 'trigger', 'navigation', 'transition'], 'wire reaction'); if (r.trigger !== 'ON_CLICK' || !['NAVIGATE', 'OVERLAY', 'BACK'].includes(r.navigation)) throw new Error('Unsupported wire trigger/navigation');
      if (r.navigation === 'BACK') { if (r.targetId !== undefined || r.transition !== undefined) throw new Error('BACK takes no destination or transition'); }
      else { await targetFrame(r.targetId); if (r.transition !== undefined) { keys(r.transition, ['type', 'duration'], 'transition'); if (!['DISSOLVE', 'SMART_ANIMATE'].includes(r.transition.type)) throw new Error('Unsupported transition'); finite(r.transition.duration, 0, 2, 'transition duration'); } }
      reactions.push(reactionValue(r, r.targetId));
    }
    prepared.push({ n, reactions });
  }
  let flows;
  if (args.flowStartingPoints !== undefined) {
    if (!Array.isArray(args.flowStartingPoints) || args.flowStartingPoints.length > 100) throw new Error('wire takes 0–100 flow starting points'); flows = []; const flowIds = new Set();
    for (const f of args.flowStartingPoints) { keys(f, ['nodeId', 'name'], 'wire flow'); string(f.name, 100, 'flow name'); await targetFrame(f.nodeId); if (flowIds.has(f.nodeId)) throw new Error('Duplicate flow node id'); flowIds.add(f.nodeId); flows.push({ nodeId: f.nodeId, name: f.name }); }
  }
  checkFile(command); const mutatedNodeIds = [];
  try {
    for (const p of prepared) { checkFile(command); mutatedNodeIds.push(p.n.id); await inAsyncStage('wire reactions [' + p.n.id + ']', () => p.n.setReactionsAsync(p.reactions)); }
    if (flows !== undefined) { checkFile(command); mutatedNodeIds.push(page.id); inStage('wire flow starting points [' + page.id + ']', () => { page.flowStartingPoints = flows; }); }
    return { pageId: page.id, mutatedNodeIds, wiredNodeCount: prepared.length, ...(flows !== undefined ? { flowStartingPoints: flows } : {}) };
  } catch (error) { const e = contextualError('wire', error); e.partial = mutatedNodeIds.length > 0; e.mutatedNodeIds = mutatedNodeIds; e.pageId = page.id; throw e; }
}
async function execute(command) {
  if (!SUPPORTED_OPS.has(command.op)) throw new Error('Operation not allowed: ' + command.op);
  checkFile(command);
  const args = command.args || {}; object(args, 'args');
  if (command.op === 'overview') { const pages = figma.root.children.filter(n => n.type === 'PAGE').map(p => ({ id: p.id, name: p.name })); return { ...metadata(), pages, currentPageNodes: figma.currentPage.children.slice(0, 300).map(summary), truncated: figma.currentPage.children.length > 300 }; }
  if (command.op === 'compose') return compose(command, args);
  if (command.op === 'wire') return wire(command, args);
  if (command.op === 'paintImage') {
    keys(args, ['nodeId', 'asset', 'scaleMode'], 'paintImage args');
    const n = await nodeById(args.nodeId);
    if (!['FRAME', 'RECTANGLE', 'ELLIPSE'].includes(n.type)) throw new Error('paintImage requires FRAME, RECTANGLE or ELLIPSE');
    if (!['FIT', 'FILL'].includes(args.scaleMode)) throw new Error('paintImage scaleMode must be FIT or FILL');
    const bytes = inStage('paintImage PNG preflight [' + n.id + ']', () => pngBytes(args.asset));
    checkFile(command);
    const hash = inStage('paintImage createImage [' + n.id + ', ' + bytes.length + ' bytes]', () => {
      const image = figma.createImage(bytes); if (!image || typeof image.hash !== 'string' || !image.hash) throw new Error('Native API did not return an image hash'); return image.hash;
    });
    checkFile(command);
    try { inStage('paintImage set fills [' + n.id + ']', () => { n.fills = [{ type: 'IMAGE', imageHash: hash, scaleMode: args.scaleMode }]; }); }
    catch (error) { const e = contextualError('paintImage', error); e.partial = true; e.mutatedNodeIds = [n.id]; throw e; }
    return { mutatedNodeIds: [n.id], nodeId: n.id, scaleMode: args.scaleMode, imageBytes: bytes.length };
  }
  if (command.op === 'selection') return { ...metadata(), nodes: figma.currentPage.selection.slice(0, 50).map(summary) };
  if (command.op === 'fonts') { const query = typeof args.query === 'string' ? args.query.toLowerCase() : ''; const all = await figma.listAvailableFontsAsync(); const matched = all.filter(f => !query || f.fontName.family.toLowerCase().includes(query)); return { fonts: matched.slice(0, 300).map(f => cleanFont(f.fontName)), total: matched.length, truncated: matched.length > 300 }; }
  if (command.op === 'inspect') {
    const root = args.rootId ? await nodeById(args.rootId) : figma.currentPage;
    const depth = args.depth === undefined ? 1 : args.depth, limit = args.limit === undefined ? 120 : args.limit; finite(depth, 0, 4, 'depth'); finite(limit, 1, 3000, 'limit');
    const work = [{ node: root, depth: 0 }], nodes = []; let at = 0;
    while (at < work.length && nodes.length < limit) { const item = work[at++]; nodes.push({ ...summary(item.node), depth: item.depth }); if (item.depth < depth && 'children' in item.node) for (const child of item.node.children) work.push({ node: child, depth: item.depth + 1 }); }
    return { ...metadata(), nodes, truncated: at < work.length };
  }
  if (command.op === 'patch') {
    if (!Array.isArray(args.nodes) || !args.nodes.length || args.nodes.length > 100) throw new Error('patch takes 1–100 nodes');
    const ids = new Set(), prepared = [];
    for (const item of args.nodes) { object(item, 'patch item'); if (ids.has(item.id)) throw new Error('Duplicate node id'); ids.add(item.id); const n = await nodeById(item.id); validateProps(n, item.props); prepared.push({ n, props: item.props }); }
    await Promise.all(prepared.map(item => loadFonts(item.n, item.props)));
    checkFile(command);
    const mutatedNodeIds = [];
    try { for (const item of prepared) { mutatedNodeIds.push(item.n.id); applyProps(item.n, item.props); } }
    catch (e) { e.partial = true; e.mutatedNodeIds = mutatedNodeIds; throw e; }
    return { mutatedNodeIds, nodes: prepared.map(item => summary(item.n)) };
  }
  if (command.op === 'navigate') { const p = await nodeById(args.pageId); if (p.type !== 'PAGE') throw new Error('navigate requires a PAGE'); await figma.setCurrentPageAsync(p); return metadata(); }
  if (command.op === 'screenshot') { const n = await nodeById(args.rootId); if (!('exportAsync' in n) || n.type === 'PAGE') throw new Error('screenshot requires an exportable scene node'); const width = args.width === undefined ? 900 : args.width; finite(width, 100, 1600, 'screenshot width'); const bytes = await n.exportAsync({ format: 'PNG', constraint: { type: 'WIDTH', value: width } }); if (bytes.length > 5 * 1024 * 1024) throw new Error('PNG exceeds 5 MB; choose a smaller width'); return { nodeId: n.id, mimeType: 'image/png', bytes: bytes.length, base64: bytesToBase64(bytes) }; }
  if (command.op === 'createText' || command.op === 'createFrame') {
    const parent = await nodeById(args.parentId); if (!['PAGE', 'FRAME', 'COMPONENT'].includes(parent.type) || !('appendChild' in parent)) throw new Error('Parent must be a mutable page, frame or component');
    const props = args.props || {}; object(props, 'props');
    // Validate against a capability shell before creating anything on the canvas.
    const text = command.op === 'createText'; const shell = capability(text ? 'TEXT' : 'FRAME', parent); if (!text) shell.layoutMode = 'VERTICAL';
    validateProps(shell, props);
    const font = props.fontName || { family: 'Inter', style: 'Regular' }; if (text) await figma.loadFontAsync(font);
    checkFile(command);
    const n = text ? figma.createText() : figma.createFrame();
    try { if (text) n.fontName = cleanFont(font); else { n.layoutMode = 'VERTICAL'; n.primaryAxisSizingMode = 'AUTO'; n.counterAxisSizingMode = 'FIXED'; } parent.appendChild(n); applyProps(n, props); }
    catch (e) { e.partial = true; e.createdNodeIds = [n.id]; throw e; }
    return { createdNodeIds: [n.id], node: summary(n) };
  }
  throw new Error('Unhandled operation');
}
function dispatch(command) {
  if (!command || typeof command.id !== 'string' || command.id.length > 160) return Promise.resolve({ id: null, ok: false, error: { message: 'Invalid command id' } });
  if (!command.id || retiredIds.has(command.id)) return Promise.resolve({ id: command.id, ok: false, error: { message: 'Command was already handled; cached result expired. Inspect the canvas before issuing a new id.' } });
  const fingerprint = JSON.stringify({ op: command.op, args: command.args || {}, expectedFileKey: command.expectedFileKey });
  if (fingerprint.length > (command.op === 'compose' ? 12 * 1024 * 1024 + 1024 : command.op === 'paintImage' ? 8 * 1024 * 1024 + 1024 : 1024 * 1024)) return Promise.resolve({ id: command.id, ok: false, error: { message: 'Command is too large' } });
  if (cache.has(command.id)) { const saved = cache.get(command.id); return Promise.resolve(saved.fingerprint === fingerprint ? saved.response : { id: command.id, ok: false, error: { message: 'Command id was reused with different contents' } }); }
  if (pending.has(command.id)) { const saved = pending.get(command.id); return saved.fingerprint === fingerprint ? saved.task : Promise.resolve({ id: command.id, ok: false, error: { message: 'Command id was reused with different contents' } }); }
  if (pending.size >= 20) return Promise.resolve({ id: command.id, ok: false, error: { message: 'Plugin queue is full' } });
  if (retiredIds.size >= 10000) return Promise.resolve({ id: command.id, ok: false, error: { message: 'Session command limit reached. Close and reopen this plugin.' } });
  const task = queue.then(async () => { let response; try { response = { id: command.id, ok: true, result: await execute(command) }; } catch (e) { response = { id: command.id, ok: false, error: { message: String(e.message || e), partial: !!e.partial, mutatedNodeIds: e.mutatedNodeIds || [], createdNodeIds: e.createdNodeIds || [], ...(e.pageId ? { pageId: e.pageId, refs: e.refs || {} } : {}) } }; } cache.set(command.id, { fingerprint, response }); cachedCharacters += fingerprint.length; while (cache.size > 256 || cachedCharacters > 24 * 1024 * 1024) { const oldest = cache.keys().next().value; retiredIds.add(oldest); cachedCharacters -= cache.get(oldest).fingerprint.length; cache.delete(oldest); } return response; });
  pending.set(command.id, { fingerprint, task }); queue = task.then(() => undefined, () => undefined); task.then(() => pending.delete(command.id), () => pending.delete(command.id)); return task;
}
figma.ui.onmessage = async message => {
  if (!message || typeof message.type !== 'string') return;
  if (message.type === 'metadata') { post('metadata', { metadata: metadata() }); return; }
  if (message.type === 'bind') { const actual = fileKey(); boundFileKey = actual; post('bound', { metadata: metadata(), writable: !!actual }); return; }
  if (message.type === 'disconnect') { boundFileKey = null; return; }
  if (message.type === 'command') {
    const response = await dispatch(message.command);
    try { post('result', { response }); }
    catch (error) {
      const known = response.ok ? response.result || {} : response.error || {};
      const fallback = { id: response.id, ok: false, error: { message: contextualError('Result transport failed; inspect the canvas before retrying', error).message, partial: response.ok ? WRITE_OPS.has(message.command.op) : !!known.partial, createdNodeIds: known.createdNodeIds || [], mutatedNodeIds: known.mutatedNodeIds || [], ...(known.pageId ? { pageId: known.pageId, refs: known.refs || {} } : {}) } };
      post('result', { response: fallback });
    }
    post('metadata', { metadata: metadata() });
  }
};
figma.on('selectionchange', () => post('metadata', { metadata: metadata() }));
figma.on('currentpagechange', () => post('metadata', { metadata: metadata() }));
post('metadata', { metadata: metadata() });
