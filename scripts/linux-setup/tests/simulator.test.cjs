const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../assets/simulator-fix.js'), 'utf8');
function frame({pathname = '/panel', search = '?simulator=1', top = false} = {}) {
  const messages = [], timers = new Map();
  let listener, next = 0;
  const parent = {};
  const window = {parent, addEventListener: (_, fn) => listener = fn,
    postMessage: (msg, origin) => messages.push({msg, origin})};
  if (top) window.parent = window;
  vm.runInNewContext(script, {window, location: {pathname, search, origin: 'http://localhost:9400'},
    URLSearchParams, setTimeout: fn => {timers.set(++next, fn); return next;},
    clearTimeout: id => timers.delete(id)});
  return {messages, send: (data, origin = 'http://localhost:9400', source = window.parent) =>
    listener?.({data, origin, source}), flush: () => {for (const [id, fn] of [...timers]) {timers.delete(id); fn();}}};
}
const theme = {type: 'simulator/set-theme', theme: {color: 'red'}};
const layout = {type: 'simulator/set-layout', layout: {surface: 'y70', widgets: [{id: 'fixture'}]}};
test('waits for both real values and initializes exactly once in either order', () => {
  for (const events of [[theme, layout], [layout, theme]]) {
    const f = frame(); f.send(events[0]); f.flush(); assert.equal(f.messages.length, 0);
    f.send(events[1]); f.flush(); f.send(layout); f.flush();
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].msg.type, 'simulator/init');
    assert.equal(f.messages[0].msg.layout.widgets[0].id, 'fixture');
    assert.equal(f.messages[0].origin, 'http://localhost:9400');
  }
});
test('real init cancels pending synthetic init', () => {
  const f = frame(); f.send(theme); f.send(layout);
  f.send({type: 'simulator/init', layout: layout.layout, theme: theme.theme}); f.flush();
  assert.equal(f.messages.filter(x => x.msg.type === 'simulator/init').length, 0);
});
test('ignores foreign origins and non-parent sources', () => {
  const f = frame(); f.send(theme, 'https://example.invalid'); f.send(layout); f.flush();
  f.send(theme, 'http://localhost:9400', {}); f.flush(); assert.equal(f.messages.length, 0);
});
test('does not affect top-level pages, other routes or non-simulator frames', () => {
  for (const options of [{top: true}, {pathname: '/panel/saved'}, {search: ''}]) {
    const f = frame(options); f.send(theme); f.send(layout); f.flush(); assert.equal(f.messages.length, 0);
  }
});
test('does not initialize or force visibility for phone layouts', () => {
  const f = frame(); f.send(theme); f.send({type: 'simulator/set-layout', layout: {surface: 'phone'}});
  f.send({type: 'simulator/set-display', showPanel: false}); f.flush(); assert.equal(f.messages.length, 0);
});
test('each iframe reload gets its own initialization', () => {
  for (let i=0;i<2;i++) {const f=frame(); f.send(theme); f.send(layout); f.flush(); assert.equal(f.messages.length,1);}
});
