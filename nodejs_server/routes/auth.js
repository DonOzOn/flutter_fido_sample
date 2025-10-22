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
        residentKey: 'required', // Changed from 'preferred' to 'required' to ensure passkey is stored on device
        userVerification: 'preferred',
        requireResidentKey: true, // Explicitly require resident key for discoverability
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
    const response = {
      ...options,
      challengeId,
    };

    console.log('Registration options being sent to client:');
    console.log('- residentKey:', options.authenticatorSelection?.residentKey);
    console.log('- requireResidentKey:', options.authenticatorSelection?.requireResidentKey);
    console.log('- Full authenticatorSelection:', JSON.stringify(options.authenticatorSelection));

    res.json(response);
  } catch (error) {
    console.error('Registration begin error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// Registration - Step 2: Complete registration
router.post('/register/complete', async (req, res) => {
  try {
    const { email, id, rawId, response, type, challengeId } = req.body;

    if (!email || !id || !rawId || !response || !response.clientDataJSON || !response.attestationObject || !challengeId) {
      console.error('Missing fields:', { email: !!email, id: !!id, rawId: !!rawId, response: !!response, challengeId: !!challengeId });
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
    // Note: The Flutter passkeys package returns base64url-encoded strings
    // Android apps send origin as "android:apk-key-hash:<hash>" format
    const verification = await verifyRegistrationResponse({
      response: {
        id: id, // Already base64url-encoded string
        rawId: id, // Use same as id since they should match
        response: {
          clientDataJSON: response.clientDataJSON, // Already base64url-encoded
          attestationObject: response.attestationObject, // Already base64url-encoded
        },
        type: type || 'public-key',
      },
      expectedChallenge: storedChallenge.challenge,
      expectedOrigin: [
        process.env.RP_ORIGIN, // Web origin
        'android:apk-key-hash:K_PdYLiqF4KxnjAlbxdmu3QbKslx3NL5ubOJ6Z9jOEc', // Android app origin
      ],
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
      id,
      Buffer.from(verification.registrationInfo.credentialPublicKey).toString('base64'),
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
    res.status(500).json({ message: 'Internal server error', error: error.message });
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
    // Include allowCredentials to help Android find the specific passkey
    const options = await generateAuthenticationOptions({
      rpID: process.env.RP_ID,
      allowCredentials: credentials.map(cred => ({
        id: Buffer.from(cred.credential_id, 'base64url'), // Convert base64url string to Buffer
        type: 'public-key',
        transports: ['internal'], // Platform authenticator (biometric)
      })),
      userVerification: 'preferred',
    });

    console.log('Sign-in options - allowCredentials:',
      options.allowCredentials?.map(c => ({ id: c.id, type: c.type })));

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
    const { id, rawId, response, type, challengeId } = req.body;

    if (!id || !rawId || !response || !response.clientDataJSON || !response.authenticatorData || !response.signature || !challengeId) {
      console.error('Missing fields:', { id: !!id, rawId: !!rawId, response: !!response, challengeId: !!challengeId });
      return res.status(400).json({ message: 'Missing required fields' });
    }

    // Get stored challenge
    const storedChallenge = await db.getChallenge(challengeId);
    if (!storedChallenge) {
      return res.status(400).json({ message: 'Invalid or expired challenge' });
    }

    // Get credential by ID (this identifies the user)
    const credential = await db.getCredentialByCredentialId(id);
    if (!credential) {
      await db.deleteChallenge(challengeId);
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    // Get user from credential
    const user = await db.getUserById(credential.user_id);
    if (!user) {
      await db.deleteChallenge(challengeId);
      return res.status(400).json({ message: 'User not found' });
    }

    // Verify authentication response
    // Note: The Flutter passkeys package returns base64url-encoded strings
    // Android apps send origin as "android:apk-key-hash:<hash>" format
    const verification = await verifyAuthenticationResponse({
      response: {
        id: id, // Already base64url-encoded string
        rawId: id, // Use same as id since they should match
        response: {
          clientDataJSON: response.clientDataJSON, // Already base64url-encoded
          authenticatorData: response.authenticatorData, // Already base64url-encoded
          signature: response.signature, // Already base64url-encoded
        },
        type: type || 'public-key',
      },
      expectedChallenge: storedChallenge.challenge,
      expectedOrigin: [
        process.env.RP_ORIGIN, // Web origin
        'android:apk-key-hash:K_PdYLiqF4KxnjAlbxdmu3QbKslx3NL5ubOJ6Z9jOEc', // Android app origin
      ],
      expectedRPID: process.env.RP_ID,
      authenticator: {
        credentialID: credential.credential_id, // Already stored as base64url
        credentialPublicKey: Buffer.from(credential.public_key, 'base64'),
        counter: credential.counter,
      },
    });

    if (!verification.verified) {
      await db.deleteChallenge(challengeId);
      return res.status(400).json({ message: 'Authentication verification failed' });
    }

    // Update credential counter
    await db.updateCredentialCounter(id, verification.authenticationInfo.newCounter);

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
    res.status(500).json({ message: 'Internal server error', error: error.message });
  }
});

module.exports = router;
