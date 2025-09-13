#!/bin/bash
# build.sh
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "错误: 请指定要编译的 C 文件路径（包含 .c 后缀）"
  echo "用法: $0 <路径/文件名.c> [Ubuntu版本]"
  echo "示例: $0 src/lab/test.c 20.04"
  exit 1
fi

C_FILE="$1"
UBUNTU_VERSION="16.04"

# 允许的 Ubuntu 版本
VALID_UBUNTU_VERSIONS=("16.04" "18.04" "20.04" "22.04" "24.04")
if [[ ! " ${VALID_UBUNTU_VERSIONS[*]} " =~ " ${UBUNTU_VERSION} " ]]; then
  echo "错误: 不支持的 Ubuntu 版本 '${UBUNTU_VERSION}'"
  echo "支持的版本有: ${VALID_UBUNTU_VERSIONS[*]}"
  exit 1
fi

# 预检 docker 镜像是否存在
if ! command -v docker >/dev/null 2>&1; then
  echo "错误: 未找到 docker 命令，请先安装 Docker"
  exit 1
fi
if ! sudo docker image inspect "gcc-ubuntu:${UBUNTU_VERSION}" >/dev/null 2>&1; then
  echo "   未找到本地镜像 gcc-ubuntu:${UBUNTU_VERSION}，请先运行 build.sh 构建该镜像"
  exit 1
fi

# 检查 C 文件
if [ ! -f "$C_FILE" ]; then
  echo "错误: 文件 $C_FILE 不存在！"
  exit 1
fi
if [[ "$C_FILE" != *.c ]]; then
  echo "错误: 请输入以 .c 结尾的源文件"
  exit 1
fi

# 基本路径与输出名
ABS_C_FILE="$(realpath "$C_FILE")"
SRC_DIR="$(dirname "$ABS_C_FILE")"
NAME="$(basename "$ABS_C_FILE" .c)"



# 输出文件名
OUTPUT_FILE="${SRC_DIR}/${NAME}"
ABS_C_FILE="$(realpath "$C_FILE")"
SRC_DIR="$(dirname "$ABS_C_FILE")"
NAME="$(basename "$ABS_C_FILE" .c)"
# rpath 在 C 文件旁边
RPATH_DIR="${SRC_DIR}/rpath"
LD_SO="${RPATH_DIR}/ld-linux-x86-64.so.2"

echo ""
echo "1) 使用 Gcc - Ubuntu ${UBUNTU_VERSION} 编译：${ABS_C_FILE}"
echo "   输出：${OUTPUT_FILE}"
echo "   rpath 目录：${RPATH_DIR}"



echo ""
echo "3) 容器内编译..."
sudo docker run --rm \
  -v "$SRC_DIR:/app" \
  -w /app \
  "gcc-ubuntu:${UBUNTU_VERSION}" \
  /bin/bash -c "
    set -e
    rm -f \"$NAME\"
    echo '   -> gcc -g -o \"$NAME\" \"$(basename "$ABS_C_FILE")\"'
    gcc -g -o \"$NAME\" \"$(basename "$ABS_C_FILE")\"
    echo '   编译完成'
  "

# 确认生成
if [ ! -f "$OUTPUT_FILE" ]; then
  echo "错误: 编译失败，未生成 ${OUTPUT_FILE}"
  exit 1
fi

# patchelf：使用 C 文件旁的 rpath
echo ""
echo "4) 配置运行时链接 (patchelf)..."
if [ -d "$RPATH_DIR" ]; then
  if ! command -v patchelf >/dev/null 2>&1; then
    echo "   警告: 未找到 patchelf, 跳过该步骤"
  else
    if [ -f "$LD_SO" ]; then
      # 解释器使用“绝对路径”指向 C 文件旁的 ld-linux
      echo "   -> set-interpreter: $LD_SO"
      patchelf --set-interpreter "$LD_SO" "$OUTPUT_FILE"
      # RPATH 使用 $ORIGIN/rpath（$ 需要转义）
      echo "   -> set-rpath: \$ORIGIN/rpath"
      patchelf --set-rpath "\$ORIGIN/rpath" "$OUTPUT_FILE"
      
      
    else
      echo "   警告: 未找到 ${LD_SO}，仅设置 RPATH"
      patchelf --set-rpath "\$ORIGIN/rpath" "$OUTPUT_FILE"
    fi
  fi
else
  echo "   警告: 未找到 rpath 目录 ${RPATH_DIR}，跳过 patchelf 步骤"
fi
echo ""
echo "5) 文件信息："
file "$OUTPUT_FILE" || true

echo ""
echo "6) 动态库链接："
ldd -v "$OUTPUT_FILE" || true

echo ""
echo "7) 完成：${OUTPUT_FILE}"
