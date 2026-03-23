const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false,
});

let paramCounter = 0;

const db = {
  query: async (sql, params = []) => {
    const pgSql = toPostgres(sql);
    const { rows } = await pool.query(pgSql, params);
    return rows;
  },
  queryOne: async (sql, params = []) => {
    const pgSql = toPostgres(sql);
    const { rows } = await pool.query(pgSql, params);
    return rows[0] || null;
  },
  transaction: async (fn) => {
    const client = await pool.connect();
    await client.query('BEGIN');
    try {
      const db2 = {
        query: async (sql, params = []) => {
          const { rows } = await client.query(toPostgres(sql), params);
          return rows;
        },
        queryOne: async (sql, params = []) => {
          const { rows } = await client.query(toPostgres(sql), params);
          return rows[0] || null;
        },
      };
      const result = await fn(db2);
      await client.query('COMMIT');
      return result;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
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
  pool,
};

function toPostgres(sql) {
  let i = 0;
  return sql.replace(/\?/g, () => `$${++i}`);
}

module.exports = db;
