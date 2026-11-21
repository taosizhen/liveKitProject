import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';
import type { ServerOptions } from 'https';

// mkcert 自签证书路径（由 dev-tools/certs/localhost+3.pem 生成）
const certDir = path.resolve(__dirname, '../dev-tools/certs');
const certFile = path.join(certDir, 'localhost+3.pem');
const keyFile = path.join(certDir, 'localhost+3-key.pem');
const hasCerts = fs.existsSync(certFile) && fs.existsSync(keyFile);

// 后端代理地址：开发态 API 请求由 src/api/http.ts 直连 :8090，
// 此代理仅用于 /storage 静态资源（头像、材料等相对路径）。
// 走后端额外开启的本地回环 HTTP 端口（APP_HTTP_PORT=8139），避免自签证书与 TLS 握手问题。
const backendTarget = 'http://127.0.0.1:8139';

// Vite 配置
// - React 插件
// - 路径别名 @/ → src/
// - 开发代理 /api、/storage → Go 后端本地回环端口
// - HTTPS（需先跑 dev-tools/mkcert -install + 生成证书；无证书时回退 HTTP）
const httpsConfig: ServerOptions | undefined = hasCerts
  ? { cert: fs.readFileSync(certFile), key: fs.readFileSync(keyFile) }
  : undefined;

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    port: 5173,
    host: '0.0.0.0',
    https: httpsConfig,
    proxy: {
      '/api': { target: backendTarget, changeOrigin: true },
      '/storage': { target: backendTarget, changeOrigin: true },
    },
  },
});
