const express = require('express');
const r = express.Router();
const c = require('../controllers/contactsController');
const { authenticate } = require('../middleware/auth');

r.post('/lookup',        authenticate, c.lookupPhone);
r.post('/add',           authenticate, c.addContact);
r.get('/',               authenticate, c.getContacts);
r.delete('/:id',         authenticate, c.removeContact);
r.put('/:id/nickname',   authenticate, c.setNickname);
r.post('/:id/block',     authenticate, c.blockContact);

module.exports = r;
