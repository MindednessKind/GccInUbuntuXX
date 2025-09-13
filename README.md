# GccInUbuntuXX
该工具用于在UbuntuXX版本下跑单文件编译(以后可能尝试去支持 MAKEFILE+项目文件 编译,但自己用不到,可能会很慢)
当前支持 Ubuntu 版本 16.04 18.04 20.04 22.04 24.04
简单的一个小脚本,如有问题可以提出. 会尝试解决的 XD


# 前置需求
该脚本依赖 Docker. 因而需要你自己安装
```sh
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```



在使用cgcc之前，你需要运行 build.sh 来完成对 对应Ubuntu版本的GCC编译环境的Docker镜像的封装。
完成对应版本的封装后,直接运行 cgcc即可
