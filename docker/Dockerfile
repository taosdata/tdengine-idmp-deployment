FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG DOWNLOAD_URL

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
        fontconfig \
        locales \
        tzdata \
    && ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV TZ=Asia/Shanghai \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 

RUN groupadd -r tdengine --gid=101 \
    && useradd -r -g tdengine --uid=101 --home-dir=/home/tdengine --shell=/bin/bash tdengine

RUN wget --progress=bar:force:noscroll "${DOWNLOAD_URL}" -O /tmp/tdengine-idp-enterprise-linux.tar.gz \
    && tar -xzf /tmp/tdengine-idp-enterprise-linux.tar.gz -C /tmp \
    && rm -f /tmp/tdengine-idp-enterprise-linux.tar.gz \
    && cd /tmp/tdengine-idp-enterprise-* \
    && ./install.sh -s -n \
    && rm -rf /tmp/* \
    && chown -R tdengine:tdengine /usr/local/taos/idp

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 6042

USER tdengine

WORKDIR /home/tdengine

ENTRYPOINT ["/entrypoint.sh"]
