# Kindle WhatsApp (KOReader)

Kindle Paperwhite 11 + KOReader için basit WhatsApp (sadece metin) eklentisi.

```
Kindle (whatsapp.koplugin) <--HTTP--> bridge (Node + Baileys) <--> WhatsApp
```

## Uyumluluk
- Eklenti firmware'e bağlı değildir, KOReader içinde çalışır. Firmware sadece jailbreak için önemli.
- Hedef: Kindle firmware 5.15 ve üstü (11. nesil Paperwhite dahil), güncel KOReader sürümleri.
- Jailbreak (firmware'e göre): 5.16.4–5.18.x için Nosebleed/Sanctuary, 5.18.1–5.18.5 reklamlı cihazlar için AdBreak, 5.18.1'e kadar WinterBreak. Güncel yöntemler için kindlemodding.org'a bak.
- Hafif tasarım: modüller sadece kullanılınca yüklenir, listeler 15 öğeyle sınırlı, arka planda hiçbir şey çalışmaz.

## 1. Köprü (bilgisayar / Raspberry Pi / VPS)
```
cd bridge
npm install
TOKEN=gizlisifre node server.js
```
Node 18+ gerekir. Sürekli açık kalmalı (`pm2 start server.js` önerilir).

Docker ile: `cd bridge && docker build -t wa-bridge . && docker run -d --restart=always -p 3000:3000 -v $PWD/data:/app/data -e TOKEN=gizlisifre wa-bridge`

## 2. Sunucu adresini eklentiye göm
GitHub repo > Settings > Secrets and variables > Actions: `WA_SERVER` (örn. `http://192.168.1.20:3000` veya `https://alanadi.com`) ve `WA_TOKEN` (köprüdeki TOKEN) ekle. Workflow bunları `config.lua` içine yazar (varsayılan adres). İstersen uygulamada WhatsApp > Ayarlar menüsünden de değiştirebilirsin, uygulamadaki ayar `config.lua`'nın önüne geçer.
Secret eklemezsen `whatsapp.koplugin/config.lua` dosyasını elle düzenle.

## 3. Eklenti
Releases'tan `whatsapp.koplugin.zip` indir, zip'in içindeki `whatsapp.koplugin`
klasörünü Kindle'da `koreader/plugins/` içine kopyala, KOReader'ı yeniden başlat.

## 4. Kullanım
Araçlar menüsü > WhatsApp:
1. **Telefonla eşleştir**: listeden ülkeyi seç (Türkiye en üstte), numarayı başında 0 olmadan yaz, çıkan kodu telefonda
   WhatsApp > Bağlı cihazlar > Telefon numarasıyla bağla yoluyla gir.
2. **Gelen mesajlar** (tüm sohbetlerden son gelenler), **Sohbetler** veya **Yeni mesaj**.

> Gayriresmi API kullanır, hesap ban riski vardır. Sadece kendi hesabında, az kullan.
