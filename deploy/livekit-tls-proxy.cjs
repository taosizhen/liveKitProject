/**
 * LiveKit 信令 TLS 终止代理
 * LiveKit 服务本身不支持在信令端口直接启用 TLS，官方推荐前置反向代理。
 * 本脚本用 mkcert 证书在 7891 端口提供 HTTPS/WSS，转发到本机 7890 端口的 LiveKit。
 * 用法: node deploy/livekit-tls-proxy.cjs
 */
const https = require('https');
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');

const CERT_DIR = path.resolve(__dirname, '../dev-tools/certs');
const CERT_FILE = path.join(CERT_DIR, 'localhost+3.pem');
const KEY_FILE = path.join(CERT_DIR, 'localhost+3-key.pem');

const LISTEN_PORT = 7891;
const TARGET_HOST = '127.0.0.1';
// 7890 被 FlClash 代理内核占用、7880 被 Windows 保留，LiveKit 实际监听 7895
const TARGET_PORT = 7895;

if (!fs.existsSync(CERT_FILE) || !fs.existsSync(KEY_FILE)) {
  console.error(`[FATAL] 证书缺失: ${CERT_FILE} / ${KEY_FILE}`);
  process.exit(1);
}

const tlsOptions = {
  cert: fs.readFileSync(CERT_FILE),
  key: fs.readFileSync(KEY_FILE),
};

/**
 * 构造 CORS 响应头
 *
 * Web 前端（:5173）与 LiveKit（:7891）跨域，SDK 建连前会 fetch /rtc/validate。
 * LiveKit 自身不返回 CORS 头、且对 OPTIONS 预检回 400，浏览器会直接
 * 报 "Failed to fetch"，因此由代理统一补齐。
 */
function buildCorsHeaders(req) {
  const origin = req.headers.origin;
  return {
    // 回显来源而非 *，以便配合 credentials
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers':
      req.headers['access-control-request-headers'] || 'content-type, authorization',
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

/**
 * 代理普通 HTTP 请求
 */
const server = https.createServer(tlsOptions, (req, res) => {
  const corsHeaders = buildCorsHeaders(req);

  // 预检请求直接放行，不转发给 LiveKit（其对 OPTIONS 返回 400）
  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders);
    res.end();
    return;
  }

  const proxyReq = http.request(
    {
      host: TARGET_HOST,
      port: TARGET_PORT,
      path: req.url,
      method: req.method,
      headers: { ...req.headers, host: `${TARGET_HOST}:${TARGET_PORT}` },
    },
    (proxyRes) => {
      // 上游 LiveKit 也返回 access-control-allow-origin: *，若直接叠加会出现
      // 两个同名头，浏览器会判定为非法多值并拒绝，这里先剔除上游的 CORS 头
      const upstream = { ...proxyRes.headers };
      for (const key of Object.keys(upstream)) {
        if (key.toLowerCase().startsWith('access-control-')) delete upstream[key];
      }
      if (upstream.vary) {
        const rest = String(upstream.vary)
          .split(',')
          .map((v) => v.trim())
          .filter((v) => v.toLowerCase() !== 'origin');
        if (rest.length) upstream.vary = rest.join(', ');
        else delete upstream.vary;
      }
      res.writeHead(proxyRes.statusCode || 502, { ...upstream, ...corsHeaders });
      proxyRes.pipe(res);
    }
  );
  proxyReq.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'text/plain', ...corsHeaders });
    }
    res.end(`proxy error: ${err.message}`);
  });
  req.pipe(proxyReq);
});

/**
 * 隧道转发 WebSocket 升级请求（LiveKit 信令 /rtc）
 */
server.on('upgrade', (req, socket, head) => {
  const target = net.connect(TARGET_PORT, TARGET_HOST, () => {
    const headerLines = Object.entries({
      ...req.headers,
      host: `${TARGET_HOST}:${TARGET_PORT}`,
    })
      .map(([k, v]) => `${k}: ${v}`)
      .join('\r\n');
    target.write(`${req.method} ${req.url} HTTP/1.1\r\n${headerLines}\r\n\r\n`);
    if (head && head.length) target.write(head);
    socket.pipe(target);
    target.pipe(socket);
  });
  target.on('error', () => socket.destroy());
  socket.on('error', () => target.destroy());
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`[INFO] LiveKit TLS proxy: https://0.0.0.0:${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}`);
});
