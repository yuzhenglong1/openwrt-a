#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 1. 修改默认 IP (LAN IP)
sed -i 's/192.168.1.1/172.16.1.2/g' package/base-files/files/bin/config_generate

# 1.1 设置网关 (指向主路由)
sed -i '/set network.$1.netmask=$netm/a\t\t\tset network.$1.gateway='172.16.1.1'' package/base-files/files/bin/config_generate

# 1.2 设置 DNS (指向主路由)
sed -i '/set network.$1.netmask=$netm/a\t\t\tset network.$1.dns='172.16.1.1'' package/base-files/files/bin/config_generate

# 2. 修改主机名
sed -i 's/OpenWrt/Roo-Router/g' package/base-files/files/bin/config_generate

# 3. 针对 Intel i225-V 网卡的优化 (igc 驱动)
# 确保 igc 驱动被包含在内核中，并尝试开启一些性能特性
# 注意：大部分 igc 优化是在内核配置中完成的，这里可以添加一些系统级的调优参数
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv4.tcp_rmem=4096 87380 16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv4.tcp_wmem=4096 65536 16777216" >> package/base-files/files/etc/sysctl.conf

# 4. 移除不需要的默认包 (可选)
# sed -i 's/luci-app-wol//g' include/target.mk

# 5. 设置 Argon 为默认主题
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 6. 修改默认终端欢迎信息 (Banner)
echo "  _______  _______  _______ " > package/base-files/files/etc/banner
echo " |   _   ||   _   ||   _   |" >> package/base-files/files/etc/banner
echo " |.  |   ||.  |   ||.  |   |" >> package/base-files/files/etc/banner
echo " |.  |   ||.  |   ||.  |   |" >> package/base-files/files/etc/banner
echo " |:  1   ||:  1   ||:  1   |" >> package/base-files/files/etc/banner
echo " |::.. . ||::.. . ||::.. . |" >> package/base-files/files/etc/banner
echo " \_______/\_______/\_______/" >> package/base-files/files/etc/banner
echo " ---------------------------" >> package/base-files/files/etc/banner
echo "  Roo-Router Optimized OS   " >> package/base-files/files/etc/banner
echo " ---------------------------" >> package/base-files/files/etc/banner
