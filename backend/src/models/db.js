const postgres = require('postgres')

const sql = postgres('postgres://aayush:Aayush1234@localhost:5433/optilab_mvp', {
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
})

module.exports = sql