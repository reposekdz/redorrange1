const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host:               process.env.DB_HOST     || 'localhost',
  port:           parseInt(process.env.DB_PORT || '3306'),
  user:               process.env.DB_USER     || 'root',
  password:           process.env.DB_PASSWORD || '',
  database:           process.env.DB_NAME     || 'redorrange',
  waitForConnections: true,
  connectionLimit:    20,
  queueLimit:         0,
  timezone:           '+00:00',
  charset:            'utf8mb4',
  enableKeepAlive:    true,
  keepAliveInitialDelay: 0,
});

const db = {
  query: async (sql, params = []) => {
    const [rows] = await pool.execute(sql, params);
    return rows;
  },
  queryOne: async (sql, params = []) => {
    const [rows] = await pool.execute(sql, params);
    return rows[0] || null;
  },
  transaction: async (fn) => {
    const conn = await pool.getConnection();
    await conn.beginTransaction();
    try {
      const result = await fn(conn);
      await conn.commit();
      return result;
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  },
  test: async () => {
    try {
      await pool.query('SELECT 1');
      return true;
    } catch (e) {
      console.error('[DB] Connection failed:', e.message);
      return false;
    }
  },
};

module.exports = db;
