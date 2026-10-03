local framework = pr_lib.activeBridges.frameworks

local db = {
    table = (framework == 'qbx' or framework == 'qb') and 'players'
        or framework == 'esx' and 'users'
        or framework == 'nd' and 'nd_characters'
        or framework == 'ox' and 'characters',
    identifier = (framework == 'qbx' or framework == 'qb') and 'citizenid'
        or framework == 'esx' and 'identifier'
        or (framework == 'nd' or framework == 'ox') and 'charid',
}

local queries = {
    {
        table = 'xt_prison',
        query = [[
            CREATE TABLE IF NOT EXISTS `xt_prison` (
            `identifier` VARCHAR(100) NOT NULL,
            `jailtime` INT(11) NOT NULL DEFAULT '0',
            `sentence` LONGTEXT NULL DEFAULT NULL,
            PRIMARY KEY (`identifier`) USING BTREE
        );
        ]]
    },
    {
        table = 'xt_prison_items',
        query = [[
            CREATE TABLE IF NOT EXISTS `xt_prison_items` (
            `owner` VARCHAR(60) NULL DEFAULT NULL COLLATE 'utf8_general_ci',
            `data` LONGTEXT NULL DEFAULT NULL COLLATE 'utf8_general_ci',
            UNIQUE INDEX `owner` (`owner`) USING BTREE
        );
        ]]
    },
    {
        table = 'xt_prison_settings',
        query = [[
            CREATE TABLE IF NOT EXISTS xt_prison_settings (
            id VARCHAR(50) NOT NULL,
            data LONGTEXT NOT NULL,
            updated_at TIMESTAMP NOT NULL
                DEFAULT CURRENT_TIMESTAMP
                ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        );
        ]]
    }
}


local ready, failure = false, nil
local function checked(query, parameters)
    local result = pr_lib.database.query(query, parameters or {})
    if result == nil or result == false then error('Falha no banco: ' .. query:sub(1, 100)) end
    return result
end

local function initialize()
        for x = 1, #queries do
            checked(queries[x].query)
            local rows = checked('SELECT COUNT(*) AS count FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { queries[x].table })
            if tonumber(rows[1] and rows[1].count) ~= 1 then error('Tabela indisponivel: ' .. queries[x].table) end
            XTPrison.log('info', ('Initializing Table: %s'):format(queries[x].table))
        end

        local sentenceColumn = checked("SELECT COUNT(COLUMN_NAME) AS count FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'xt_prison' AND COLUMN_NAME = 'sentence'")
        if tonumber(sentenceColumn and sentenceColumn[1] and sentenceColumn[1].count) ~= 1 then
            checked('ALTER TABLE xt_prison ADD COLUMN sentence LONGTEXT NULL DEFAULT NULL AFTER jailtime')
            XTPrison.log('info', 'Coluna de dados da pena adicionada à tabela xt_prison.')
        end

        if not db.table or not db.identifier then return end

        local convertNeeded = checked(("SELECT COUNT(COLUMN_NAME) AS count FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '%s' AND COLUMN_NAME = 'jailtime'"):format(db.table))
        if not convertNeeded or tonumber(convertNeeded[1] and convertNeeded[1].count) ~= 1 then return end

        local rows = checked(('SELECT `%s`, `jailtime` FROM `%s`'):format(db.identifier, db.table))
        for _, row in ipairs(rows) do
            checked('INSERT IGNORE INTO xt_prison (identifier, jailtime) VALUES (?, ?)', {
                row[db.identifier], row.jailtime
            })
        end

        XTPrison.log('info', 'Importacao legada concluida; coluna original preservada, penas existentes nao sobrescritas.')
end

CreateThread(function()
    pr_lib.database.ready(function()
        local ok, err = pcall(initialize)
        if ok then ready = true else
            failure = tostring(err)
            XTPrison.log('error', 'Inicializacao do banco bloqueada: ' .. failure)
        end
    end)
end)

return {
    awaitReady = function()
        local deadline = GetGameTimer() + 15000
        while not ready and not failure and GetGameTimer() < deadline do Wait(50) end
        return ready, failure or (not ready and 'Banco ainda nao inicializado; tente novamente.') or nil
    end,
    UPDATE_JAILTIME = 'INSERT INTO xt_prison (identifier, jailtime, sentence) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE jailtime = VALUES(jailtime), sentence = VALUES(sentence)',
    LOAD_JAILTIME = 'SELECT `jailtime`, `sentence` FROM xt_prison WHERE `identifier` = ?',

    GET_ITEMS = 'SELECT data FROM xt_prison_items WHERE owner = ?',
    CONFISCATE_ITEMS = 'INSERT INTO xt_prison_items (owner, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
    CLEAR_CONFISCATED_ITEMS = 'DELETE FROM xt_prison_items WHERE owner = ?'
}
