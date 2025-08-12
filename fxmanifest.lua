fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Leon'
description 'Player Center: Reports + Warnings + Staff Tools'
version '4.0.1'

ui_page 'html/index.html'
files { 'html/index.html' }

client_scripts {
  '@ox_lib/init.lua',
  'client.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server.lua'
}

dependencies {
  'oxmysql',
  'qb-core',
  'ox_lib'
}
