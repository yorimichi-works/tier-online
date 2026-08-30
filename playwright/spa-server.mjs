// Flutter Web(SPA)を配信する最小限の静的サーバー。
// クライアントサイドルーティング(/ja/tier/xxx 等)に対応するため、
// 拡張子を持たないパスは index.html にフォールバックする。
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const root = process.argv[2] ?? 'build/web';
const port = Number(process.argv[3] ?? 8973);

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.ico': 'image/x-icon',
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? '/', 'http://localhost');
    let filePath = normalize(join(root, decodeURIComponent(url.pathname)));
    if (!filePath.startsWith(normalize(root))) {
      res.writeHead(403).end('Forbidden');
      return;
    }
    let stats;
    try {
      stats = await stat(filePath);
    } catch {
      stats = null;
    }
    if (!stats || stats.isDirectory() || extname(filePath) === '') {
      filePath = join(root, 'index.html');
    }
    const ext = extname(filePath);
    const body = await readFile(filePath);
    res.writeHead(200, {
      'Content-Type': mimeTypes[ext] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
    });
    res.end(body);
  } catch (error) {
    res.writeHead(500).end(String(error));
  }
});

server.listen(port, () => {
  console.log(`SPA server serving ${root} on http://localhost:${port}`);
});
