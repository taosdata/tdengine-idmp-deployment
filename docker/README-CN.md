# TDengine IDMP Docker 项目

简体中文 | [English](README.md)

本项目提供了 TDengine IDMP 应用程序的 Docker 化版本。它包含了使用 Docker 和 Docker Compose 构建、运行和部署 TDengine IDMP 应用程序所需的所有文件。

## 项目结构

```
TDengine IDMP docker
│── Dockerfile                # 构建 TDengine IDMP Docker 镜像的指令文件
│── entrypoint.sh             # TDengine IDMP 应用程序的初始化脚本
│── docker-compose.yml        # 标准部署配置文件（TSDB Enterprise + IDMP）
│── docker-compose-tdgpt.yml  # 完整部署配置文件（TSDB Enterprise + IDMP + TDgpt）
│── init-anode.sql            # TDengine anode 初始化脚本
│── README.md                 # 英文项目文档
└── README-CN.md              # 中文项目文档
```

## 前置条件

- Docker：确保您的机器上已安装并运行 Docker
- Docker Compose：确保已安装 Docker Compose

## 构建 Docker 镜像

要构建 TDengine IDMP Docker 镜像，请导航到项目目录并运行以下命令。

**注意：** 请将 `<version>` 替换为实际的版本号。

```bash
docker build \
  -t tdengine/idmp-ee:<version> \
  --build-arg DOWNLOAD_URL="https://downloads.taosdata.com/tdengine-idmp-enterprise/<version>/tdengine-idmp-enterprise-<version>-linux-generic.tar.gz" .
docker tag tdengine/idmp-ee:<version> tdengine/idmp-ee:latest
```

## 部署方式

本项目提供两种部署方式：

### 方式一：标准部署（推荐用于开发环境）

仅包含 TDengine TSDB 企业版和 IDMP 服务，不包含 AI 功能：

```bash
# 启动标准服务
docker compose up -d

# 停止服务
docker compose down
```

**服务端口：**
- **6030**: TDengine TSDB 企业版客户端连接端口
- **6041**: TDengine TSDB 企业版REST API 端口
- **6060**: TDengine TSDB 企业版管理系统前端端口
- **6042**: IDMP Web 前端端口
- **8082**: IDMP h2  服务端口

### 方式二：完整部署（包含 AI 功能）

包含完整的 TDengine 生态系统和 AI 分析能力：

```bash
# 启动完整服务
docker compose -f docker-compose-tdgpt.yml up -d

# 停止服务
docker compose -f docker-compose-tdgpt.yml down
```

**额外端口：**
- **6090**: TDgpt 主服务端口
- **5000**: 模型服务端口
- **5001**: 扩展模型服务端口

**服务启动顺序：**
1. **TDgpt 服务**: 优先启动，提供 AI 分析能力
2. **TDengine TSDB Enterprise**: 等待 TDgpt 健康检查通过后启动，自动创建 anode 连接
3. **IDMP 服务**: 最后启动，依赖 TSDB 企业版服务正常运行

## 健康检查

所有服务都配置了健康检查机制，确保服务按正确顺序启动：
- **TDgpt**: 检查 6090 端口可用性
- **TSDB Enterprise**: 检查数据库连接状态
- **IDMP**: 检查 6042 端口可用性

## 镜像配置

### TDgpt 镜像版本

如需使用完整版 TDgpt 镜像，可修改 `docker-compose-tdgpt.yml` 中的镜像配置：

```yaml
services:
  tdengine-tdgpt:
    image: tdengine/tdgpt-full:latest  # 完整版镜像
    # 或
    image: tdengine/tdgpt:latest       # 标准版镜像
```

## 使用建议

- **开发环境**: 使用标准 `docker-compose.yml` 即可满足基本需求
- **需要 AI 功能**: 使用 `docker-compose-tdgpt.yml` 获得完整功能
- **生产环境**: 根据实际业务需求选择对应的配置文件

