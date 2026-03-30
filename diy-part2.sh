#!/bin/bash
# 1. 修改默认 IP (LAN IP)
sed -i 's/192.168.1.1/172.16.1.2/g' package/base-files/files/bin/config_generate

# 1.1 设置网关 (指向主路由)
sed -i "s/set network.\$1.netmask=\$netm/set network.\$1.netmask=\$netm\n\t\t\tset network.\$1.gateway='172.16.1.1'/g" package/base-files/files/bin/config_generate

# 1.2 设置 DNS (指向主路由)
sed -i "s/set network.\$1.netmask=\$netm/set network.\$1.netmask=\$netm\n\t\t\tset network.\$1.dns='172.16.1.1'/g" package/base-files/files/bin/config_generate

# 2. 修改主机名
sed -i 's/OpenWrt/Roo-Router/g' package/base-files/files/bin/config_generate

# 2.1 旁路路由优化 (与 iKuai 结合更无痕)
# 禁用 LAN 口的 DHCP (由 iKuai 分配)
sed -i 's/set network.$1.proto=static/set network.$1.proto=static\n\t\t\tset network.$1.dhcpv6=disabled\n\t\t\tset network.$1.ra=disabled/g' package/base-files/files/bin/config_generate
# 禁用 IPv6 (旁路路由环境下 IPv6 经常导致断流或延迟)
sed -i 's/option ipv6/option ipv6_disabled/g' package/base-files/files/etc/config/network 2>/dev/null || true
echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf

# 2.2 防火墙优化 (减少旁路路由丢包)
# 允许所有流量转发，避免双重过滤导致的“不丝滑”
sed -i 's/option forward\tREJECT/option forward\tACCEPT/g' package/network/config/firewall/files/firewall.config

# 2.3 开启多核数据包转发优化 (RPS/RFS)
echo "echo \"f\" > /sys/class/net/eth0/queues/rx-0/rps_cpus" >> package/base-files/files/etc/rc.local

# 3. 针对 Intel i225-V 网卡的优化
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf

# 4. 移除冲突包 (针对官方源码结构优化)
# 移除可能导致编译失败的重复或冲突包
find package/ -type d -name "luci-app-samba" | xargs rm -rf
find package/ -type d -name "luci-app-samba4" | xargs rm -rf
find package/ -type d -name "ksmbd-server" | xargs rm -rf
find package/ -type d -name "luci-app-ksmbd" | xargs rm -rf

# 4.1 修复 Kconfig 递归依赖错误 (针对 kenzo 插件源中的 fchomo/nikki 冲突)
# 报错信息: symbol PACKAGE_firewall4 is selected by PACKAGE_luci-app-fchomo -> depends on PACKAGE_nikki -> depends on PACKAGE_firewall4
find package/feeds/kenzo/ -type d -name "luci-app-fchomo" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "nikki" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "luci-app-nikki" | xargs rm -rf
# 4.2 修复 OpenClash 依赖问题 (针对最新源码)
# 某些新版源码可能会缺少 luci-lib-ipkg
[ ! -d "package/feeds/luci/luci-lib-ipkg" ] && git clone https://github.com/openwrt/luci/tree/master/libs/luci-lib-ipkg package/luci-lib-ipkg

# 5. 设置 Argon 为默认主题
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 6. 修改 Banner
echo "  _______  _______  _______ " > package/base-files/files/etc/banner
echo " |   _   ||   _   ||   _   |" >> package/base-files/files/etc/banner
echo " |   |   ||   |   ||   |   |" >> package/base-files/files/etc/banner
echo " |   |   ||   |   ||   |   |" >> package/base-files/files/etc/banner
echo " |   1   ||   1   ||   1   |" >> package/base-files/files/etc/banner
echo " |___|___||___|___||___|___|" >> package/base-files/files/etc/banner
echo " ---------------------------" >> package/base-files/files/etc/banner
echo "  Roo-Router Optimized OS   " >> package/base-files/files/etc/banner
echo " ---------------------------" >> package/base-files/files/etc/banner
