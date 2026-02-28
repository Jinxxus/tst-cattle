fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name        'cattle_herding'
description 'Cattle Herding System - VORP Framework'
version     '1.0.0'
author      'Converted from SHVDN script.cpp'

shared_scripts {
    -- Add any shared config here if needed
}

client_scripts {
    'client.lua',
}

server_scripts {
    'server.lua',
}

dependencies {
    'vorp_core',
    'uiprompt',  -- kibook/uiprompt
}
