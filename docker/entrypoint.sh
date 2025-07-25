#!/bin/bash
set -e

# necessary to make sure generator works
cd /usr/local/taos/idmp

echo "Starting TDengine IDMP DB Service..."
nohup /usr/bin/java -cp /usr/local/taos/idmp/lib/main/com.h2database.h2.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort 9092 -ifNotExists -web -webPort 8082 -webAllowOthers 2>&1 &

for i in {1..10}; do
  if netstat -tln | grep 9092; then
    echo "tdengine-idmp-h2 started."
    break
  fi
  sleep 2
done

echo "Starting TDengine IDMP Chat Service..."
export $(grep -v '^#' /usr/local/taos/idmp/service/tdengine-idmp-chat.env | xargs) || true
nohup /usr/local/taos/idmp/venv/bin/python3 /usr/local/taos/idmp/chat/src/server.py 2>&1 &


echo "Starting TDengine IDMP Service..."
nohup /usr/bin/java -Xms1g -Xmx2g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/taos/ \
  -Dquarkus.config.locations=file:/usr/local/taos/idmp/config/application.yml \
  -jar /usr/local/taos/idmp/quarkus-run.jar 2>&1 &

echo "Waiting for TDengine IDMP Service to be ready..."
for i in {1..20}; do
  if netstat -tln | grep 6042; then
    echo "TDengine IDMP is listening on port 6042"
    break
  fi
  sleep 2
done

tail -F /var/log/taos/*.log