const multer = require('multer');
const path   = require('path');
const fs     = require('fs');
const { v4: uuidv4 } = require('uuid');

const ensure = (dir) => { if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true }); };

const FIELD_MAP = {
  avatar:        'uploads/avatars',
  cover:         'uploads/covers',
  post_media:    'uploads/posts',
  story:         'uploads/stories',
  reel:          'uploads/reels',
  thumbnail:     'uploads/reels',
  message_file:  'uploads/messages',
  voice_note:    'uploads/voicenotes',
  event_cover:   'uploads/events',
  highlight_cover: 'uploads/highlights',
};

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = FIELD_MAP[file.fieldname] || 'uploads/misc';
    ensure(dir);
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `${uuidv4()}${ext}`);
  },
});

const ALLOWED = new Set([
  'image/jpeg','image/jpg','image/png','image/gif','image/webp',
  'video/mp4','video/mov','video/avi','video/mkv','video/quicktime','video/webm',
  'audio/mpeg','audio/mp4','audio/wav','audio/ogg','audio/webm','audio/m4a','audio/aac',
  'application/pdf','application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel','text/plain','application/zip',
]);

const fileFilter = (req, file, cb) => {
  if (ALLOWED.has(file.mimetype)) cb(null, true);
  else cb(new Error(`File type ${file.mimetype} not allowed`), false);
};

const upload = multer({ storage, fileFilter, limits: { fileSize: 100 * 1024 * 1024 } });

const getFileUrl = (req, filePath) => {
  if (!filePath) return null;
  return `${req.protocol}://${req.get('host')}/${filePath.replace(/\\/g, '/')}`;
};

module.exports = { upload, getFileUrl };
