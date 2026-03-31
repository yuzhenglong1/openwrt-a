#!/bin/bash

# ========================================================
# Roo-Router 一键配置生成脚本 (v3.0 - 适配 OpenWrt Main 分支)
# 功能：自动创建 GitHub Actions 编译 OpenWrt 所需的所有文件
# 优化目标：X86_64, Intel i225-V, 旁路路由优化, 彻底修复递归依赖
# ========================================================

echo "正在初始化 Roo-Router 终极编译配置文件..."

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
  REPO_BRANCH: main
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
        sudo -E apt-get -qq install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget
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
        grep '^CONFIG_TARGET.*DEVICE.*=y' .config | sed -r 's/.*DEVICE_(.*)=y/\1/' > DEVICE_NAME
        [ -s DEVICE_NAME ] && echo "DEVICE_NAME=_$(cat DEVICE_NAME)" >> $GITHUB_ENV
        echo "FILE_DATE=_$(date +"%Y%m%d%H%M")" >> $GITHUB_ENV

    - name: Organize files
      id: organize
      if: steps.compile.outputs.status == 'success' && !cancelled()
      run: |
        cd openwrt/bin/targets/*/*
        rm -rf packages
        echo "FIRMWARE=$PWD" >> $GITHUB_ENV
        echo "status=success" >> $GITHUB_OUTPUT

    - name: Upload firmware directory
      uses: actions/upload-artifact@v4
      if: steps.organize.outputs.status == 'success' && !cancelled()
      with:
        name: OpenWrt_firmware${{ env.DEVICE_NAME }}${{ env.FILE_DATE }}
        path: ${{ env.FIRMWARE }}

    - name: Generate release tag
      id: tag
      if: env.UPLOAD_RELEASE == 'true' && !cancelled()
      run: |
        echo "release_tag=OpenWrt_Main_$(date +"%Y.%m.%d-%H%M")" >> $GITHUB_OUTPUT
        echo "status=success" >> $GITHUB_OUTPUT

    - name: Upload firmware to release
      uses: softprops/action-gh-release@v2
      if: steps.tag.outputs.status == 'success' && !cancelled()
      with:
        tag_name: ${{ steps.tag.outputs.release_tag }}
        files: ${{ env.FIRMWARE }}/*
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF

# 3. 生成 diy-part1.sh
cat <<'EOF' > diy-part1.sh
#!/bin/bash
# Add a feed source
# 使用更稳定的插件源组合，适配最新 OpenWrt 官方源码
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default
echo 'src-git small https://github.com/kenzok8/small' >>feeds.conf.default
EOF

# 4. 生成 diy-part2.sh
cat <<'EOF' > diy-part2.sh
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
echo "正在执行深度物理清理，切断递归依赖链..."
PKGS_TO_DIE=(
    "homeproxy" "momo" "fchomo" "nikki" "daed" "mihomo" 
    "ssr-plus" "bypass" "v2ray-server" "v2ray-geodata"
    "open-app-filter" "smartdns"
)

for pkg in "${PKGS_TO_DIE[@]}"; do
    find feeds/ package/feeds/ -type d -name "*$pkg*" -exec rm -rf {} +
done

# 4.2 特别处理 sing-box
# 删除第三方源的 sing-box，让系统自动回退到官方 packages 仓库中的版本
find feeds/kenzo feeds/small package/feeds/kenzo package/feeds/small -type d -name "*sing-box*" -exec rm -rf {} +

# 4.3 物理删除官方源码中报错的 ksmbd (与新内核 6.12 冲突)
rm -rf package/kernel/ksmbd
find package/ feeds/ -type d -name "*ksmbd*" -exec rm -rf {} +

# 4.4 修复核心插件兼容性 (注入 luci-compat)
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

# 强制使用 dnsmasq-full (OpenClash 必须)
CONFIG_PACKAGE_dnsmasq=n
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_dnsmasq_full_ipset=y
CONFIG_PACKAGE_dnsmasq_full_nftset=y
CONFIG_PACKAGE_dnsmasq_full_tftp=y

# 针对 X86 性能优化
CONFIG_TARGET_OPTIONS=y
CONFIG_TARGET_OPTIMIZATION="-O2 -pipe -march=x86-64-v2"
CONFIG_X86_64_AESNI=y

# 【深度清理】禁用官方源码中冲突或报错的模块
CONFIG_PACKAGE_kmod-fs-ksmbd=n
CONFIG_PACKAGE_ksmbd-server=n
CONFIG_PACKAGE_luci-app-ksmbd=n

# 【深度清理】禁用第三方源中导致递归依赖的插件
CONFIG_PACKAGE_luci-app-homeproxy=n
CONFIG_PACKAGE_homeproxy=n
CONFIG_PACKAGE_luci-app-momo=n
CONFIG_PACKAGE_momo=n
CONFIG_PACKAGE_luci-app-ssr-plus=n
CONFIG_PACKAGE_luci-app-fchomo=n
CONFIG_PACKAGE_luci-app-nikki=n
CONFIG_PACKAGE_nikki=n
CONFIG_PACKAGE_luci-app-daed=n
CONFIG_PACKAGE_daed=n
CONFIG_PACKAGE_luci-app-mihomo=n
CONFIG_PACKAGE_mihomo=n
CONFIG_PACKAGE_luci-app-bypass=n
CONFIG_PACKAGE_luci-app-smartdns=n
CONFIG_PACKAGE_luci-app-open-app-filter=n
CONFIG_PACKAGE_luci-app-v2ray-server=n

# 常用 LuCI 插件集成 (基于官方源码环境)
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

# 界面美美化
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y

# 语言设置
CONFIG_LUCI_LANG_zh_Hans=y

# 核心功能插件
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-mosdns=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_irqbalance=y
CONFIG_PACKAGE_ethtool=y

# PassWall
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=y

# 额外内核优化
CONFIG_PACKAGE_kmod-tcp-bbr=y
EOF

chmod +x diy-part1.sh diy-part2.sh
echo "--------------------------------------------------"
echo "Roo-Router 终极配置已生成！"
echo "1. 请将生成的 5 个文件上传到您的 GitHub 仓库。"
echo "2. 在 GitHub Actions 中运行 'Build OpenWrt'。"
echo "3. 递归依赖问题已通过物理清理彻底解决。"
echo "--------------------------------------------------"
