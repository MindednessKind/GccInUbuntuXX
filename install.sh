#!/bin/bash

set -e
set -o pipefail

cat << EOF
环境搭建脚本, 运行即自动搭建相应环境
按任意键继续...
EOF
read -n 1 -s


echo " 获取sudo权限"
sudo -v

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y -qq
if ! command -v docker >/dev/null 2>&1; then
  echo "错误: 未找到 docker 命令"
  exit 1
fi
sudo systemctl start docker
sudo systemctl enable docker


sudo apt install patchelf -y -qq
if ! command -v patchelf >/dev/null 2>&1; then
  echo "错误: 未找到 patchelf 命令"
  exit 1
fi

#将cgcc.sh 复制到 /usr/local/bin
sudo cp ./cgcc.sh /usr/local/bin/cgcc
sudo chmod +x /usr/local/bin/cgcc