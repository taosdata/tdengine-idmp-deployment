#!/bin/bash
set -e

# necessary to make sure generator works
cd /usr/local/tdengine-ai/

echo "Starting TDengine AI DB Service..."
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

echo "Starting TDengine AI Chat Service..."
export $(grep -v '^#' /usr/local/tdengine-ai/service/tdengine-ai-chat.env | xargs) || true
nohup /usr/local/tdengine-ai/venv/bin/python3 /usr/local/tdengine-ai/chat/src/server.py \
  > /usr/local/tdengine-ai/logs/tdengine-ai-chat.log 2>&1 &


echo "Starting TDengine AI Service..."
nohup java -Xms1g -Xmx2g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/usr/local/tdengine-ai/logs/ \
  -jar /usr/local/tdengine-ai/quarkus-run.jar \
  > /usr/local/tdengine-ai/logs/tdengine-ai.log 2>&1 &

echo "Waiting for TDengine AI Service to be ready..."
for i in {1..20}; do
  if netstat -tln | grep 6042; then
    echo "TDengine AI is listening on port 6042"
    break
  fi
  sleep 2
done

tail -F /usr/local/tdengine-ai/logs/*.log