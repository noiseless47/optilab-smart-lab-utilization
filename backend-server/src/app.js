const express = require('express');
const cors = require('cors');
const config = require('./config/config');
const routes = require('./routes');

const app = express();

// parse json request body
app.use(express.json());

// parse urlencoded request body
app.use(express.urlencoded({ extended: true }));

// enable cors
app.use(cors());
app.options('*', cors());

// api routes
app.use('/', routes);

// send back a 404 error for any unknown api request
app.use((req, res, next) => {
  res.status(404).json({ error: 'Not found' });
});

// handle error
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

module.exports = app;
