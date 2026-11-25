-- Hafif WhatsApp istemcisi (sadece Türkçe). Ağır modüller kullanılınca yüklenir.
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local function _(s) return s end
local LIMIT = 15

-- Ülke kodları (ad=kod). Türkiye en başta.
local COUNTRIES = "Türkiye=90;ABD / Kanada / Karayipler=1;Afganistan=93;Almanya=49;Andorra=376;Angola=244;"
    .. "Arjantin=54;Arnavutluk=355;Avustralya=61;Avusturya=43;Azerbaycan=994;Bahreyn=973;Bangladeş=880;"
    .. "Belarus=375;Belçika=32;Benin=229;Birleşik Arap Emirlikleri=971;Birleşik Krallık=44;Bolivya=591;"
    .. "Bosna Hersek=387;Botsvana=267;Brezilya=55;Bulgaristan=359;Burkina Faso=226;Burundi=257;Butan=975;"
    .. "Cezayir=213;Çad=235;Çekya=420;Çin=86;Danimarka=45;Doğu Timor=670;Ekvador=593;Ekvator Ginesi=240;"
    .. "El Salvador=503;Endonezya=62;Eritre=291;Ermenistan=374;Estonya=372;Etiyopya=251;Fas=212;Fiji=679;"
    .. "Fildişi Sahili=225;Filipinler=63;Filistin=970;Finlandiya=358;Fransa=33;Gabon=241;Gambiya=220;Gana=233;"
    .. "Gine=224;Gine-Bissau=245;Guatemala=502;Guyana=592;Güney Afrika=27;Güney Kore=82;Güney Sudan=211;"
    .. "Gürcistan=995;Haiti=509;Hırvatistan=385;Hindistan=91;Hollanda=31;Honduras=504;Hong Kong=852;Irak=964;"
    .. "İran=98;İrlanda=353;İspanya=34;İsrail=972;İsveç=46;İsviçre=41;İtalya=39;İzlanda=354;Japonya=81;"
    .. "Kamboçya=855;Kamerun=237;Katar=974;Kazakistan=7;Kenya=254;Kıbrıs (Rum)=357;Kırgızistan=996;"
    .. "Kolombiya=57;Kongo (Demokratik)=243;Kongo (Cumhuriyeti)=242;Kosova=383;Kosta Rika=506;Kuveyt=965;"
    .. "Kuzey Makedonya=389;Küba=53;Laos=856;Lesotho=266;Letonya=371;Liberya=231;Libya=218;Lihtenştayn=423;"
    .. "Litvanya=370;Lübnan=961;Lüksemburg=352;Macaristan=36;Madagaskar=261;Makao=853;Malavi=265;Maldivler=960;"
    .. "Malezya=60;Mali=223;Malta=356;Meksika=52;Mısır=20;Moğolistan=976;Moldova=373;Monako=377;Moritanya=222;"
    .. "Mozambik=258;Myanmar=95;Namibya=264;Nepal=977;Nijer=227;Nijerya=234;Nikaragua=505;Norveç=47;"
    .. "Orta Afrika Cumhuriyeti=236;Özbekistan=998;Pakistan=92;Panama=507;Papua Yeni Gine=675;Paraguay=595;"
    .. "Peru=51;Polonya=48;Portekiz=351;Romanya=40;Ruanda=250;Rusya=7;Senegal=221;Sırbistan=381;Sierra Leone=232;"
    .. "Singapur=65;Slovakya=421;Slovenya=386;Somali=252;Sri Lanka=94;Sudan=249;Suriye=963;Suudi Arabistan=966;"
    .. "Şili=56;Tacikistan=992;Tanzanya=255;Tayland=66;Tayvan=886;Togo=228;Tunus=216;Türkmenistan=993;"
    .. "Uganda=256;Ukrayna=380;Umman=968;Uruguay=598;Ürdün=962;Vietnam=84;Yemen=967;Yeni Zelanda=64;"
    .. "Yunanistan=30;Zambiya=260;Zimbabve=263"

-- Sunucu ayarı: config.lua dosyasından okunur (uygulama içinde ayar menüsü yok)
local function loadConfig()
    local conf = { server = "http://192.168.1.10:3000", token = "changeme" }
    local src = debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*)/[^/]*$")
    if dir then
        local ok, t = pcall(dofile, dir .. "/config.lua")
        if ok and type(t) == "table" then
            conf.server = t.server or conf.server
            conf.token = t.token or conf.token
        end
    end
    conf.server = (tostring(conf.server):gsub("%s+", ""):gsub("/+$", ""))
    return conf
end
local CONF = loadConfig()

-- Uygulama içi ayar (varsa) config.lua'nın önüne geçer
local function getServer()
    local v = G_reader_settings and G_reader_settings:readSetting("whatsapp_server")
    if type(v) == "string" and v ~= "" then return v end
    return CONF.server
end

local function getToken()
    local v = G_reader_settings and G_reader_settings:readSetting("whatsapp_token")
    if type(v) == "string" and v ~= "" then return v end
    return CONF.token
end

local WhatsApp = WidgetContainer:extend{
    name = "whatsapp",
    is_doc_only = false,
}

local function urlencode(s)
    return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

function WhatsApp:init()
    self.ui.menu:registerToMainMenu(self)
end

function WhatsApp:msg(text, timeout)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 5 })
end

-- Eski/yeni KOReader sürümleriyle uyumlu "online olunca çalıştır"
function WhatsApp:online(fn)
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr.runWhenOnline then
        NetworkMgr:runWhenOnline(fn)
    elseif NetworkMgr.isOnline and NetworkMgr:isOnline() then
        fn()
    elseif NetworkMgr.promptWifiOn then
        NetworkMgr:promptWifiOn()
    else
        fn()
    end
end

-- Döner: tablo, ya da nil + hata metni
function WhatsApp:api(method, path, body)
    local url = getServer() .. path
    local http
    if url:match("^https://") then
        local okH, h = pcall(require, "ssl.https")
        if not okH then return nil, "HTTPS desteklenmiyor, http:// adresi kullan" end
        http = h
    else
        http = require("socket.http")
    end
    local ltn12 = require("ltn12")
    local JSON = require("json")
    local okS, socketutil = pcall(require, "socketutil")

    local resp = {}
    local headers = { ["X-Token"] = getToken() }
    local source
    if body then
        local s = JSON.encode(body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#s)
        source = ltn12.source.string(s)
    end
    if okS and socketutil.set_timeout then socketutil:set_timeout(15, 40) else http.TIMEOUT = 20 end
    local ok, code = http.request{
        url = url,
        method = method,
        headers = headers,
        source = source,
        sink = ltn12.sink.table(resp),
    }
    if okS and socketutil.reset_timeout then socketutil:reset_timeout() end
    if not ok then
        return nil, _("Sunucuya bağlanılamadı") .. "\n" .. tostring(code) .. "\n" .. getServer()
    end
    local okj, data = pcall(JSON.decode, table.concat(resp))
    if not okj or type(data) ~= "table" then
        return nil, _("Sunucu geçersiz yanıt verdi") .. " (" .. tostring(code) .. ")\n" .. getServer()
    end
    if code ~= 200 then return nil, data.error or ("HTTP " .. tostring(code)) end
    return data
end

function WhatsApp:ask(title, default, cb, hint)
    local UIManager = require("ui/uimanager")
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = title,
        input = default or "",
        input_hint = hint,
        buttons = {{
            { text = _("İptal"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Tamam"), is_enter_default = true, callback = function()
                local t = dlg:getInputText()
                UIManager:close(dlg)
                cb(t)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- Ülke seç, sonra numara iste. cb(tam_numara) çağrılır (örn. 905551234567)
function WhatsApp:askNumber(cb)
    local UIManager = require("ui/uimanager")
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local menu
    local function afterCode(code)
        self:ask("+" .. code .. " " .. _("numarası (başında 0 olmadan)"), "", function(num)
            num = (num:gsub("%D", ""))
            num = (num:gsub("^0+", ""))
            if num == "" then return self:msg(_("Numara girilmedi")) end
            cb(code .. num)
        end, "5551234567")
    end
    local items = {}
    for name, code in COUNTRIES:gmatch("([^=;]+)=(%d+)") do
        items[#items + 1] = {
            text = name,
            mandatory = "+" .. code,
            callback = function()
                UIManager:close(menu)
                afterCode(code)
            end,
        }
    end
    items[#items + 1] = {
        text = _("Diğer (ülke kodunu elle yaz)"),
        callback = function()
            UIManager:close(menu)
            self:ask(_("Ülke kodu (örn. 90)"), "", function(t)
                t = (t:gsub("%D", ""))
                if t == "" then return end
                afterCode(t)
            end)
        end,
    }
    menu = Menu:new{
        title = _("Ülke seç"),
        item_table = items,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    UIManager:show(menu)
end

function WhatsApp:pair()
    self:askNumber(function(full)
        self:online(function()
            local data, err = self:api("POST", "/pair", { phone = full })
            if not data then return self:msg(err, 10) end
            if data.error then return self:msg(data.error, 8) end
            self:msg(_("Eşleştirme kodu:") .. "\n\n" .. data.code ..
                "\n\n" .. _("Telefonda WhatsApp > Bağlı cihazlar > Cihaz bağla > Telefon numarasıyla bağla"), 90)
        end)
    end)
end

function WhatsApp:showChat(jid, name)
    self:online(function()
        local data, err = self:api("GET", "/messages?limit=" .. LIMIT .. "&jid=" .. urlencode(jid))
        if not data then return self:msg(err, 10) end
        local UIManager = require("ui/uimanager")
        local TextViewer = require("ui/widget/textviewer")
        local Screen = require("device").screen
        local lines = {}
        local list = data.messages or {}
        for i = #list, 1, -1 do   -- en yeni üstte
            local m = list[i]
            local who = m.fromMe and _("Ben") or (m.name or name)
            lines[#lines + 1] = who .. " [" .. tostring(m.time or "") .. "]\n" .. tostring(m.text or "") .. "\n"
        end
        if #lines == 0 then lines[1] = _("(mesaj yok)") end
        if self.viewer then UIManager:close(self.viewer) end
        self.viewer = TextViewer:new{
            title = name,
            text = table.concat(lines, "\n"),
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            buttons_table = {{
                { text = _("Yaz"), callback = function()
                    self:ask(_("Mesaj"), "", function(text)
                        if text == "" then return end
                        local r, e = self:api("POST", "/send", { jid = jid, text = text })
                        if not r then return self:msg(e, 10) end
                        self:showChat(jid, name)
                    end)
                end },
                { text = _("Yenile"), callback = function() self:showChat(jid, name) end },
                { text = _("Kapat"), callback = function()
                    UIManager:close(self.viewer)
                    self.viewer = nil
                end },
            }},
        }
        UIManager:show(self.viewer)
    end)
end

function WhatsApp:showChats()
    self:online(function()
        local data, err = self:api("GET", "/chats")
        if not data then return self:msg(err, 10) end
        local UIManager = require("ui/uimanager")
        local Menu = require("ui/widget/menu")
        local Screen = require("device").screen
        if self.chat_menu then UIManager:close(self.chat_menu) end
        local items = {{
            text = "↻ " .. _("Yenile"),
            callback = function() self:showChats() end,
        }}
        for _i, c in ipairs(data.chats or {}) do
            items[#items + 1] = {
                text = tostring(c.name or "?") .. " - " .. tostring(c.last or ""),
                mandatory = tostring(c.time or ""),
                callback = function() self:showChat(c.jid, c.name) end,
            }
        end
        self.chat_menu = Menu:new{
            title = "WhatsApp",
            item_table = items,
            is_borderless = true,
            is_popout = false,
            covers_fullscreen = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            close_callback = function() self.chat_menu = nil end,
        }
        UIManager:show(self.chat_menu)
    end)
end

function WhatsApp:showInbox()
    self:online(function()
        local data, err = self:api("GET", "/inbox")
        if not data then return self:msg(err, 10) end
        local UIManager = require("ui/uimanager")
        local TextViewer = require("ui/widget/textviewer")
        local Screen = require("device").screen
        local lines = {}
        for _i, m in ipairs(data.messages or {}) do
            lines[#lines + 1] = tostring(m.name or "?") .. " [" .. tostring(m.time or "") .. "]\n" .. tostring(m.text or "") .. "\n"
        end
        if #lines == 0 then lines[1] = _("(gelen mesaj yok)") end
        if self.viewer then UIManager:close(self.viewer) end
        self.viewer = TextViewer:new{
            title = _("Gelen mesajlar"),
            text = table.concat(lines, "\n"),
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            buttons_table = {{
                { text = _("Yenile"), callback = function() self:showInbox() end },
                { text = _("Kapat"), callback = function()
                    if self.viewer then UIManager:close(self.viewer) end
                    self.viewer = nil
                end },
            }},
        }
        UIManager:show(self.viewer)
    end)
end

function WhatsApp:setServer()
    self:ask(_("Sunucu adresi"), getServer(), function(t)
        t = (t:gsub("%s+", ""):gsub("/+$", ""))
        if t == "" then return self:msg(_("Adres boş olamaz")) end
        if not t:match("^https?://") then t = "http://" .. t end
        G_reader_settings:saveSetting("whatsapp_server", t)
        self:msg(_("Kaydedildi:") .. "\n" .. t)
    end, "http://192.168.1.20:3000")
end

function WhatsApp:setToken()
    self:ask(_("Token"), getToken(), function(t)
        t = (t:gsub("%s+", ""))
        if t == "" then return self:msg(_("Token boş olamaz")) end
        G_reader_settings:saveSetting("whatsapp_token", t)
        self:msg(_("Kaydedildi"))
    end)
end

function WhatsApp:resetSettings()
    G_reader_settings:delSetting("whatsapp_server")
    G_reader_settings:delSetting("whatsapp_token")
    self:msg(_("Varsayılan ayarlara dönüldü") .. "\n" .. CONF.server)
end

function WhatsApp:newMessage()
    self:askNumber(function(full)
        self:showChat(full .. "@s.whatsapp.net", "+" .. full)
    end)
end

function WhatsApp:addToMainMenu(menu_items)
    menu_items.whatsapp = {
        text = "WhatsApp",
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Sohbetler"), callback = function() self:showChats() end },
            { text = _("Gelen mesajlar"), callback = function() self:showInbox() end },
            { text = _("Yeni mesaj"), callback = function() self:newMessage() end },
            { text = _("Telefonla eşleştir"), callback = function() self:pair() end },
            { text = _("Bağlantı testi"), callback = function()
                self:online(function()
                    local d, e = self:api("GET", "/status")
                    if not d then return self:msg(e, 10) end
                    self:msg(d.connected and _("Sunucu çalışıyor, WhatsApp bağlı")
                        or _("Sunucu çalışıyor, WhatsApp henüz bağlı değil (eşleştir)"))
                end)
            end },
            { text = _("Ayarlar"), sub_item_table = {
                { text = _("Sunucu adresi"), keep_menu_open = true, callback = function() self:setServer() end },
                { text = _("Token"), keep_menu_open = true, callback = function() self:setToken() end },
                { text = _("Varsayılana dön"), keep_menu_open = true, callback = function() self:resetSettings() end },
            }},
        },
    }
end

return WhatsApp
