// A tiny static web server for trying the page locally (GitHub Pages serves the same files).
//   node tools/serve.js [port=8775]
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const PORT = +process.argv[2] || +process.env.PORT || 8775;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.lua': 'text/plain; charset=utf-8', '.toc': 'text/plain; charset=utf-8', '.json': 'application/json', '.ico': 'image/x-icon' };
http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p.endsWith('/')) p += 'index.html';
  const file = path.join(ROOT, p);
  if (!file.startsWith(ROOT) || /[\\/](private|tools|\.git)([\\/]|$)/.test(path.relative(ROOT, file).replace(/^/, '/'))) { res.writeHead(404); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
}).listen(PORT, () => console.log('Forever Warlock Arcade on http://localhost:' + PORT));
