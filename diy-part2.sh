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
# 禁用 IPv6
sed -i 's/option ipv6/option ipv6_disabled/g' package/base-files/files/etc/config/network 2>/dev/null || true
echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf

# 2.2 防火墙优化 (旁路路由核心：允许转发 + 开启伪装)
# 允许所有流量转发
sed -i 's/option forward.*REJECT/option forward\tACCEPT/g' package/network/config/firewall/files/firewall.config
# 开启 LAN 口的伪装 (MASQUERADE)，确保流量正常回传
sed -i '/option name.*lan/ a \	option masq\t\t1' package/network/config/firewall/files/firewall.config

# 2.3 开启多核数据包转发优化 (RPS/RFS)
echo 'for x in /sys/class/net/eth*/queues/rx-*/rps_cpus; do echo "f" > "$x"; done' >> package/base-files/files/etc/rc.local

# 3. 针对 Intel i225-V 网卡的优化
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf

# 4. 【终极清理】彻底切断递归依赖和冲突源
# 4.1 物理删除导致递归依赖的包 (这是解决 recursive dependency 的唯一有效手段)
# 我们必须删除第三方源中所有与代理相关的冲突包，只保留 OpenClash 和 PassWall
echo "正在执行深度物理清理，切断递归依赖链..."
# 定义必须消失的关键字
PKGS_TO_DIE=(
    "homeproxy" "momo" "fchomo" "nikki" "daed" "mihomo"
    "ssr-plus" "bypass" "v2ray-server" "v2ray-geodata"
    "open-app-filter" "smartdns"
)

for pkg in "${PKGS_TO_DIE[@]}"; do
    # 同时删除 feeds 源码和 package/feeds 中的软链接，确保 Kconfig 扫描不到它们
    find feeds/ package/feeds/ -type d -name "*$pkg*" -exec rm -rf {} +
done

# 4.2 特别处理 sing-box
# kenzo 仓库中的 sing-box 经常包含错误的依赖逻辑，导致与官方源冲突
# 我们删除第三方源的 sing-box，让系统自动回退到官方 packages 仓库中的版本
find feeds/kenzo feeds/small package/feeds/kenzo package/feeds/small -type d -name "*sing-box*" -exec rm -rf {} +

# 4.3 物理删除官方源码中报错的 ksmbd (与新内核 6.12 冲突)
rm -rf package/kernel/ksmbd
find package/ feeds/ -type d -name "*ksmbd*" -exec rm -rf {} +

# 4.4 修复核心插件兼容性 (注入 luci-compat)
# OpenWrt Main 分支必须手动补齐 luci-compat，否则插件无法运行
echo "正在注入 luci-compat 兼容性补丁..."
find package/feeds/ -name "Makefile" -exec sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base +luci-compat/g' {} +
# 针对 TurboAcc 的特殊修复
find package/feeds/ -name "luci-app-turboacc" -type d -exec sh -c 'sed -i "s/+pdnsd-alt//g" {}/Makefile' \;

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

# 7. 【关键】强制删除 tmp 目录，确保依赖关系重新扫描
rm -rf tmp
