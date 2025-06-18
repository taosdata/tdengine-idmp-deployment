# TDengine AI Docker 项目

简体中文 | [English](README.md)

本项目提供了 TDengine AI 应用程序的 Docker 化版本。它包含了使用 Docker 和 Docker Compose 构建、运行和部署 TDengine AI 应用程序所需的所有文件。

## 项目结构

```
TDengine AI docker
│── Dockerfile           # 构建 TDengine AI Docker 镜像的指令文件
│── entrypoint.sh        # TDengine AI 应用程序的初始化脚本
│── docker-compose.yml   # 使用 Docker Compose 部署 TDengine AI 的配置文件
└── README.md            # 项目文档
```

## 前置条件

- Docker：确保您的机器上已安装并运行 Docker
- Docker Compose：确保已安装 Docker Compose

## 构建 Docker 镜像

要构建 TDengine AI Docker 镜像，请导航到项目目录并运行以下命令。以版本 0.9.6 为例：

```bash
docker build \
  -t tdengine-ai:0.9.6 \
  --build-arg DOWNLOAD_URL="https://downloads.taosdata.com/tdengine-ai/enterprise/0.9.6/tdengine-ai-enterprise-0.9.6-linux.tar.gz" .
docker tag tdengine/tdengine-ai:0.9.6 tdengine/tdengine-ai:latest
```

## 运行 Docker 容器

构建镜像后，您可以使用 Docker Compose 运行 TDengine AI 应用程序。执行以下命令：

```bash
docker compose -f docker-compose.yml up -d
```

此命令将启动 TDengine AI 应用程序及其定义的所有依赖项。

## 停止应用程序

要停止运行中的应用程序，您可以使用：

```bash
docker compose -f docker-compose.yml down
```