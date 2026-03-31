#!/bin/bash

# ========================================================
# Roo-Router 一键配置生成脚本 (v2.0 - 修复权限与依赖冲突)
# 功能：自动创建 GitHub Actions 编译 OpenWrt 所需的所有文件
# 优化目标：X86_64, Intel i225-V, Argon 主题美化, 双代理集成
# ========================================================

echo "正在初始化 OpenWrt 编译配置文件..."

# 1. 创建 GitHub Actions 工作流目录
mkdir -p .github/workflows

# 2. 生成 build-openwrt.yml
cat <<'EOF' > .github/workflows/build-openwrt.yml
name: Build OpenWrt

on:
  repository_dispatch:
  workflow_dispatch:

env:
  REPO_URL: https://github.com/openwrt/openwrt
  REPO_BRANCH: v25.12.2
  FEEDS_CONF: feeds.conf.default
  CONFIG_FILE: .config
  DIY_P1_SH: diy-part1.sh
  DIY_P2_SH: diy-part2.sh
  UPLOAD_FIRMWARE: true
  UPLOAD_RELEASE: true
  TZ: Asia/Shanghai
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:
  build:
    runs-on: ubuntu-22.04
    permissions:
      contents: write

    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Initialization environment
      env:
        DEBIAN_FRONTEND: noninteractive
      run: |
        sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc
        sudo -E apt-get -qq update
        sudo -E apt-get -qq install $(curl -fsSL https://is.gd/depends_ubuntu_2204)
        sudo -E apt-get -qq autoremove --purge
        sudo -E apt-get -qq clean
        sudo timedatectl set-timezone "$TZ"
        sudo mkdir -p /workdir
        sudo chown $USER:$GROUPS /workdir

    - name: Clone source code
      working-directory: /workdir
      run: |
        df -hT $PWD
        git clone $REPO_URL -b $REPO_BRANCH openwrt
        ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt

    - name: Load custom feeds
      run: |
        [ -e $FEEDS_CONF ] && cp $FEEDS_CONF openwrt/feeds.conf.default
        chmod +x $DIY_P1_SH
        cd openwrt
        $GITHUB_WORKSPACE/$DIY_P1_SH

    - name: Update feeds
      run: cd openwrt && ./scripts/feeds update -a

    - name: Install feeds
      run: cd openwrt && ./scripts/feeds install -a

    - name: Load custom configuration
      run: |
        [ -e $CONFIG_FILE ] && cp $CONFIG_FILE openwrt/.config
        chmod +x $DIY_P2_SH
        cd openwrt
        $GITHUB_WORKSPACE/$DIY_P2_SH

    - name: Download package
      id: package
      run: |
        cd openwrt
        make defconfig
        make download -j8
        find dl -size -1024c -exec ls -l {} \;
        find dl -size -1024c -exec rm -f {} \;

    - name: Compile the firmware
      id: compile
      run: |
        cd openwrt
        echo -e "$(nproc) thread compile"
        make -j$(nproc) || make -j1 || make -j1 V=s
        echo "status=success" >> $GITHUB_OUTPUT

    - name: Organize files
      id: organize
      if: env.UPLOAD_FIRMWARE == 'true' && !cancelled()
      run: |
        cd openwrt/bin/targets/*/*
        rm -rf packages
        echo "FIRMWARE=$PWD" >> $GITHUB_ENV
        echo "status=success" >> $GITHUB_OUTPUT

    - name: Upload firmware directory
      uses: actions/upload-artifact@v4
      if: steps.organize.outputs.status == 'success' && !cancelled()
      with:
        name: OpenWrt_firmware
        path: ${{ env.FIRMWARE }}

    - name: Upload firmware to release
      uses: softprops/action-gh-release@v2
      if: steps.organize.outputs.status == 'success' && !cancelled()
      with:
        tag_name: OpenWrt_$(date +"%Y.%m.%d-%H%M")
        files: ${{ env.FIRMWARE }}/*
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF

# 3. 生成 diy-part1.sh
cat <<'EOF' > diy-part1.sh
#!/bin/bash
# 添加插件源
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default
echo 'src-git small https://github.com/kenzok8/small' >>feeds.conf.default
EOF

# 4. 生成 diy-part2.sh
cat <<'EOF' > diy-part2.sh
#!/bin/bash
# 1. 修改默认 IP (LAN IP)
sed -i 's/192.168.1.1/172.16.1.2/g' package/base-files/files/bin/config_generate

# 1.1 设置网关与 DNS (指向主路由)
sed -i "s/set network.\$1.netmask=\$netm/set network.\$1.netmask=\$netm\n\t\t\tset network.\$1.gateway='172.16.1.1'\n\t\t\tset network.\$1.dns='172.16.1.1'/g" package/base-files/files/bin/config_generate

# 1.2 旁路路由优化 (禁用 DHCP/IPv6)
sed -i 's/set network.$1.proto=static/set network.$1.proto=static\n\t\t\tset network.$1.dhcpv6=disabled\n\t\t\tset network.$1.ra=disabled/g' package/base-files/files/bin/config_generate
echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf

# 2. 修改主机名
sed -i 's/OpenWrt/Roo-Router/g' package/base-files/files/bin/config_generate

# 2.1 防火墙优化 (允许转发)
sed -i 's/option forward\tREJECT/option forward\tACCEPT/g' package/network/config/firewall/files/firewall.config

# 3. 针对 Intel i225-V 网卡的优化
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf

# 4. 移除冲突包与修复依赖警告
# 移除可能导致编译失败的重复或冲突包
find package/ -type d -name "luci-app-samba" | xargs rm -rf
find package/ -type d -name "luci-app-samba4" | xargs rm -rf
find package/ -type d -name "ksmbd-server" | xargs rm -rf
find package/ -type d -name "luci-app-ksmbd" | xargs rm -rf

# 4.1 修复依赖缺失警告 (针对 kenzo 插件源中的 Lean 系插件)
find package/feeds/kenzo/ -type d -name "autocore" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "autosamba" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "ipv6-helper" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "luci-app-cpufreq" | xargs rm -rf

# 4.2 修复 Kconfig 递归依赖错误
find package/feeds/kenzo/ -type d -name "luci-app-fchomo" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "nikki" | xargs rm -rf
find package/feeds/kenzo/ -type d -name "luci-app-nikki" | xargs rm -rf

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
EOF

# 5. 生成 .config
cat <<'EOF' > .config
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y

# 基础系统设置
CONFIG_TARGET_KERNEL_PARTSIZE=64
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y

# 针对 Intel i225-V (igc 驱动) 的支持
CONFIG_PACKAGE_kmod-igc=y
CONFIG_PACKAGE_kmod-mii=y

# 针对 X86 性能优化
CONFIG_TARGET_OPTIONS=y
CONFIG_TARGET_OPTIMIZATION="-O2 -pipe -march=x86-64-v2"
CONFIG_X86_64_AESNI=y

# 常用 LuCI 插件集成
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-app-access-control=y
CONFIG_PACKAGE_luci-app-arpbind=y
CONFIG_PACKAGE_luci-app-autoreboot=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-filetransfer=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-app-flowoffload=y
CONFIG_PACKAGE_luci-app-nlbwmon=y
CONFIG_PACKAGE_luci-app-ramfree=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOAD=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_BBR_CCA=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-app-vsftpd=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-app-xlnetacc=y
CONFIG_PACKAGE_luci-app-zerotier=y
CONFIG_PACKAGE_luci-app-sqm=y

# Docker 支持
CONFIG_PACKAGE_luci-app-docker=y
CONFIG_PACKAGE_docker-ce=y

# 界面美化
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y

# 语言设置
CONFIG_LUCI_LANG_zh_Hans=y

# OpenClash & MosDNS & AdGuardHome
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-mosdns=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_irqbalance=y
CONFIG_PACKAGE_ethtool=y

# PassWall (作为 OpenClash 的备选方案)
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=y
EOF

chmod +x diy-part1.sh diy-part2.sh
echo "--------------------------------------------------"
echo "所有修复已应用！"
echo "1. 请将这些文件上传到您的 GitHub 仓库。"
echo "2. 在 GitHub Actions 中运行 'Build OpenWrt'。"
echo "3. 权限问题已修复，编译完成后将自动创建 Release。"
echo "--------------------------------------------------"
