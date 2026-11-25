// Kindle WhatsApp köprüsü (Baileys). Kullanım: TOKEN=gizli node server.js
const {
  default: makeWASocket, useMultiFileAuthState, DisconnectReason,
  fetchLatestBaileysVersion, Browsers,
} = require('@whiskeysockets/baileys');
const express = require('express');
const pino = require('pino');
const fs = require('fs');

const PORT = process.env.PORT || 3000;
const TOKEN = process.env.TOKEN || 'changeme';
const TZ = process.env.TZ_NAME || 'Europe/Istanbul';
const DATA = './data';
const STORE_FILE = `${DATA}/store.json`;
fs.mkdirSync(DATA, { recursive: true });

// ---- basit depo ----
let store = { chats: {}, messages: {} };
try { store = JSON.parse(fs.readFileSync(STORE_FILE, 'utf8')); } catch (_) {}
let dirty = false;
setInterval(() => {
  if (!dirty) return;
  dirty = false;
  const keep = Object.values(store.chats).sort((a, b) => b.ts - a.ts).slice(0, 50).map((c) => c.jid);
  for (const j of Object.keys(store.chats)) if (!keep.includes(j)) { delete store.chats[j]; delete store.messages[j]; }
  fs.writeFile(STORE_FILE, JSON.stringify(store), () => {});
}, 15000);

const fmt = (ts) => new Date(ts * 1000).toLocaleString('tr-TR', {
  timeZone: TZ, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
});

function textOf(m) {
  const x = m.message;
  if (!x) return null;
  return x.conversation || x.extendedTextMessage?.text ||
    x.ephemeralMessage?.message?.extendedTextMessage?.text ||
    x.ephemeralMessage?.message?.conversation ||
    (x.imageMessage ? '[resim] ' + (x.imageMessage.caption || '') : null) ||
    (x.audioMessage ? '[ses]' : null) ||
    (x.videoMessage ? '[video]' : null) ||
    (x.documentMessage ? '[belge]' : null) ||
    (x.stickerMessage ? '[çıkartma]' : null) || null;
}

function touchChat(jid, name, ts) {
  if (!jid || jid === 'status@broadcast') return;
  const c = store.chats[jid] || (store.chats[jid] = { jid, name: null, ts: 0, last: '' });
  if (name && (!c.name || c.name === jid.split('@')[0])) c.name = name;
  if (ts && ts > c.ts) c.ts = ts;
  dirty = true;
  return c;
}

function addMessage(m) {
  const jid = m.key?.remoteJid;
  if (!jid || jid === 'status@broadcast') return;
  const text = textOf(m);
  if (!text) return;
  const ts = Number(m.messageTimestamp) || Math.floor(Date.now() / 1000);
  const list = store.messages[jid] || (store.messages[jid] = []);
  if (list.some((x) => x.id === m.key.id)) return;
  const fromMe = !!m.key.fromMe;
  list.push({ id: m.key.id, fromMe, text, ts, name: m.pushName || null });
  list.sort((a, b) => a.ts - b.ts);
  if (list.length > 20) list.splice(0, list.length - 20);
  const c = touchChat(jid, !fromMe && !jid.endsWith('@g.us') ? m.pushName : null, ts);
  if (c) c.last = (fromMe ? 'Ben: ' : '') + text.replace(/\s+/g, ' ').slice(0, 40);
}

// ---- WhatsApp bağlantısı ----
let sock = null;
let connected = false;

async function start() {
  const { state, saveCreds } = await useMultiFileAuthState(`${DATA}/auth`);
  const { version } = await fetchLatestBaileysVersion();
  sock = makeWASocket({
    version, auth: state, logger: pino({ level: 'silent' }),
    browser: Browsers.ubuntu('Chrome'), syncFullHistory: false,
    markOnlineOnConnect: false, generateHighQualityLinkPreview: false,
    getMessage: async () => undefined,
  });
  sock.ev.on('creds.update', saveCreds);
  sock.ev.on('connection.update', ({ connection, lastDisconnect }) => {
    if (connection === 'open') { connected = true; console.log('WhatsApp bağlı'); }
    if (connection === 'close') {
      connected = false;
      const code = lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        fs.rmSync(`${DATA}/auth`, { recursive: true, force: true });
      }
      setTimeout(start, 2000);
    }
  });
  sock.ev.on('messaging-history.set', ({ chats = [], contacts = [], messages = [] }) => {
    contacts.forEach((c) => touchChat(c.id, c.name || c.notify, 0));
    chats.forEach((c) => touchChat(c.id, c.name, Number(c.conversationTimestamp) || 0));
    messages.forEach((m) => addMessage(m));
  });
  sock.ev.on('chats.upsert', (cs) => cs.forEach((c) => touchChat(c.id, c.name, Number(c.conversationTimestamp) || 0)));
  sock.ev.on('contacts.upsert', (cs) => cs.forEach((c) => touchChat(c.id, c.name || c.notify, 0)));
  sock.ev.on('messages.upsert', ({ messages }) => messages.forEach((m) => addMessage(m)));
}

// ---- HTTP API ----
const app = express();
app.use(express.json());
app.use((req, res, next) => {
  if (req.get('X-Token') !== TOKEN) return res.status(401).json({ error: 'token hatalı' });
  next();
});

app.get('/status', (req, res) =>
  res.json({ connected, registered: !!sock?.authState?.creds?.registered }));

app.post('/pair', async (req, res) => {
  const phone = String(req.body.phone || '').replace(/\D/g, '');
  if (!phone) return res.status(400).json({ error: 'numara gerekli (905xxxxxxxxx)' });
  if (sock?.authState?.creds?.registered) return res.json({ error: 'zaten bağlı' });
  try {
    await new Promise((r) => setTimeout(r, 2000));
    const code = await sock.requestPairingCode(phone);
    res.json({ code: code.match(/.{1,4}/g).join('-') });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/chats', (req, res) => {
  const chats = Object.values(store.chats)
    .filter((c) => c.last)
    .sort((a, b) => b.ts - a.ts).slice(0, 15)
    .map((c) => ({
      jid: c.jid, name: c.name || c.jid.split('@')[0],
      last: c.last, time: c.ts ? fmt(c.ts) : '',
    }));
  res.json({ chats });
});

app.get('/messages', (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 15, 20);
  const list = (store.messages[req.query.jid] || []).slice(-limit)
    .map((m) => ({ fromMe: m.fromMe, text: m.text, name: m.name, time: fmt(m.ts) }));
  res.json({ messages: list });
});

app.get('/inbox', (req, res) => {
  const all = [];
  for (const [jid, list] of Object.entries(store.messages)) {
    const c = store.chats[jid];
    const base = (c && c.name) || jid.split('@')[0];
    for (const m of list) {
      if (m.fromMe) continue;
      const name = jid.endsWith('@g.us') && m.name ? `${base} / ${m.name}` : base;
      all.push({ name, text: m.text, ts: m.ts });
    }
  }
  all.sort((a, b) => b.ts - a.ts);
  res.json({ messages: all.slice(0, 20).map((m) => ({ name: m.name, text: m.text, time: fmt(m.ts) })) });
});

app.post('/send', async (req, res) => {
  const { jid, text } = req.body;
  if (!jid || !text) return res.status(400).json({ error: 'jid ve text gerekli' });
  if (!connected) return res.status(503).json({ error: 'WhatsApp bağlı değil' });
  try {
    const sent = await sock.sendMessage(jid, { text });
    addMessage(sent);
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

start();
app.listen(PORT, '0.0.0.0', () => console.log(`Köprü ${PORT} portunda`));
