#!/bin/bash

set -euo pipefail

VERSION_LIST=("16.04" "18.04" "20.04" "22.04" "24.04")
ARCH_LIST=("amd64" "i386")

INPUT_FILES=()
OUTPUT_FILE="a.out"
UBUNTU_VERSION="16.04"
ARCH="amd64"
DEBUG_FLAG=""
PATCHELF_FLAG=""
RPATH_DIR=""
ASSEMBLE_ONLY_FLAG=""
NO_LINK_FLAG=""
GCC_EXTRA_ARGS=()

help() {
cat << 'EOF2'
    简易 C 编译脚本，使用 Docker 容器编译 C 代码。
    用法: cgcc [cgcc options] <input files> [gcc options]

    cgcc 选项:
        -h,--help            显示此帮助信息
        -g,--debug           启用调试信息
        -S                   仅编译为汇编代码,不进行汇编和链接
        -c                   仅编译为目标文件,不进行链接
        -o,--output FILE     指定输出文件名 (默认: a.out)
        -a,--arch ARCH       指定目标架构 (默认: amd64)
        -u,--ubuntu version  指定 Ubuntu 版本 (默认: 16.04)
        -P,--patchelf        启用 patchelf 修改解释器和 rpath
        -R,--rpath DIR       指定 rpath 目录 (默认: 当前目录/rpath)
        --                   后续参数全部透传给 gcc

    说明:
        除上述 cgcc 自身参数外，其余参数都会原样透传给 gcc，
        因此可以使用 gcc 支持的全部参数。
EOF2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -g|--debug)
                DEBUG_FLAG=true
                shift
                ;;
            -S)
                if [[ -n "$NO_LINK_FLAG" ]]; then
                    echo "错误: 选项 -S 和 -c 不能同时使用."
                    exit 1
                fi
                ASSEMBLE_ONLY_FLAG=true
                shift
                ;;
            -c)
                if [[ -n "$ASSEMBLE_ONLY_FLAG" ]]; then
                    echo "错误: 选项 -S 和 -c 不能同时使用."
                    exit 1
                fi
                NO_LINK_FLAG=true
                shift
                ;;
            -a|--arch)
                ARCH="$2"
                shift 2
                ;;
            -u|--ubuntu)
                UBUNTU_VERSION="$2"
                shift 2
                ;;
            -R|--rpath)
                RPATH_DIR="$2"
                shift 2
                ;;
            -P|--patchelf)
                PATCHELF_FLAG="True"
                shift
                ;;
            -h|--help)
                help
                exit 0
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    GCC_EXTRA_ARGS+=("$1")
                    shift
                done
                break
                ;;
            -*)
                GCC_EXTRA_ARGS+=("$1")
                shift
                ;;
            *)
                INPUT_FILES+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        echo -e "\033[1;31mfatal error:\033[0m no input files." 1>&2
        exit 1
    fi

    if [[ -z "$RPATH_DIR" ]]; then
        RPATH_DIR="$(pwd)/rpath"
    fi
}

parse_args "$@"

sudo -v

if [[ ! " ${VERSION_LIST[*]} " =~ " ${UBUNTU_VERSION} " ]]; then
  echo "错误: 不支持的 Ubuntu 版本 '$UBUNTU_VERSION'. 支持的版本: ${VERSION_LIST[*]}"
  exit 1
fi
if [[ ! " ${ARCH_LIST[*]} " =~ " ${ARCH} " ]]; then
  echo "错误: 不支持的架构 '$ARCH'. 支持的架构: ${ARCH_LIST[*]}"
  exit 1
fi

DOCKER_IMAGE="gcc-ubuntu:$UBUNTU_VERSION"

if ! command -v docker >/dev/null 2>&1; then
  echo "错误: 未找到 docker 命令，请先安装 Docker"
  exit 1
fi
if ! sudo docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
  echo "   未找到本地镜像 $DOCKER_IMAGE，请先运行 download.sh 构建该镜像"
  exit 1
fi

for input in "${INPUT_FILES[@]}"; do
  if [[ ! -e "$input" ]]; then
    echo "错误: 输入文件 '$input' 不存在."
    exit 1
  fi
done

if [[ "$ARCH" == "i386" ]]; then
  GCC_ARCH_FLAG="-m32"
  LD_SO_NAME="ld-linux.so.2"
else
  GCC_ARCH_FLAG=""
  LD_SO_NAME="ld-linux-x86-64.so.2"
fi

WORKDIR="$(pwd)"
INPUT_BASENAMES=()
for input in "${INPUT_FILES[@]}"; do
  INPUT_BASENAMES+=("$(basename "$input")")
done

cat << EOF2
1) 使用 Gcc - Ubuntu ${UBUNTU_VERSION}
    输入：${INPUT_FILES[*]}
    输出：${OUTPUT_FILE}
    Arch: ${ARCH}
    GCC透传参数：${GCC_EXTRA_ARGS[*]:-(无)}
EOF2

printf -v INPUT_ARGS_Q ' %q' "${INPUT_BASENAMES[@]}"
printf -v EXTRA_ARGS_Q ' %q' "${GCC_EXTRA_ARGS[@]}"

sudo docker run --rm \
  -v "$WORKDIR:/app" \
  -w /app \
  "$DOCKER_IMAGE" \
  /bin/bash -c "
    set -e
    rm -f \"$OUTPUT_FILE\"
    echo gcc ${GCC_ARCH_FLAG} -o \"$OUTPUT_FILE\"${INPUT_ARGS_Q} ${DEBUG_FLAG:+-g} ${ASSEMBLE_ONLY_FLAG:+-S} ${NO_LINK_FLAG:+-c}${EXTRA_ARGS_Q}
    gcc ${GCC_ARCH_FLAG} -o \"$OUTPUT_FILE\"${INPUT_ARGS_Q} ${DEBUG_FLAG:+-g} ${ASSEMBLE_ONLY_FLAG:+-S} ${NO_LINK_FLAG:+-c}${EXTRA_ARGS_Q}
    echo '   编译完成'
  "

if [[ -f "$OUTPUT_FILE" ]]; then
  cat << EOF2
2) 文件信息：
    $(file "$OUTPUT_FILE" || true)
    $(ldd -v "$OUTPUT_FILE" || true)
EOF2
fi

if [[ -n "$PATCHELF_FLAG" && -f "$OUTPUT_FILE" ]]; then
  if ! command -v patchelf >/dev/null 2>&1; then
      echo "警告: 未找到 patchelf, 跳过该步骤"
  elif [ ! -d "$RPATH_DIR" ]; then
      echo "警告: 未找到 rpath 目录 ${RPATH_DIR}，跳过 patchelf 步骤"
  else
      LD_SO="${RPATH_DIR}/${LD_SO_NAME}"
      if [ ! -f "$LD_SO" ]; then
          echo "警告: 未找到 ${LD_SO_NAME}, 跳过 patchelf 步骤"
      else
          patchelf --set-interpreter "$LD_SO" "$OUTPUT_FILE"
          patchelf --set-rpath "$RPATH_DIR" "$OUTPUT_FILE"
          echo "patchelf 配置完成"
      fi
  fi
fi

echo "完成"
