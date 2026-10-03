fx_version 'cerulean'
game 'gta5'
use_experimental_fxv2_oal 'yes'
lua54 'yes'

author 'xT Development / Forge Core'
description 'Prison integrado exclusivamente pelo pr_bridge'
repository 'https://github.com/xT-Development/xt-prison'
version '1.4.8'

shared_scripts {
    '@pr_bridge/init.lua',
    'bridge/shared.lua',
    'bridge/cache.lua',
}

dependencies {
    'pr_bridge',
}

client_scripts {
    'bridge/client/pr_bridge.lua',
    'bridge/compat/client.lua',
    'client/*.lua'
}

server_scripts {
    'bridge/server/pr_bridge.lua',
    'bridge/compat/server.lua',
    'server/*.lua'
}

files {
    'data/audioexample_sounds.dat54.rel',
    'audiodirectory/jail_sounds.awc',
    'locales/*.json',
    'configs/client.lua',
    'configs/server.lua',
    'configs/prisonbreak.lua',
    'modules/client/*.lua',
    'modules/server/*.lua',
    'modules/break_settings.lua',
    'bridge/compat/client.lua',
    'bridge/compat/resources.lua',
}

data_file 'AUDIO_WAVEPACK' 'audiodirectory'
data_file 'AUDIO_SOUNDDATA' 'data/audioexample_sounds.dat'

