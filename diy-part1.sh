#!/bin/bash
# Add a feed source
# 使用更稳定的插件源组合，适配最新 OpenWrt 官方源码
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default
echo 'src-git small https://github.com/kenzok8/small' >>feeds.conf.default
