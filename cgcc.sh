#!/bin/bash

VERSION_LIST=("16.04" "18.04" "20.04" "22.04" "24.04")
ARCH_LIST=("amd64" "i386")

INPUT_FILE=""
OUTPUT_FILE="a.out"
UBUNTU_VERSION="16.04"
ARCH="amd64"
DEBUG_FLAG=""
PATCHELF_FLAG=""
RPATH_DIR=""
ASSEMBLE_ONLY_FLAG=""
NO_LINK_FLAG=""
help() {
cat << EOF
    简易 C 编译脚本，使用 Docker 容器编译 C 代码。
    用法: $0 [options] source.c"
    选项:
        -h,--help            显示此帮助信息
        -g,--debug            启用调试信息
        -S                   仅编译为汇编代码,不进行汇编和链接
        -c                  仅编译为目标文件,不进行链接
        -o,--output FILE     指定输出文件名 (默认: a.out)
        -a,--arch ARCH       指定目标架构 (默认: amd64) 支持: ${ARCH_LIST[*]}
        -u,--ubuntu version   指定 Ubuntu 版本 (默认: 16.04) 支持: ${VERSION_LIST[*]}
        -P,--patchelf       启用 patchelf 修改绑定 glibc 版本(默认: 关闭)
        -R,--rpath DIR      指定 rpath 目录 (默认: 源文件同目录下的 rpath)
        --                   结束选项，后续参数视为输入文件
EOF
}
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -g|--debug)
                DEBUG_FLAG=true
                shift
                ;;
            -S)
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
                break
                ;;
            -*)
                echo "错误: 未知选项 '$1'"
                help
                exit 1
                ;;
            *)
                if [[ -z "$INPUT_FILE" ]]; then
                    INPUT_FILE="$1"
                    shift
                else
                    echo "错误: 多个输入文件指定: '$INPUT_FILE' 和 '$1'"
                    exit 1
                fi
                ;;
        esac
    done


    if [[ -z "$INPUT_FILE" ]]; then
        echo -e "\033[1;31mfatal error:\033[0m no input files." 1>&2
        exit 1
    fi

    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "错误: 输入文件 '$INPUT_FILE' 不存在."
        exit 1
    fi

    if [[ -z "$RPATH_DIR" ]]; then
        RPATH_DIR="$(dirname "$INPUT_FILE")/rpath"
    fi

    if [[ ! -d "$RPATH_DIR" ]]; then
        echo "警告: rpath 目录 '$RPATH_DIR' 不存在，继续编译但不会进行 patchelf."
        PATCHELF_FLAG=""
    fi
}

parse_args "$@"
FILE_PATH=$(realpath "$INPUT_FILE")
FILE_DIR=$(dirname "$FILE_PATH")
FILE_NAME=$(basename "$FILE_PATH")


sudo -v

echo "编译 '$FILE_NAME' 为 '$OUTPUT_FILE' (Ubuntu $UBUNTU_VERSION, Arch: $ARCH, Debug: $DEBUG_FLAG)"
# echo "源文件路径: $FILE_PATH 目录: $FILE_DIR 文件名: $FILE_NAME"

# 检查版本和架构
if [[ ! " ${VERSION_LIST[*]} " =~ " ${UBUNTU_VERSION} " ]]; then
  echo "错误: 不支持的 Ubuntu 版本 '$UBUNTU_VERSION'. 支持的版本: ${VERSION_LIST[*]}"
  exit 1
fi
if [[ ! " ${ARCH_LIST[*]} " =~ " ${ARCH} " ]]; then
  echo "错误: 不支持的架构 '$ARCH'. 支持的架构: ${ARCH_LIST[*]}"
  exit 1
fi

DOCKER_IMAGE="gcc-ubuntu:$UBUNTU_VERSION"

# 预检 docker 镜像是否存在
if ! command -v docker >/dev/null 2>&1; then
  echo "错误: 未找到 docker 命令，请先安装 Docker"
  exit 1
fi
if ! sudo docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
  echo "   未找到本地镜像 $DOCKER_IMAGE，请先运行 build.sh 构建该镜像"
  exit 1
fi

# 检查 C 文件
if [[ "$FILE_NAME" != *.c ]]; then
  echo "错误: 请输入以 .c 结尾的源文件"
  exit 1
fi


cat << EOF 
1) 使用 Gcc - Ubuntu ${UBUNTU_VERSION}
    编译：${FILE_PATH}
    输出：${OUTPUT_FILE}
    Arch: ${ARCH}
EOF

cat << EOF

2) 在容器内编译...
EOF

sudo docker run --rm \
  -v "$FILE_DIR:/app" \
  -w /app \
  "gcc-ubuntu:${UBUNTU_VERSION}" \
  /bin/bash -c "
    set -e
    rm -f \"$OUTPUT_FILE\"
    echo '   -> gcc -o \"$OUTPUT_FILE\" \"$(basename "$FILE_PATH")\" ${DEBUG_FLAG:+-g} ${ASSEMBLE_ONLY_FLAG:+-S} ${NO_LINK_FLAG:+-c}'
    gcc -o \"$OUTPUT_FILE\" \"$(basename "$FILE_PATH")\" ${DEBUG_FLAG:+-g} ${ASSEMBLE_ONLY_FLAG:+-S} ${NO_LINK_FLAG:+-c}
    echo '   编译完成'
  "

# 确认生成
if [ ! -f "${FILE_DIR}/${OUTPUT_FILE}" ]; then
  echo "错误: 编译失败，未生成输出文件 ${OUTPUT_FILE}"
  exit 1
fi

cat << EOF
3) 配置运行时链接 (patchelf)...
EOF

if [[ -n "$PATCHELF_FLAG" ]]; then
    if ! command -v patchelf >/dev/null 2>&1; then
        echo "   警告: 未找到 patchelf, 跳过该步骤"
    elif [ ! -d "$RPATH_DIR" ]; then
        echo "   警告: 未找到 rpath 目录 ${RPATH_DIR}，跳过 patchelf 步骤"
    else
        LD_SO="${RPATH_DIR}/ld-linux-x86-64.so.2"
        if [ ! -f "$LD_SO" ]; then
            echo "   警告: 未找到 ld-linux-x86-64.so.2, 跳过 patchelf 步骤"
        else
            echo "   -> patchelf --set-interpreter \"$LD_SO\" --set-rpath \"$RPATH_DIR\" \"$OUTPUT_FILE\""
            patchelf --set-interpreter "$LD_SO" "$FILE_DIR/$OUTPUT_FILE"
            patchelf --set-rpath "$RPATH_DIR" "$FILE_DIR/$OUTPUT_FILE"
            echo "   patchelf 配置完成"
        fi
    fi
fi
cat << EOF
4) 文件信息：
    $(file "$FILE_DIR/$OUTPUT_FILE" || true)
    $(ldd -v "$FILE_DIR/$OUTPUT_FILE" || true)
EOF

echo "
5) 完成：${OUTPUT_FILE}
"