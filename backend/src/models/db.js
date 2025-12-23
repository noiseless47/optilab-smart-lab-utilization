import postgres from 'postgres'

const connectionString = 'postgres://postgres:aayush@localhost:5433/optilab_mvp'

const sql = postgres(connectionString, {
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
})

export default sql