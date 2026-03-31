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

# 2.2 防火墙优化 (旁路路由核心：允许转发 + 开启伪装)
# 允许所有流量转发
sed -i 's/option forward.*REJECT/option forward\tACCEPT/g' package/network/config/firewall/files/firewall.config
# 开启 LAN 口的伪装 (MASQUERADE)，确保旁路路由流量正常回传，无需在主路由设置静态路由
sed -i '/config zone/,/option name.*lan/ { /option name.*lan/ a \	option masq\t\t1' package/network/config/firewall/files/firewall.config

# 2.3 开启多核数据包转发优化 (RPS/RFS)
echo 'for x in /sys/class/net/eth*/queues/rx-*/rps_cpus; do echo "f" > "$x"; done' >> package/base-files/files/etc/rc.local

# 3. 针对 Intel i225-V 网卡的优化
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf

# 4. 彻底重构：清理官方源码中与第三方插件冲突的部分
# 移除官方源码中的 ksmbd (内核 6.12 编译报错源)
rm -rf package/kernel/ksmbd
find package/ feeds/ -type d -name "ksmbd-server" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-app-ksmbd" -exec rm -rf {} +
find package/ feeds/ -type d -name "kmod-ksmbd" -exec rm -rf {} +

# 移除官方源码中可能与第三方源冲突的组件
find package/ feeds/ -type d -name "luci-app-samba" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-app-samba4" -exec rm -rf {} +

# 4.1 解决第三方源 (kenzo/small) 的递归依赖与缺失依赖问题
# 彻底移除导致递归依赖的软件包 (homeproxy, sing-box, momo)
find package/ feeds/ -type d -name "luci-app-homeproxy" -exec rm -rf {} +
find package/ feeds/ -type d -name "sing-box" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-app-momo" -exec rm -rf {} +
find package/ feeds/ -type d -name "momo" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-app-fchomo" -exec rm -rf {} +
find package/ feeds/ -type d -name "nikki" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-app-nikki" -exec rm -rf {} +

# 移除产生大量警告且不兼容官方源码的包
find package/ feeds/ -type d -name "luci-app-ssr-plus" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-app-mjpg-streamer" -exec rm -rf {} +
find package/ feeds/ -type d -name "onionshare-cli" -exec rm -rf {} +
find package/ feeds/ -type d -name "trojan" -exec rm -rf {} +
find package/ feeds/ -type d -name "trojan-plus" -exec rm -rf {} +
find package/ feeds/ -type d -name "luci-theme-alpha" -exec rm -rf {} +

# 4.2 修复核心插件的 LuCI 兼容性 (针对官方 v25.12 架构)
# 强制为 OpenClash 和 PassWall 添加 luci-compat 依赖
[ -f package/feeds/kenzo/luci-app-openclash/Makefile ] && sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +luci-compat/g' package/feeds/kenzo/luci-app-openclash/Makefile
[ -f package/feeds/small/luci-app-passwall/Makefile ] && sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +luci-compat/g' package/feeds/small/luci-app-passwall/Makefile

# 4.3 修复 TurboAcc 依赖问题 (官方源码可能缺少 pdnsd-alt)
find package/ feeds/ -type d -name "luci-app-turboacc" -exec sed -i 's/+pdnsd-alt//g' {}/Makefile \;

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
