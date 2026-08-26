const express = require('express');
const cors = require('cors');
const path = require('path');
const { createDemoData } = require('./localDemoData');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'camfeddashboard')));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', source: 'local-demo-data' });
});

app.get('/api/data', (req, res) => {
  res.json(createDemoData());
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log('CAMFED demo API listening on http://localhost:' + PORT);
  console.log('Data source: local dummy data bundled with this repository');
});
