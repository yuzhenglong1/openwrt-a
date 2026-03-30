#!/bin/bash

# ========================================================
# Roo-Router 一键配置生成脚本
# 功能：自动创建 GitHub Actions 编译 OpenWrt 所需的所有文件
# 优化目标：X86_64, Intel i225-V, Argon 主题美化
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
    inputs:
      ssh:
        description: 'SSH connection to Actions'
        required: false
        default: 'false'

env:
  REPO_URL: https://github.com/openwrt/openwrt
  REPO_BRANCH: v25.12.2
  FEEDS_CONF: feeds.conf.default
  CONFIG_FILE: .config
  DIY_P1_SH: diy-part1.sh
  DIY_P2_SH: diy-part2.sh
  UPLOAD_BIN_DIR: false
  UPLOAD_FIRMWARE: true
  UPLOAD_RELEASE: true
  TZ: Asia/Shanghai
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:
  build:
    runs-on: ubuntu-22.04

    steps:
    - name: Checkout
      uses: actions/checkout@main

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
        [ -e files ] && mv files openwrt/files
        [ -e $CONFIG_FILE ] && cp $CONFIG_FILE openwrt/.config
        chmod +x $DIY_P2_SH
        cd openwrt
        $GITHUB_WORKSPACE/$DIY_P2_SH

    - name: SSH connection to Actions
      uses: P3TERX/ssh2actions@main
      if: (github.event.inputs.ssh == 'true' && github.event.inputs.ssh  != 'false') || contains(github.event.action, 'ssh')

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
      uses: actions/upload-artifact@main
      if: steps.organize.outputs.status == 'success' && !cancelled()
      with:
        name: OpenWrt_firmware
        path: ${{ env.FIRMWARE }}

    - name: Upload firmware to release
      uses: softprops/action-gh-release@v1
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
# 添加额外的插件源 (使用兼容 23.05 的源)
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default
echo 'src-git small https://github.com/kenzok8/small' >>feeds.conf.default
EOF

# 4. 生成 diy-part2.sh (含 i225-V 优化与主题美化)
cat <<'EOF' > diy-part2.sh
#!/bin/bash
# 移除冲突和报错包
find package/ -type d -name "luci-app-samba" | xargs rm -rf
find package/ -type d -name "ksmbd-server" | xargs rm -rf
# 1. 修改默认 IP (LAN IP)
sed -i 's/192.168.1.1/172.16.1.2/g' package/base-files/files/bin/config_generate
# 1.1 设置网关 (指向主路由)
sed -i "/set network.\$1.netmask=\$netm/a\t\t\tset network.\$1.gateway='172.16.1.1'" package/base-files/files/bin/config_generate
# 1.2 设置 DNS (指向主路由)
sed -i "/set network.\$1.netmask=\$netm/a\t\t\tset network.\$1.dns='172.16.1.1'" package/base-files/files/bin/config_generate
# 1.3 旁路路由优化 (禁用 DHCP/IPv6)
sed -i 's/set network.$1.proto=static/set network.$1.proto=static\n\t\t\tset network.$1.dhcpv6=disabled\n\t\t\tset network.$1.ra=disabled/g' package/base-files/files/bin/config_generate
echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
# 2. 修改主机名
sed -i 's/OpenWrt/Roo-Router/g' package/base-files/files/bin/config_generate
# 2.1 防火墙优化 (允许转发)
sed -i 's/option forward\tREJECT/option forward\tACCEPT/g' package/network/config/firewall/files/firewall.config
# 3. 设置 Argon 为默认主题
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
# 4. 网络优化 (针对 i225-V)
echo "net.core.rmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> package/base-files/files/etc/sysctl.conf
# 5. 修改 Banner
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
CONFIG_TARGET_KERNEL_PARTSIZE=64
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_PACKAGE_kmod-igc=y
CONFIG_PACKAGE_kmod-mii=y
CONFIG_TARGET_OPTIONS=y
CONFIG_TARGET_OPTIMIZATION="-O2 -pipe -march=x86-64-v2"
CONFIG_X86_64_AESNI=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOAD=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_BBR_CCA=y
# CONFIG_PACKAGE_ksmbd-server is not set
# CONFIG_PACKAGE_luci-app-ksmbd is not set
CONFIG_PACKAGE_luci-app-docker=y
CONFIG_PACKAGE_docker-ce=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-mosdns=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_luci-app-sqm=y
EOF

chmod +x diy-part1.sh diy-part2.sh
echo "--------------------------------------------------"
echo "所有文件已生成！"
echo "1. 请将这些文件上传到您的 GitHub 仓库。"
echo "2. 在 GitHub Actions 中运行 'Build OpenWrt'。"
echo "3. 编译完成后，在 Releases 页面下载以 '-combined-efi.img.gz' 结尾的文件。"
echo "--------------------------------------------------"
