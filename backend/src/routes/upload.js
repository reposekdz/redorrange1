const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const path = require('path');

// POST /api/upload/file - generic file upload
r.post('/file', authenticate, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, message: 'No file provided' });
  res.json({
    success: true,
    url:      getFileUrl(req, req.file.path),
    filename: req.file.originalname,
    size:     req.file.size,
    mimetype: req.file.mimetype,
  });
});

// POST /api/upload/image
r.post('/image', authenticate, upload.single('image'), (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, message: 'No image provided' });
  res.json({
    success: true,
    url:  getFileUrl(req, req.file.path),
    size: req.file.size,
    width:  req.body.width  || null,
    height: req.body.height || null,
  });
});

// POST /api/upload/media - multiple files
r.post('/media', authenticate, upload.array('files', 10), (req, res) => {
  if (!req.files?.length) return res.status(400).json({ success: false, message: 'No files provided' });
  const files = req.files.map(f => ({
    url:      getFileUrl(req, f.path),
    filename: f.originalname,
    size:     f.size,
    mimetype: f.mimetype,
  }));
  res.json({ success: true, files });
});

// POST /api/upload/avatar
r.post('/avatar', authenticate, upload.single('avatar'), async (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, message: 'No avatar provided' });
  const url = getFileUrl(req, req.file.path);
  const db = require('../config/database');
  await db.query('UPDATE users SET avatar_url=? WHERE id=?', [url, req.userId]);
  res.json({ success: true, url });
});

module.exports = r;
