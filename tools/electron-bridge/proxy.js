// Reverse proxy that exposes a local DSH host to the tailnet.
//
// The DSH desktop host binds 127.0.0.1:<random port> and authenticates with a
// signed cookie whose authority is 127.0.0.1:<port>. This proxy rewrites
// Host/Origin to that loopback authority and replays the captured cookie, so a
// remote client can use it without ever seeing the token.
//
// Usage: node proxy.js <listenPort> [stateFile]
//   stateFile defaults to %USERPROFILE%\.dsh\electron-cookie.json
//   and must contain {"port": <number>, "cookie": "<dsh-auth-...=...>"}.
//
// Stateless on purpose: it re-reads the state file on every request, so
// refreshing the cookie needs no restart.

const http = require('http');
const fs = require('fs');
const path = require('path');

const LISTEN_PORT = Number(process.argv[2] || 8791);
const STATE_FILE =
  process.argv[3] || path.join(process.env.USERPROFILE || process.env.HOME || '.', '.dsh', 'electron-cookie.json');

function readState() {
  try {
    const s = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    return s && s.port && s.cookie ? s : null;
  } catch {
    return null;
  }
}

function upstreamHeaders(req, state) {
  const headers = { ...req.headers };
  headers.host = `127.0.0.1:${state.port}`;
  headers.cookie = state.cookie;
  if (headers.origin) headers.origin = `http://127.0.0.1:${state.port}`;
  if (headers.referer) {
    headers.referer = String(headers.referer).replace(/^https?:\/\/[^/]+/, `http://127.0.0.1:${state.port}`);
  }
  delete headers['x-forwarded-host'];
  delete headers['x-forwarded-proto'];
  delete headers['x-forwarded-for'];
  return headers;
}

const server = http.createServer((req, res) => {
  const state = readState();
  if (!state) {
    res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('desktop session not captured yet');
    return;
  }

  const up = http.request(
    {
      host: '127.0.0.1',
      port: state.port,
      method: req.method,
      path: req.url,
      headers: upstreamHeaders(req, state),
    },
    (ur) => {
      const h = { ...ur.headers };
      if (h['set-cookie']) {
        h['set-cookie'] = h['set-cookie'].map((c) => c.replace(/;\s*domain=[^;]+/i, ''));
      }
      if (h.location) {
        h.location = String(h.location).replace(
          new RegExp(`127\\.0\\.0\\.1:${state.port}`, 'g'),
          req.headers.host || 'localhost'
        );
      }
      res.writeHead(ur.statusCode || 502, h);
      ur.pipe(res);
    }
  );

  up.on('error', (e) => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' });
    try { res.end(`upstream error: ${e.message}`); } catch {}
  });

  req.pipe(up);
});

server.on('upgrade', (req, socket, head) => {
  const state = readState();
  if (!state) { socket.destroy(); return; }

  const up = http.request({
    host: '127.0.0.1',
    port: state.port,
    method: req.method,
    path: req.url,
    headers: upstreamHeaders(req, state),
  });

  up.on('upgrade', (ur, usock, uhead) => {
    let raw = 'HTTP/1.1 101 Switching Protocols\r\n';
    for (let i = 0; i < ur.rawHeaders.length; i += 2) {
      raw += `${ur.rawHeaders[i]}: ${ur.rawHeaders[i + 1]}\r\n`;
    }
    raw += '\r\n';
    socket.write(raw);
    if (uhead && uhead.length) socket.write(uhead);
    if (head && head.length) usock.write(head);
    usock.pipe(socket);
    socket.pipe(usock);
    usock.on('error', () => socket.destroy());
    socket.on('error', () => usock.destroy());
  });

  up.on('error', () => socket.destroy());
  up.end();
});

server.on('error', (e) => { console.error('listen failed:', e.message); process.exit(1); });

server.listen(LISTEN_PORT, '127.0.0.1', () => {
  console.log(`proxy listening on 127.0.0.1:${LISTEN_PORT} (state: ${STATE_FILE})`);
});
