-- === ВСТРОЕННЫЕ УТИЛИТЫ ===
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function decodeBase64(data)
    if not data then return "" end
    data = string.gsub(data, '-', '+')
    data = string.gsub(data, '_', '/')
    local mod4 = #data % 4
    if mod4 > 0 then data = data .. string.rep('=', 4 - mod4) end
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local function urlDecode(s)
    if not s then return "" end
    s = string.gsub(s, '%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    return s
end

-- === ФУНКЦИИ ПРОВЕРКИ ===
local function safe(s)
    if not s then return "" end
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "[%c]", "")
    s = string.gsub(s, "^%s*(.-)%s*$", "%1")
    return s
end

local function clean(s, idx)
    if not s then s = "Node" end
    s = string.gsub(s, "[^a-zA-Z0-9%-%_]", "")
    if s == "" then s = "Node" end
    return s .. "_" .. idx
end

local function is_valid_method(m)
    if not m then return false end
    m = string.lower(m)
    if m == "aes-128-gcm" or m == "aes-256-gcm" or m == "chacha20-ietf-poly1305" or m == "chacha20-poly1305" or m == "2022-blake3-aes-128-gcm" or m == "2022-blake3-aes-256-gcm" or m == "none" or m == "plain" then return true end
    return false
end

local function parseQ(q)
    local r = {}
    if not q then return r end
    for k, v in string.gmatch(q, "([^&=?]+)=([^&=?]+)") do
        r[k] = urlDecode(v)
    end
    return r
end

local function getJ(s, k)
    local p = '"' .. k .. '"%s*:%s*"(.-)"'
    local v = string.match(s, p)
    if not v then
        p = '"' .. k .. '"%s*:%s*([%w%.%-]+)'
        v = string.match(s, p)
    end
    return v
end

-- === ГЕНЕРАТОРЫ ===
local function mkSS(s, n)
    local u, hp = s:match("^(.-)@(.*)")
    if not u then return nil end
    local dec = decodeBase64(u)
    local m, p = dec:match("^(.-):(.*)")
    local h, port = hp:match("^(.-):(%d+)")
    if not h or h == "" or not port or tonumber(port) == 0 or not m then return nil end
    if not is_valid_method(m) then return nil end
    if m == "chacha20-poly1305" then m = "chacha20-ietf-poly1305" end
    return string.format('{ "type": "shadowsocks", "tag": "%s", "server": "%s", "server_port": %s, "method": "%s", "password": "%s" }', safe(n), safe(h), port, safe(m), safe(p))
end

local function mkMieru(link, tag)
    local creds_host = link:match("mieru://([^?]+)")
    if not creds_host then return nil end
    local user_pass, host_port = creds_host:match("([^@]+)@(.+)")
    if not user_pass or not host_port then return nil end
    local username, password = user_pass:match("([^:]+):(.+)")
    local server, port = host_port:match("([^:]+):(%d+)")
    if not server or not port then return nil end

    return string.format('{ "type": "mieru", "tag": "%s", "server": "%s", "server_port": %s, "username": "%s", "password": "%s" }', safe(tag), safe(server), tonumber(port), safe(username), safe(password))
end

local function mkMasque(link, tag)
    local url_part = link:match("masque://([^#]+)")
    if not url_part then return nil end
    local main_part, query = url_part:match("([^?]+)%?(.*)")
    if not main_part then main_part = url_part end

    local userinfo, host_port = main_part:match("([^@]+)@(.+)")
    if not host_port then host_port = main_part end
    local server, port = host_port:match("([^:]+):(%d+)")
    if not server or not port then return nil end

    local params = {}
    if query then
        for k, v in query:gmatch("([^&=?]+)=([^&=?]+)") do params[k] = v end
    end

    local sn = params["sni"] or server
    local user_block = ""
    if userinfo then
        local user, pass = userinfo:match("([^:]+):(.+)")
        if user and pass then
            user_block = string.format(', "username": "%s", "password": "%s"', safe(user), safe(pass))
        end
    end

    return string.format('{ "type": "masque", "tag": "%s", "server": "%s", "server_port": %s%s, "tls": { "enabled": true, "server_name": "%s", "insecure": true } }', safe(tag), safe(server), tonumber(port), user_block, safe(sn))
end

local function mkVless(s, n)
    local u, rest = s:match("^(.-)@(.*)")
    if not u then return nil end
    local h, port, p_str = rest:match("^(.-):(%d+)%?(.*)")
    if not p_str then h, port = rest:match("^(.-):(%d+)"); p_str = "" end
    if not h or h == "" or not port or tonumber(port) == 0 then return nil end
    
    local p = parseQ(p_str)
    local tls = "false"; local sn = ""
    local sec = p["security"]
    if sec == "tls" or sec == "reality" then tls = "true"; sn = p["sni"] or h end
    local tr = ""
    local tt = p["type"]
    if tt == "ws" then
        tr = string.format(', "transport": { "type": "ws", "path": "%s", "headers": { "Host": "%s" } }', safe(p["path"] or "/"), safe(p["host"] or sn))
    elseif tt == "grpc" then
        tr = string.format(', "transport": { "type": "grpc", "service_name": "%s" }', safe(p["serviceName"] or "grpc"))
    elseif tt == "xhttp" or tt == "http" then
        tr = string.format(', "transport": { "type": "http", "host": [ "%s" ], "path": "%s" }', safe(p["host"] or sn), safe(p["path"] or "/"))
    end
    return string.format('{ "type": "vless", "tag": "%s", "server": "%s", "server_port": %s, "uuid": "%s", "flow": "%s", "tls": { "enabled": %s, "server_name": "%s", "insecure": true }%s }', safe(n), safe(h), port, safe(u), safe(p["flow"] or ""), tls, safe(sn), tr)
end

local function mkVmess(b64, n)
    local j = decodeBase64(b64)
    if not j or j == "" then return nil end
    local add = getJ(j, "add"); local port = getJ(j, "port")
    local id = getJ(j, "id"); local aid = getJ(j, "aid")
    local net = getJ(j, "net"); local h = getJ(j, "host")
    local path = getJ(j, "path"); local tls = getJ(j, "tls")
    local sni = getJ(j, "sni")
    if not add or add == "" or not port or tonumber(port) == 0 or not id then return nil end
    
    local tls_en = "false"; local sn = ""
    if tls == "tls" then tls_en = "true"; sn = sni or h or add end
    local tr = ""
    if net == "ws" then
        tr = string.format(', "transport": { "type": "ws", "path": "%s", "headers": { "Host": "%s" } }', safe(path or "/"), safe(h or ""))
    elseif net == "grpc" then
         tr = string.format(', "transport": { "type": "grpc", "service_name": "%s" }', safe(path or "grpc"))
    end
    return string.format('{ "type": "vmess", "tag": "%s", "server": "%s", "server_port": %s, "uuid": "%s", "alter_id": %s, "security": "auto", "tls": { "enabled": %s, "server_name": "%s", "insecure": true }%s }', safe(n), safe(add), port, safe(id), aid or 0, tls_en, safe(sn), tr)
end

local function mkTrojan(s, n)
    local pwd, rest = s:match("^(.-)@(.*)")
    if not pwd then return nil end
    local h, port, p_str = rest:match("^(.-):(%d+)%?(.*)")
    if not p_str then h, port = rest:match("^(.-):(%d+)"); p_str = "" end
    if not h or h == "" or not port or tonumber(port) == 0 then return nil end

    local p = parseQ(p_str)
    local sn = p["sni"] or h
    local tr = ""
    local tt = p["type"]
    if tt == "ws" then
        tr = string.format(', "transport": { "type": "ws", "path": "%s", "headers": { "Host": "%s" } }', safe(p["path"] or "/"), safe(p["host"] or sn))
    elseif tt == "grpc" then
        tr = string.format(', "transport": { "type": "grpc", "service_name": "%s" }', safe(p["serviceName"] or "grpc"))
    elseif tt == "xhttp" or tt == "http" then
        tr = string.format(', "transport": { "type": "http", "host": [ "%s" ], "path": "%s" }', safe(p["host"] or sn), safe(p["path"] or "/"))
    end
    return string.format('{ "type": "trojan", "tag": "%s", "server": "%s", "server_port": %s, "password": "%s", "tls": { "enabled": true, "server_name": "%s", "insecure": true }%s }', safe(n), safe(h), port, safe(pwd), safe(sn), tr)
end

local function mkHysteria2(s, n)
    local pwd, rest = s:match("^(.-)@(.*)")
    if not pwd then return nil end
    local h, port, p_str = rest:match("^(.-):(%d+)%?(.*)")
    if not p_str then h, port = rest:match("^(.-):(%d+)"); p_str = "" end
    if not h or h == "" or not port or tonumber(port) == 0 then return nil end

    local p = parseQ(p_str)
    local sn = p["sni"] or h
    return string.format('{ "type": "hysteria2", "tag": "%s", "server": "%s", "server_port": %s, "password": "%s", "tls": { "enabled": true, "server_name": "%s", "insecure": true } }', safe(n), safe(h), port, safe(pwd), safe(sn))
end

local function mkTuic(s, n)
    local up, rest = s:match("^(.-)@(.*)")
    if not up then return nil end
    local uuid, pwd = up:match("^(.-):(.*)")
    if not uuid then return nil end
    
    local h, port, p_str = rest:match("^(.-):(%d+)%?(.*)")
    if not p_str then h, port = rest:match("^(.-):(%d+)"); p_str = "" end
    if not h or h == "" or not port or tonumber(port) == 0 then return nil end

    local p = parseQ(p_str)
    local sn = p["sni"] or h
    return string.format('{ "type": "tuic", "tag": "%s", "server": "%s", "server_port": %s, "uuid": "%s", "password": "%s", "tls": { "enabled": true, "server_name": "%s", "insecure": true } }', safe(n), safe(h), port, safe(uuid), safe(pwd), safe(sn))
end

-- === MAIN (ПОТОКОВОЕ ЧТЕНИЕ - ЗАЩИТА ОТ OOM) ===
local nodes = {}
local count = 0

-- Построчное чтение предотвращает переполнение памяти роутера
for line in io.lines("subs_raw.txt") do
    line = string.gsub(line, "%s+", "")
    if line ~= "" then
        local rn = "Node"
        local lnk = line
        local hp = string.find(line, "#")
        if hp then
            lnk = string.sub(line, 1, hp - 1)
            rn = string.sub(line, hp + 1)
        end
        
        rn = urlDecode(rn)
        local un = clean(rn, count)
        
        local nd = nil
        if string.find(lnk, "^ss://") then nd = mkSS(string.sub(lnk, 6), un)
        elseif string.find(lnk, "^vless://") then nd = mkVless(string.sub(lnk, 9), un)
        elseif string.find(lnk, "^vmess://") then nd = mkVmess(string.sub(lnk, 9), un)
        elseif string.find(lnk, "^trojan://") then nd = mkTrojan(string.sub(lnk, 10), un)
        elseif string.find(lnk, "^hysteria2://") then nd = mkHysteria2(string.sub(lnk, 13), un)
        elseif string.find(lnk, "^hy2://") then nd = mkHysteria2(string.sub(lnk, 7), un)
        elseif string.find(lnk, "^tuic://") then nd = mkTuic(string.sub(lnk, 8), un)
        elseif string.find(lnk, "^mieru://") then nd = mkMieru(lnk, un)
        elseif string.find(lnk, "^masque://") then nd = mkMasque(lnk, un)
        end
        
        if nd then table.insert(nodes, nd); count = count + 1 end
    end
end

local fo = io.open("all_nodes.json", "w")
fo:write("[\n" .. table.concat(nodes, ",\n") .. "\n]")
fo:close()
print(count)