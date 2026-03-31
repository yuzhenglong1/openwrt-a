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
# 自动为所有以太网卡开启 RPS，提升多核性能
echo 'for x in /sys/class/net/eth*/queues/rx-*/rps_cpus; do echo "f" > "$x"; done' >> package/base-files/files/etc/rc.local

# 3. 针对 Intel i225-V 网卡的优化
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf

# 4. 移除冲突包 (针对官方源码结构优化)
# 彻底移除 ksmbd 相关包，避免内核 6.12 编译失败
find package/ feeds/ -type d -name "ksmbd-server" | xargs rm -rf
find package/ feeds/ -type d -name "luci-app-ksmbd" | xargs rm -rf
find package/ feeds/ -type d -name "kmod-ksmbd" | xargs rm -rf
rm -rf package/kernel/ksmbd

# 移除重复的 samba 包，统一使用 samba4
find package/ feeds/ -type d -name "luci-app-samba" | xargs rm -rf

# 4.1 修复依赖缺失警告 (针对 kenzo 插件源中的 Lean 系插件)
# 这些插件在官方源码上缺少 bc, pciutils 等依赖，且容易导致编译失败
find package/ feeds/ -type d -name "autocore" | xargs rm -rf
find package/ feeds/ -type d -name "autosamba" | xargs rm -rf
find package/ feeds/ -type d -name "ipv6-helper" | xargs rm -rf
find package/ feeds/ -type d -name "luci-app-cpufreq" | xargs rm -rf
find package/ feeds/ -type d -name "fogvdn" | xargs rm -rf
find package/ feeds/ -type d -name "luci-app-fogvdn" | xargs rm -rf
find package/ feeds/ -type d -name "pcat-manager" | xargs rm -rf
find package/ feeds/ -type d -name "luci-app-mtwifi" | xargs rm -rf
find package/ feeds/ -type d -name "ddns-scripts_aliyun" | xargs rm -rf
find package/ feeds/ -type d -name "ddns-scripts_dnspod" | xargs rm -rf
find package/ feeds/ -type d -name "luci-theme-alpha" | xargs rm -rf

# 4.2 修复 Kconfig 递归依赖错误 (针对 kenzo 插件源中的 fchomo/nikki 冲突)
find package/ feeds/ -type d -name "luci-app-fchomo" | xargs rm -rf
find package/ feeds/ -type d -name "nikki" | xargs rm -rf
find package/ feeds/ -type d -name "luci-app-nikki" | xargs rm -rf

# 4.3 修复 OpenClash 依赖问题 (针对最新源码)
# 确保 luci-compat 存在，这是很多旧插件运行的基础
# 官方 v25.12 源码中 luci-lib-ipkg 可能已整合或更名，通过 luci-compat 兼容
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +luci-compat/g' package/feeds/kenzo/luci-app-openclash/Makefile 2>/dev/null || true

# 4.4 修复 PassWall 依赖问题 (针对官方源码 v25.12)
# 官方源码可能缺少某些旧版依赖，确保 luci-compat 存在
sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +luci-compat/g' package/feeds/small/luci-app-passwall/Makefile 2>/dev/null || true

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
