const postgres = require('postgres')

// Connection configuration with explicit parameters
const sql = postgres({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5433,
  database: process.env.DB_NAME || 'optilab_mvp',
  user: process.env.DB_USER || 'aayush',
  password: process.env.DB_PASSWORD || 'aayush',
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
})

module.exports = sql