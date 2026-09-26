#!/bin/sh
# OpenWrt initial settings via uci-defaults
# Runs on first boot

# Set LAN IP
uci set network.lan.ipaddr='10.0.0.252'
uci set network.lan.netmask='255.255.255.0'

# Set timezone
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'

# Set language
uci set luci.main.lang='zh_cn'

# Set default theme to Argon
uci set luci.main.mediaurlbase='/luci-static/argon'

# Commit changes
uci commit network
uci commit system
uci commit luci

exit 0