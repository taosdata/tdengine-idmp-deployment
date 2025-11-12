#!/bin/bash

# --- 配置区 ---
# 必须与备份脚本中的 VOLUMES_TO_BACKUP 列表保持一致。
# (请替换为你自己的)
VOLUMES_TO_RESTORE=(
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
    echo "请确保 .tar.gz 备份文件和 compose 配置文件在同一目录。"
    exit 1
fi
echo "将使用配置文件: $COMPOSE_FILE"
echo "---"
# --------------------------------

echo "### 开始执行 Docker Compose 数据恢复 ###"

echo "步骤 1/3: 正在创建新的空数据卷..."
# 使用检测到的命令
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up --no-start
echo "数据卷创建完毕。"

echo "步骤 2/3: 正在恢复数据..."
for volume in "${VOLUMES_TO_RESTORE[@]}"; do
    BACKUP_FILE="${volume}.tar.gz"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "  -> 错误：未找到备份文件 $BACKUP_FILE。跳过 $volume 的恢复。"
        continue
    fi

    echo "  -> 正在从 $BACKUP_FILE 恢复到 $volume ..."
    
    docker run --rm -v "${volume}":/data -v "$(pwd)":/backup alpine \
      tar xzf "/backup/${BACKUP_FILE}" -C /data

    if [ $? -eq 0 ]; then
        echo "  -> $volume 恢复成功。"
    else
        echo "  -> 错误： $volume 恢复失败。"
    fi
done

echo "步骤 3/3: 正在启动应用..."
# 使用检测到的命令
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up -d

echo "---"
echo "✅ 恢复完成并已启动服务！"
echo "应用已在新服务器上运行，并包含了所有迁移的数据。"