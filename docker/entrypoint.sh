#!/bin/bash
set -e

mkdir -p /usr/local/tdengine-ai/logs

cd /usr/local/tdengine-ai/

echo "Starting tdengine-ai-h2 (DB Service)..."
nohup java -cp /usr/local/tdengine-ai/lib/main/com.h2database.h2.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort 9092 -ifNotExists -web -webPort 8082 -webAllowOthers \
  > /usr/local/tdengine-ai/logs/tdengine-ai-h2.log 2>&1 &

for i in {1..10}; do
  if netstat -tln | grep 9092; then
    echo "tdengine-ai-h2 started."
    break
  fi
  sleep 2
done

echo "Starting tdengine-ai-chat (AI Service)..."
export $(grep -v '^#' /usr/local/tdengine-ai/service/tdengine-ai-chat.env | xargs) || true
nohup /usr/local/tdengine-ai/venv/bin/python3 /usr/local/tdengine-ai/chat/src/server.py \
  > /usr/local/tdengine-ai/logs/tdengine-ai-chat.log 2>&1 &


echo "Starting tdengine-ai (Main Service)..."
nohup java -Xms1g -Xmx2g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/usr/local/tdengine-ai/logs/ \
  -jar /usr/local/tdengine-ai/quarkus-run.jar \
  > /usr/local/tdengine-ai/logs/tdengine-ai.log 2>&1 &

echo "Waiting for tdengine-ai to listen on 6042..."
for i in {1..20}; do
  if netstat -tln | grep 6042; then
    echo "tdengine-ai is listening on 6042"
    break
  fi
  sleep 2
done

tail -F /usr/local/tdengine-ai/logs/*.log