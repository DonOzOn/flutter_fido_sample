require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const bodyParser = require('body-parser');
const Database = require('./database');
const authRoutes = require('./routes/auth');
const authMiddleware = require('./middleware/auth');

const app = express();
const PORT = process.env.PORT || 3000;

// Initialize database
const db = new Database();

// Middleware
app.use(helmet());
app.use(cors({
  origin: ['http://localhost:3000', 'http://127.0.0.1:3000'],
  credentials: true,
}));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Serve .well-known files for Digital Asset Links and Apple App Site Association
app.use('/.well-known', express.static('public/.well-known'));

// Routes
app.use('/api/auth', authRoutes);

// Protected route example
app.get('/api/profile', authMiddleware, (req, res) => {
  res.json({
    success: true,
    user: {
      id: req.user.id,
      email: req.user.email,
      name: req.user.name,
      createdAt: req.user.created_at,
    },
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    service: 'FIDO2 Authentication Server'
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ 
    message: 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

// Cleanup old challenges every 5 minutes
setInterval(async () => {
  try {
    const deleted = await db.cleanupOldChallenges();
    if (deleted > 0) {
      console.log(`Cleaned up ${deleted} old challenges`);
    }
  } catch (error) {
    console.error('Error cleaning up challenges:', error);
  }
}, 5 * 60 * 1000);

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down server...');
  db.close();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('Shutting down server...');
  db.close();
  process.exit(0);
});

app.listen(PORT, () => {
  console.log(`FIDO2 Authentication Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
