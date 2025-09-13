#!/bin/bash
# 该脚本为对相应 Ubuntu 版本的 gcc 编译环境的封装
# 目前支持 Ubuntu 16.04 18.04 20.04 22.04
# 需要预先安装 docker
set -euo pipefail
VALID_UBUNTU_VERSIONS=("16.04" "18.04" "20.04" "22.04" "24.04")

help() {
    echo "该build脚本用于构建不同版本的GCC编译环境的Docker镜像"
    echo "用法: $0 [Ubuntu版本]"
    echo "例如: $0 20.04"
    echo "当前支持版本: ${VALID_UBUNTU_VERSIONS[*]}"
    exit 1
}

#如果什么都没输入,就触发 help
#如果输入了,就不触发 help
if [ $# -lt 1 ]; then
    help
fi


UBUNTU_VERSION="${1}"


if [[ ! " ${VALID_UBUNTU_VERSIONS[*]} " =~ " ${UBUNTU_VERSION} " ]]; then
    echo "错误: 不支持的 Ubuntu 版本 '${UBUNTU_VERSION}'"
    echo "当前支持的版本: ${VALID_UBUNTU_VERSIONS[*]}"
    exit 1
fi



IMAGE_NAME="gcc-ubuntu:${UBUNTU_VERSION}"
mkdir ./temp_build_dir 2>/dev/null || true
cd ./temp_build_dir || exit 1
# 创建 Dockerfile
touch ./Dockerfile # 确保 Dockerfile 存在
chmod 644 ./Dockerfile
echo "# 使用 Ubuntu 作为基础镜像
FROM ubuntu:${UBUNTU_VERSION}

# 设置非交互模式，避免提示输入
ENV DEBIAN_FRONTEND=noninteractive

# 更新包管理器并安装 GCC
RUN apt-get update && \
    apt-get install -y gcc g++ make && \
    apt-get clean

# 设置工作目录
WORKDIR /app

# 容器启动时的默认命令
CMD [ "bash" ]" > ./Dockerfile

echo "正在构建 Docker 镜像 ${IMAGE_NAME} ... (这里要求权限等级支持运行docker)"
if docker build -t "${IMAGE_NAME}" . ; then
    echo "Docker 镜像 ${IMAGE_NAME} 构建成功!"
else
    echo "错误: Docker 镜像构建失败!"
fi
cd ..
rm -rrf ./temp_build_dir
