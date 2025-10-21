const express = require('express');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require('@simplewebauthn/server');
const Database = require('../database');

const router = express.Router();
const db = new Database();

// Registration - Step 1: Begin registration
router.post('/register/begin', async (req, res) => {
  try {
    const { email, name } = req.body;

    if (!email || !name) {
      return res.status(400).json({ message: 'Email and name are required' });
    }

    // Check if user already exists
    const existingUser = await db.getUserByEmail(email);
    if (existingUser) {
      return res.status(409).json({ message: 'User with this email already exists' });
    }

    const userId = uuidv4();
    const challengeId = uuidv4();

    // Generate registration options
    const options = await generateRegistrationOptions({
      rpName: process.env.RP_NAME,
      rpID: process.env.RP_ID,
      userID: Buffer.from(userId),
      userName: email,
      userDisplayName: name,
      attestationType: 'none',
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
        // Remove platform attachment to allow both platform and roaming authenticators
      },
      // Android supports these algorithms
      supportedAlgorithmIDs: [-7, -257, -8, -37, -38, -39],
      // -7: ES256 (ECDSA with SHA-256)
      // -257: RS256 (RSASSA-PKCS1-v1_5 with SHA-256)
      // -8: EdDSA
      // -37: PS256 (RSASSA-PSS with SHA-256)
      // -38: PS384
      // -39: PS512
    });

    // Save challenge temporarily
    await db.saveChallenge(challengeId, options.challenge, email, 'registration');

    // Add challengeId to response for client to send back
    res.json({
      ...options,
      challengeId,
    });
  } catch (error) {
    console.error('Registration begin error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// Registration - Step 2: Complete registration
router.post('/register/complete', async (req, res) => {
  try {
    const { email, credentialId, publicKey, authenticatorData, clientDataJSON, challengeId } = req.body;

    if (!email || !credentialId || !publicKey || !authenticatorData || !clientDataJSON || !challengeId) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    // Get stored challenge
    const storedChallenge = await db.getChallenge(challengeId);
    if (!storedChallenge) {
      return res.status(400).json({ message: 'Invalid or expired challenge' });
    }

    if (storedChallenge.user_email !== email) {
      return res.status(400).json({ message: 'Email mismatch' });
    }

    // Verify registration response
    const verification = await verifyRegistrationResponse({
      response: {
        id: credentialId,
        rawId: Buffer.from(credentialId, 'base64url'),
        response: {
          clientDataJSON: Buffer.from(clientDataJSON, 'base64url'),
          attestationObject: Buffer.from(authenticatorData, 'base64url'),
        },
        type: 'public-key',
      },
      expectedChallenge: storedChallenge.challenge,
      expectedOrigin: process.env.RP_ORIGIN,
      expectedRPID: process.env.RP_ID,
    });

    if (!verification.verified) {
      await db.deleteChallenge(challengeId);
      return res.status(400).json({ message: 'Registration verification failed' });
    }

    // Create user and save credential
    const userId = uuidv4();
    const user = await db.createUser(userId, email, storedChallenge.user_email);
    
    const credId = uuidv4();
    await db.saveCredential(
      credId,
      userId,
      credentialId,
      Buffer.from(publicKey, 'base64url').toString('base64'),
      verification.registrationInfo.counter
    );

    // Clean up challenge
    await db.deleteChallenge(challengeId);

    // Generate JWT token
    const token = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.status(201).json({
      success: true,
      message: 'Registration successful',
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        createdAt: new Date().toISOString(),
      },
      token,
    });
  } catch (error) {
    console.error('Registration complete error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// Sign in - Step 1: Begin authentication
router.post('/signin/begin', async (req, res) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ message: 'Email is required' });
    }

    // Check if user exists
    const user = await db.getUserByEmail(email);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Get user's credentials
    const credentials = await db.getCredentialsByUserId(user.id);
    if (credentials.length === 0) {
      return res.status(400).json({ message: 'No credentials found for user' });
    }

    const challengeId = uuidv4();

    // Generate authentication options
    const options = await generateAuthenticationOptions({
      rpID: process.env.RP_ID,
      allowCredentials: credentials.map(cred => ({
        id: Buffer.from(cred.credential_id, 'base64url'),
        type: 'public-key',
      })),
      userVerification: 'preferred',
    });

    // Save challenge temporarily
    await db.saveChallenge(challengeId, options.challenge, email, 'authentication');

    res.json({
      ...options,
      challengeId,
    });
  } catch (error) {
    console.error('Sign in begin error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// Sign in - Step 2: Complete authentication
router.post('/signin/complete', async (req, res) => {
  try {
    const { email, credentialId, authenticatorData, clientDataJSON, signature, challengeId } = req.body;

    if (!email || !credentialId || !authenticatorData || !clientDataJSON || !signature || !challengeId) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    // Get stored challenge
    const storedChallenge = await db.getChallenge(challengeId);
    if (!storedChallenge) {
      return res.status(400).json({ message: 'Invalid or expired challenge' });
    }

    if (storedChallenge.user_email !== email) {
      return res.status(400).json({ message: 'Email mismatch' });
    }

    // Get user and credential
    const user = await db.getUserByEmail(email);
    const credential = await db.getCredentialByCredentialId(credentialId);
    
    if (!user || !credential) {
      await db.deleteChallenge(challengeId);
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    // Verify authentication response
    const verification = await verifyAuthenticationResponse({
      response: {
        id: credentialId,
        rawId: Buffer.from(credentialId, 'base64url'),
        response: {
          clientDataJSON: Buffer.from(clientDataJSON, 'base64url'),
          authenticatorData: Buffer.from(authenticatorData, 'base64url'),
          signature: Buffer.from(signature, 'base64url'),
        },
        type: 'public-key',
      },
      expectedChallenge: storedChallenge.challenge,
      expectedOrigin: process.env.RP_ORIGIN,
      expectedRPID: process.env.RP_ID,
      authenticator: {
        credentialID: Buffer.from(credential.credential_id, 'base64url'),
        credentialPublicKey: Buffer.from(credential.public_key, 'base64'),
        counter: credential.counter,
      },
    });

    if (!verification.verified) {
      await db.deleteChallenge(challengeId);
      return res.status(400).json({ message: 'Authentication verification failed' });
    }

    // Update credential counter
    await db.updateCredentialCounter(credentialId, verification.authenticationInfo.newCounter);

    // Clean up challenge
    await db.deleteChallenge(challengeId);

    // Generate JWT token
    const token = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.json({
      success: true,
      message: 'Authentication successful',
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        createdAt: user.created_at,
      },
      token,
    });
  } catch (error) {
    console.error('Sign in complete error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

module.exports = router;
