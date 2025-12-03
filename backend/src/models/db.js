const postgres = require('postgres')

const connectionString = 'postgres://postgres:aayush@localhost:5433/optilab_mvp'

const sql = postgres(connectionString, {
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
})

module.exports = sql