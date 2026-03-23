const express    = require('express');
const r          = express.Router();
const c          = require('../controllers/authController');
const { authenticate } = require('../middleware/auth');
const { upload } = require('../middleware/upload');
const rateLimit  = require('express-rate-limit');

const otpLimiter = rateLimit({ windowMs: 15*60*1000, max: 10, message: { success: false, message: 'Too many OTP requests. Try in 15 minutes.' } });
const loginLimit = rateLimit({ windowMs: 15*60*1000, max: 20, message: { success: false, message: 'Too many login attempts.' } });

r.post('/send-otp',            otpLimiter,  c.sendOtp);
r.post('/verify-otp',          loginLimit,  c.verifyOtp);
r.post('/setup-profile',       authenticate, upload.single('avatar'), c.setupProfile);
r.post('/refresh',             c.refresh);
r.post('/logout',              authenticate, c.logout);
r.get('/me',                   authenticate, c.me);

// QR Login
r.get('/qr-generate',          c.generateQR);
r.post('/qr-scan',             authenticate, c.scanQR);
r.get('/qr-status/:sessionId', c.qrStatus);

// Account management
r.get('/check-username',       c.checkUsername);
r.put('/change-password',      authenticate, c.changePassword);
r.get('/devices',              authenticate, c.getDevices);
r.delete('/devices/:id',       authenticate, c.revokeDevice);

module.exports = r;
