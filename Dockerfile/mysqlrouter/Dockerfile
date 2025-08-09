FROM registry.cn-beijing.aliyuncs.com/wny311/minideb:bookworm

COPY *.deb /tmp 
COPY mysqlrouter.conf mysqlrouter.conf
RUN install_packages libssl3 && \
    dpkg -i /tmp/mysql-router-community_8.0.43-1debian12_amd64.deb && \
    dpkg -i /tmp/mysql-router_8.0.43-1debian12_amd64.deb && apt-get clean && rm -rf /var/lib/apt/lists /var/cache/apt/archives /tmp/*.deb
EXPOSE 6446 6447 6448 6449 6450 8443
USER 1002
ENTRYPOINT ["mysql-router --config /etc/mysqlrouter/mysqlrouter.conf"]
