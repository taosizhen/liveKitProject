import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';
// mkcert 自签证书路径（由 dev-tools/certs/localhost+3.pem 生成）
var certDir = path.resolve(__dirname, '../dev-tools/certs');
var certFile = path.join(certDir, 'localhost+3.pem');
var keyFile = path.join(certDir, 'localhost+3-key.pem');
var hasCerts = fs.existsSync(certFile) && fs.existsSync(keyFile);
// Vite 配置
// - React 插件
// - 路径别名 @/ → src/
// - 开发代理 /api → Go 后端 8080 端口
// - HTTPS（需先跑 dev-tools/mkcert -install + 生成证书；无证书时回退 HTTP）
var httpsConfig = hasCerts
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
            '/api': { target: 'http://localhost:8080', changeOrigin: true },
            '/storage': { target: 'http://localhost:8080', changeOrigin: true },
        },
    },
});
