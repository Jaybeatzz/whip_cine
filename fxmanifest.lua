fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_cine'
author 'Based on aty_cinematic by atiysu (MIT)'
description 'whip_cine - unofficial cinematic director for WHIP servers (fork of aty_cinematic): free camera, keyframe timeline, actors, lights, ready-made moves and scenes, Rockstar Editor recording'
version '1.0.0'

dependencies {
    'oxmysql',
    'whip_core',
}

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'settings.lua',
    'shared/*.lua',
}

client_scripts {
    'client/lib/dataview.lua',
    'client/bootstrap.lua',
    'client/store.lua',
    'client/nui.lua',
    'client/camera.lua',
    'client/shake.lua',
    'client/pathviz.lua',
    'client/freecam.lua',
    'client/rigs.lua',
    'client/timeline.lua',
    'client/env.lua',
    'client/actors.lua',
    'client/lights.lua',
    'client/presets.lua',
    'client/gizmo.lua',
    'client/placer.lua',
    'client/hud.lua',
    'client/persist.lua',
    'client/input.lua',
    'client/session.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/storage.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/**/*',
    'lists/*.json',
}
