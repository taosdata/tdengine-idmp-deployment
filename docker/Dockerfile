FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG INSTALL_DIR=/usr/local
ARG DOWNLOAD_URL

ENV INSTALL_DIR=${INSTALL_DIR}

WORKDIR /root

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        wget \
        tar \
        bash \
        net-tools \
        openjdk-21-jre-headless \
        python3.10 \
        python3.10-venv \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd -r tdengine --gid=101 \
    && useradd -r -g tdengine --uid=101 --home-dir=/home/tdengine --shell=/bin/bash tdengine

RUN wget --progress=bar:force:noscroll "${DOWNLOAD_URL}" -O /root/TDengine-ai-enterprise-Linux.tar.gz \
    && mkdir TDengine-ai-enterprise \
    && tar -xzvf TDengine-ai-enterprise-Linux.tar.gz -C TDengine-ai-enterprise --strip-components=1 \
    && /root/TDengine-ai-enterprise/install.sh -d ${INSTALL_DIR} \
    && rm -rf /root/TDengine-ai-enterprise /root/TDengine-ai-enterprise-Linux.tar.gz \
    && mkdir -p /usr/local/tdengine-ai/logs \
    && chown -R tdengine:tdengine /usr/local/tdengine-ai

RUN chown -R tdengine:tdengine ${INSTALL_DIR}/tdengine || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6042

USER tdengine

WORKDIR /home/tdengine

ENTRYPOINT ["/entrypoint.sh"]