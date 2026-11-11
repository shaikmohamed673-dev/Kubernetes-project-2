const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

// Settings come from environment variables (set in docker-compose.yml)
const pool = new Pool({
  host: process.env.DB_HOST,       // "db" = service name; Docker DNS resolves it
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  database: process.env.POSTGRES_DB,
  port: 5432,
});

app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/api/messages', async (_req, res) => {
  try {
    const r = await pool.query('SELECT * FROM messages ORDER BY id DESC LIMIT 20');
    res.json(r.rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/messages', async (req, res) => {
  const text = (req.body.text || '').trim();
  if (!text) return res.status(400).json({ error: 'text required' });
  try {
    const r = await pool.query('INSERT INTO messages(text) VALUES($1) RETURNING *', [text]);
    res.status(201).json(r.rows[0]);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.listen(3000, () => console.log('Backend listening on :3000'));
