fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name        'vorp_cattle_herding'
description 'Cattle herding job for RedM with VORP framework'
author      'Converted from open-source RDR2 C++ script'
version     '1.0.0'

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

shared_scripts {
    'shared/config.lua',
}
