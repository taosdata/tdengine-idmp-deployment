#!/bin/bash
set -e

if [ -n "$TZ" ]; then
  echo "Setting timezone to $TZ"
  export TZ="$TZ"
  echo "Current shell time: $(date)"
fi

if [ -n "$TSDB_URL" ]; then
  echo "TSDB_URL is set to $TSDB_URL"
  ESCAPED_URL=$(echo "$TSDB_URL" | sed 's/[\/&]/\\&/g')
  sed -i "s|url:[[:space:]]*http://localhost:6041|url: $ESCAPED_URL|" /usr/local/taos/idmp/config/application.yml
fi

# necessary to make sure generator works
cd /usr/local/taos/idmp

echo "Starting TDengine IDMP DB Service..."
WEB_H2_EXTERNAL_NAMES=()
[ -n "${H2_EXTERNAL_NAME}" ] && WEB_H2_EXTERNAL_NAMES=(-webExternalNames "${H2_EXTERNAL_NAME}")
nohup /usr/bin/java -cp /usr/local/taos/idmp/lib/main/com.h2database.h2.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort 9092 -ifNotExists -web -webPort 8082 -webAllowOthers "${WEB_H2_EXTERNAL_NAMES[@]}" 2>&1 &

for i in {1..10}; do
  if netstat -tln | grep 9092; then
    echo "tdengine-idmp-h2 started."
    break
  fi
  sleep 2
done

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

echo "Starting TDengine IDMP Chat Service..."
export $(grep -v '^#' /usr/local/taos/idmp/service/tdengine-idmp-chat.env | xargs) || true
nohup /usr/local/taos/idmp/venv/bin/python3 /usr/local/taos/idmp/chat/src/server.py 2>&1 &


tail -F /var/log/taos/*.log