#!/bin/bash

# --- 配置区 ---
# 请根据你的 docker-compose 配置文件或 'docker volume ls' 的结果，
# 在下面列出所有需要备份的卷名称。
# (这里使用了文档中的示例卷名，请替换为你自己的)
VOLUMES_TO_BACKUP=(
  "docker_tsdb_data"
  "docker_idmp_data"
  "docker_tsdb_log"
  "docker_idmp_log"
)
# ---------------

# --- 1. 自动检测 Docker Compose 命令 ---
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "错误：找不到可用的 Docker Compose 命令。" >&2
    echo "请确保已安装 Docker Compose V1 (docker-compose) 或 V2 (docker compose)。" >&2
    exit 1
fi
echo "---"
echo "检测到使用命令: $DOCKER_COMPOSE_CMD"
# ------------------------------------

# --- 2. 选择 Compose 配置文件 ---
echo "请选择要使用的 Docker Compose 配置文件:"
echo "  1) docker-compose.yml (默认)"
echo "  2) docker-compose-tdgpt.yml"
read -p "请输入选项 (1 或 2)，直接按回车将使用默认值 [1]: " choice

COMPOSE_FILE=""
case "${choice:-1}" in
    1)
        COMPOSE_FILE="docker-compose.yml"
        ;;
    2)
        COMPOSE_FILE="docker-compose-tdgpt.yml"
        ;;
    *)
        echo "无效输入。将使用默认值 'docker-compose.yml'。"
        COMPOSE_FILE="docker-compose.yml"
        ;;
esac

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "错误：所选的配置文件 '$COMPOSE_FILE' 不在当前目录。"
    exit 1
fi
echo "将使用配置文件: $COMPOSE_FILE"
echo "---"
# --------------------------------

echo "### 开始执行 Docker Compose 数据备份 ###"

echo "步骤 1/2: 正在停止 Docker Compose 服务..."
# 使用检测到的命令
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down
echo "服务已停止。"

echo "步骤 2/2: 正在备份数据卷..."
for volume in "${VOLUMES_TO_BACKUP[@]}"; do
    BACKUP_FILE="${volume}.tar.gz"
    echo "  -> 正在备份 $volume 到 $BACKUP_FILE ..."

    docker run --rm -v "${volume}":/data -v "$(pwd)":/backup alpine \
      tar czf "/backup/${BACKUP_FILE}" -C /data .

    if [ $? -eq 0 ]; then
        echo "  -> $volume 备份成功。"
    else
        echo "  -> $volume 备份完成（可能伴随 socket ignored 提示，属正常现象）。"
    fi
done

echo "---"
echo "✅ 备份完成！"
echo "当前目录已生成以下备份文件:"
ls -lh *.tar.gz
echo "---"
echo "下一步：请将此目录下的所有 .tar.gz 文件和 $COMPOSE_FILE 文件 传输到您的目标服务器上。"