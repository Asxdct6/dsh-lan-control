// Capture the DSH desktop host's auth cookie from the Electron main process.
//
// The host authenticates with a signed cookie whose authority is
// 127.0.0.1:<port>. The renderer never sees a token, and nothing is written to
// disk, so the only way to obtain it is to look at the traffic the main process
// makes on the renderer's behalf.
//
// This connects to the MAIN process inspector (--inspect=9229), wraps
// globalThis.fetch, waits for one API call carrying a dsh-auth-* cookie, then
// stores {port, cookie} for proxy.js.
//
// Usage: node capture-cookie.js [mainPort] [pagePort] [stateFile] [waitSeconds]

const http = require('http');
const fs = require('fs');
const path = require('path');

const MAIN_PORT = Number(process.argv[2] || 9229);
const PAGE_PORT = Number(process.argv[3] || 9222);
const STATE_FILE =
  process.argv[4] || path.join(process.env.USERPROFILE || process.env.HOME || '.', '.dsh', 'electron-cookie.json');
const WAIT_SECONDS = Number(process.argv[5] || 25);

const HOOK = `
(function () {
  if (globalThis.__cookieHook) return 'already';
  globalThis.__cookieHook = true;
  if (!globalThis.__cookies) globalThis.__cookies = [];
  var of = globalThis.fetch;
  globalThis.fetch = function (input, init) {
    try {
      var u = typeof input === 'string' ? input : (input && input.url) || String(input);
      var ck = null;
      try { if (init && init.headers) ck = new Headers(init.headers).get('cookie'); } catch (e) {}
      if (ck && /dsh-auth-/.test(ck)) {
        globalThis.__cookies.push({ url: u, cookie: ck });
        while (globalThis.__cookies.length > 20) globalThis.__cookies.shift();
      }
    } catch (e) {}
    return of.apply(this, arguments);
  };
  return 'hooked';
})()
`;

function getJson(port) {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${port}/json`, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    ws.addEventListener('open', () => resolve(ws));
    ws.addEventListener('error', (e) => reject(new Error(e.message || 'ws error')));
  });
}

let msgId = 0;
function request(ws, method, params, timeoutMs = 4000) {
  return new Promise((resolve) => {
    const id = ++msgId;
    const onMsg = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id !== id) return;
      ws.removeEventListener('message', onMsg);
      resolve(m.result);
    };
    ws.addEventListener('message', onMsg);
    ws.send(JSON.stringify({ id, method, params }));
    setTimeout(() => resolve(null), timeoutMs);
  });
}

async function evalIn(ws, expression) {
  const r = await request(ws, 'Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (!r || r.exceptionDetails) return undefined;
  return r.result ? r.result.value : undefined;
}

(async () => {
  const mainTargets = await getJson(MAIN_PORT);
  const main = mainTargets[0];
  if (!main) { console.error(`no inspector target on :${MAIN_PORT} (is the app started with --inspect?)`); process.exit(1); }
  const mainWs = await connect(main.webSocketDebuggerUrl);
  await evalIn(mainWs, HOOK);

  let pagePort = null;
  try {
    const pages = await getJson(PAGE_PORT);
    const page = pages.find((t) => t.type === 'page');
    if (page) {
      const pageWs = await connect(page.webSocketDebuggerUrl);
      const base = await evalIn(pageWs, '(window.__DSH_TRANSPORT__||{}).streamBaseUrl || ""');
      const m = /:(\d+)/.exec(String(base || ''));
      if (m) pagePort = Number(m[1]);
      pageWs.close();
    }
  } catch {}

  const deadline = Date.now() + WAIT_SECONDS * 1000;
  let reloaded = false;

  while (Date.now() < deadline) {
    const raw = await evalIn(mainWs, 'JSON.stringify((globalThis.__cookies||[]).slice(-5))');
    if (raw) {
      let list = [];
      try { list = JSON.parse(raw); } catch {}
      if (list.length) {
        const hit = list[list.length - 1];
        const m = /127\.0\.0\.1:(\d+)/.exec(hit.url) || /127\.0\.0\.1:(\d+)/.exec(hit.cookie);
        const port = pagePort || (m ? Number(m[1]) : null);
        if (port) {
          fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
          fs.writeFileSync(STATE_FILE, JSON.stringify({ port, cookie: hit.cookie, capturedAt: new Date().toISOString() }, null, 2), 'utf8');
          console.log(`captured: port=${port} cookieLen=${hit.cookie.length}`);
          process.exit(0);
        }
      }
    }

    // Nothing after 8s: reload the window once to force API traffic
    if (!reloaded && Date.now() - deadline + WAIT_SECONDS * 1000 > 8000) {
      try {
        const pages = await getJson(PAGE_PORT);
        const page = pages.find((t) => t.type === 'page');
        if (page) {
          const ws = await connect(page.webSocketDebuggerUrl);
          await request(ws, 'Page.reload', {});
          ws.close();
          reloaded = true;
        }
      } catch {}
    }

    await new Promise((r) => setTimeout(r, 700));
  }

  console.error('capture timed out');
  process.exit(2);
})();
