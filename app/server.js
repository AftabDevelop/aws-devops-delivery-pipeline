const express = require('express');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3000;

// Default metrics (CPU, memory, etc.)
client.collectDefaultMetrics();

// Custom metric: total requests
const httpRequests = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
});

app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequests.inc({
      method: req.method,
      route: req.route ? req.route.path : 'unmatched',
      status: res.statusCode,
    });
  });
  next();
});

app.get('/', (req, res) => res.send('Hello from the DevOps delivery pipeline!'));
app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(PORT, () => console.log(`App listening on port ${PORT}`));
