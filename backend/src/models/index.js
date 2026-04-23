// User model stub for passport authentication
class User {
  constructor(id, email, name) {
    this.id = id;
    this.email = email;
    this.name = name;
  }

  static async findById(id) {
    // TODO: Implement actual user lookup from database
    // This is a placeholder for the passport JWT strategy
    return null;
  }
}

// CFRS Model
const CFRSModel = require('./cfrs_models');

module.exports = {
  User,
  CFRSModel,
};
