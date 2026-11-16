-- Configuracoes administrativas: banco por padrao, arquivo como alternativa explicita.
local resource = GetCurrentResourceName()
local path = 'data/settings.json'
local backup = 'data/settings.backup.json'
local storage = { mode = GetConvar('xt-prison:settingsStorage', 'database'), writable = false }

local function decode(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, value = pcall(json.decode, raw)
    if ok and type(value) == 'table' then return value end
end

function storage.load()
    if storage.mode == 'file' then
        local raw = LoadResourceFile(resource, path)
        local value = decode(raw)
        if raw and not value then
            return nil, 'Arquivo de configuracoes invalido; preservado. Salvamento bloqueado.'
        end
        storage.writable = true
        return value
    end
    if storage.mode ~= 'database' then
        return nil, 'Modo de armazenamento invalido; use database ou file.'
    end
    local ready, err = XTPrison.load('modules.server.db').awaitReady()
    if not ready then return nil, err end
    local rows = pr_lib.database.query('SELECT data FROM xt_prison_settings WHERE id = ?', { 'global' })
    if type(rows) ~= 'table' then
        return nil, 'Banco de configuracoes indisponivel; salvamento bloqueado.'
    end
    local value = rows[1] and decode(rows[1].data)
    if rows[1] and not value then
        return nil, 'Configuracoes invalidas no banco; dados preservados.'
    end
    storage.writable = true
    return value
end

local function writeJson(encoded)
        local previous = LoadResourceFile(resource, path)
        if previous then
            if not SaveResourceFile(resource, backup, previous, #previous)
                or LoadResourceFile(resource, backup) ~= previous then
                return false, 'Falha ao criar backup; configuracoes preservadas.'
            end
        end
        local written = SaveResourceFile(resource, path, encoded, #encoded)
        if not written or LoadResourceFile(resource, path) ~= encoded then
            if previous then SaveResourceFile(resource, path, previous, #previous) end
            return false, 'Falha ao gravar configuracoes em arquivo.'
        end
        return true
end

function storage.save(value)
    if not storage.writable then return false, 'Armazenamento indisponivel; confira o console.' end
    local encoded = json.encode(value)
    if storage.mode == 'file' then return writeJson(encoded) end
    local previous = pr_lib.database.scalar('SELECT data FROM xt_prison_settings WHERE id = ?', { 'global' })
    local changed = pr_lib.database.execute(
        'INSERT INTO xt_prison_settings (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { 'global', encoded }
    )
    if changed == nil or changed == false then return false, 'Falha ao salvar no banco.' end
    local stored = pr_lib.database.scalar('SELECT data FROM xt_prison_settings WHERE id = ?', { 'global' })
    if stored ~= encoded then return false, 'Falha ao confirmar a gravacao das configuracoes.' end
    local written, err = writeJson(encoded)
    if not written then
        -- Publish neither new runtime settings nor a partial configuration save.
        if previous then
            pr_lib.database.execute('UPDATE xt_prison_settings SET data = ? WHERE id = ?', {previous,'global'})
        else
            pr_lib.database.execute('DELETE FROM xt_prison_settings WHERE id = ?', {'global'})
        end
        return false, err
    end
    return true
end

return storage
