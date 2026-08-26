const fs = require('node:fs');
fs.rmSync('dist', { recursive: true, force: true });
fs.cpSync('frontend/dist', 'dist', { recursive: true });
