fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name        'tst-cattle'
description 'Cattle herding job for RedM with VORP framework'
version     '1.2.0'

-- uiprompt must be started before tst-cattle in server.cfg
client_scripts {
    '@uiprompt/uiprompt.lua',
    'shared/config.lua',
    'client/main.lua',
}

server_scripts {
    'shared/config.lua',
    'server/main.lua',
}
