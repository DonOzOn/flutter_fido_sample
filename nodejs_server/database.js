const sqlite3 = require('sqlite3').verbose();
const path = require('path');

class Database {
  constructor() {
    this.db = new sqlite3.Database(process.env.DB_PATH || './database.sqlite');
    this.init();
  }

  init() {
    // Create users table
    this.db.run(`
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Create credentials table for FIDO2 authenticators
    this.db.run(`
      CREATE TABLE IF NOT EXISTS credentials (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        credential_id TEXT UNIQUE NOT NULL,
        public_key TEXT NOT NULL,
        counter INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    `);

    // Create challenges table for temporary storage
    this.db.run(`
      CREATE TABLE IF NOT EXISTS challenges (
        id TEXT PRIMARY KEY,
        challenge TEXT NOT NULL,
        user_email TEXT,
        type TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);
  }

  // User operations
  createUser(id, email, name) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO users (id, email, name) VALUES (?, ?, ?)',
        [id, email, name],
        function(err) {
          if (err) reject(err);
          else resolve({ id, email, name });
        }
      );
    });
  }

  getUserByEmail(email) {
    return new Promise((resolve, reject) => {
      this.db.get(
        'SELECT * FROM users WHERE email = ?',
        [email],
        (err, row) => {
          if (err) reject(err);
          else resolve(row);
        }
      );
    });
  }

  getUserById(id) {
    return new Promise((resolve, reject) => {
      this.db.get(
        'SELECT * FROM users WHERE id = ?',
        [id],
        (err, row) => {
          if (err) reject(err);
          else resolve(row);
        }
      );
    });
  }

  // Credential operations
  saveCredential(id, userId, credentialId, publicKey, counter = 0) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO credentials (id, user_id, credential_id, public_key, counter) VALUES (?, ?, ?, ?, ?)',
        [id, userId, credentialId, publicKey, counter],
        function(err) {
          if (err) reject(err);
          else resolve({ id, userId, credentialId, publicKey, counter });
        }
      );
    });
  }

  getCredentialByCredentialId(credentialId) {
    return new Promise((resolve, reject) => {
      this.db.get(
        'SELECT * FROM credentials WHERE credential_id = ?',
        [credentialId],
        (err, row) => {
          if (err) reject(err);
          else resolve(row);
        }
      );
    });
  }

  getCredentialsByUserId(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM credentials WHERE user_id = ?',
        [userId],
        (err, rows) => {
          if (err) reject(err);
          else resolve(rows);
        }
      );
    });
  }

  updateCredentialCounter(credentialId, counter) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE credentials SET counter = ? WHERE credential_id = ?',
        [counter, credentialId],
        function(err) {
          if (err) reject(err);
          else resolve(this.changes > 0);
        }
      );
    });
  }

  // Challenge operations
  saveChallenge(id, challenge, userEmail, type) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO challenges (id, challenge, user_email, type) VALUES (?, ?, ?, ?)',
        [id, challenge, userEmail, type],
        function(err) {
          if (err) reject(err);
          else resolve({ id, challenge, userEmail, type });
        }
      );
    });
  }

  getChallenge(id) {
    return new Promise((resolve, reject) => {
      this.db.get(
        'SELECT * FROM challenges WHERE id = ?',
        [id],
        (err, row) => {
          if (err) reject(err);
          else resolve(row);
        }
      );
    });
  }

  deleteChallenge(id) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'DELETE FROM challenges WHERE id = ?',
        [id],
        function(err) {
          if (err) reject(err);
          else resolve(this.changes > 0);
        }
      );
    });
  }

  // Clean up old challenges (older than 5 minutes)
  cleanupOldChallenges() {
    return new Promise((resolve, reject) => {
      this.db.run(
        "DELETE FROM challenges WHERE created_at < datetime('now', '-5 minutes')",
        function(err) {
          if (err) reject(err);
          else resolve(this.changes);
        }
      );
    });
  }

  close() {
    this.db.close();
  }
}

module.exports = Database;
