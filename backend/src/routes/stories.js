'use strict';
const express = require('express');
const r = express.Router();
const { authenticate, optionalAuth } = require('../middleware/auth');
const { upload } = require('../middleware/upload');
const c = require('../controllers/storiesController');

r.get('/feed',                  authenticate,                          c.storiesFeed);
r.get('/user/:userId',          optionalAuth,                          c.getUserStories);
r.post('/',                     authenticate, upload.single('story'),  c.createStory);
r.post('/:id/view',             authenticate,                          c.viewStory);
r.get('/:id/viewers',           authenticate,                          c.getStoryViewers);
r.post('/:id/reply',            authenticate,                          c.replyToStory);
r.post('/:id/react',            authenticate,                          c.reactToStory);
r.delete('/:id',                authenticate,                          c.deleteStory);

r.get('/highlights/:userId',    authenticate,                          c.getHighlights);
r.post('/highlights',           authenticate, upload.single('cover'),  c.createHighlight);
r.delete('/highlights/:id',     authenticate,                          c.deleteHighlight);

module.exports = r;
