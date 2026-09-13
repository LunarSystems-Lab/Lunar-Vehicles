-- lunar-vehicles — crash damage, handling, oil, roadside repair
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only
-- This program is free software under the GNU GPL v3. See LICENSE.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunar-vehicles'
author 'Lunar'
description 'QBCore crash damage, tyres, handling, oil'
version '1.4.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
    'client/damage.lua',
    'client/handling.lua',
    'client/oil_gauge.lua',
    'client/oil.lua',
    'client/repair.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.handling.lua',
    'server/handling.lua',
    'server/main.lua',
}

dependencies {
    'qb-core',
    'oxmysql',
}
