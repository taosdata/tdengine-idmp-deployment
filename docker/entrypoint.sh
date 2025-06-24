#!/bin/bash
set -e

# necessary to make sure generator works
cd /usr/local/taos/idp/

echo "Starting TDengine IDP DB Service..."
nohup java -cp /usr/local/taos/idp/lib/main/com.h2database.h2.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort 9092 -ifNotExists -web -webPort 8082 -webAllowOthers \
  > /usr/local/taos/idp/logs/tdengine-idp-h2.log 2>&1 &

for i in {1..10}; do
  if netstat -tln | grep 9092; then
    echo "tdengine-idp-h2 started."
    break
  fi
  sleep 2
done

echo "Starting TDengine IDP Chat Service..."
export $(grep -v '^#' /usr/local/taos/idp/service/tdengine-idp-chat.env | xargs) || true
nohup /usr/local/taos/idp/venv/bin/python3 /usr/local/taos/idp/chat/src/server.py \
  > /usr/local/taos/idp/logs/tdengine-idp-chat.log 2>&1 &


echo "Starting TDengine IDP Service..."
nohup java -Xms1g -Xmx2g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/usr/local/taos/idp/logs/ \
  -jar /usr/local/taos/idp/quarkus-run.jar \
  > /usr/local/taos/idp/logs/tdengine-idp.log 2>&1 &

echo "Waiting for TDengine IDP Service to be ready..."
for i in {1..20}; do
  if netstat -tln | grep 6042; then
    echo "TDengine IDP is listening on port 6042"
    break
  fi
  sleep 2
done

tail -F /usr/local/taos/idp/logs/*.log