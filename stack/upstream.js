// Stands in for the teams' backend services. It answers every request with a small JSON body
// and sets no CORS headers, so the Gateway alone decides which browser origins are allowed.
const http = require('http');
http.createServer((req, res) => {
  const service = (req.url.split('/')[2] || 'unknown').split('?')[0];
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ service, method: req.method, path: req.url }) + '\n');
}).listen(8080, () => console.log('upstream listening on 8080'));
