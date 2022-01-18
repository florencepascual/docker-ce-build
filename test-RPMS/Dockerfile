# Dockerfile to test RPMS packages

ARG GOLANG_VERSION=1.16
ARG DISTRO_NAME
ARG DISTRO_VERS

FROM ppc64le/$DISTRO_NAME:$DISTRO_VERS

ARG GOLANG_VERSION
ARG DISTRO_NAME
ARG DISTRO_VERS

WORKDIR /workspace
RUN mkdir -p /workspace
ENV WORKSPACE=/workspace \
    TERM=xterm
ENV PATH /usr/local/go/bin:$PATH

RUN set -eux; yum -y install wget make gcc findutils procps-ng

COPY bundles-*.tar.gz /workspace
COPY *.rpm /workspace/
COPY test-launch.sh /usr/local/bin/test-launch.sh

RUN set -eux; \
    tar -xvzf bundles-*.tar.gz --wildcards  --strip-components 6 '*/RPMS/*' &&\
    yum -y localinstall *.rpm

##
#Docker in Docker inspired from
#  https://github.com/docker-library/docker/tree/master/20.10/dind
# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
##
RUN set -eux; \
	groupadd --system dockremap; \
	adduser --system -g dockremap dockremap; \
	echo 'dockremap:165536:65536' >> /etc/subuid; \
	echo 'dockremap:165536:65536' >> /etc/subgid

# https://github.com/docker/docker/tree/master/hack/dind
ENV DIND_COMMIT 42b1175eda071c0e9121e1d64345928384a93df1
# ENV DIND_COMMIT ed89041433a031cafc0a0f19cfe573c31688d377
ENV DOCKERD_COMMIT 8baa881aab85f8398d2edbbcc0da4bd1f556dd98
# ENV DOCKERD_COMMIT 094faa88f437cafef7aeb0cc36e75b59046cc4b9

RUN set -eux; \
        wget -O /usr/local/bin/dind "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind"; \
        wget -O /usr/local/bin/dockerd-entrypoint.sh "https://raw.githubusercontent.com/docker-library/docker/${DOCKERD_COMMIT}/20.10/dind/dockerd-entrypoint.sh"; \
        chmod +x /usr/local/bin/dind; \
        chmod +x /usr/local/bin/dockerd-entrypoint.sh; \
        chmod +x /usr/local/bin/test-launch.sh;

RUN set -eux; \
    url="https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-ppc64le.tar.gz";\
    wget -O go.tgz "$url" --progress=dot:giga; \
    tar -C /usr/local -xzf go.tgz; \
    rm go.tgz; \
    go version;

VOLUME /var/lib/docker
EXPOSE 2375 2376

ENTRYPOINT ["/usr/local/bin/test-launch.sh"]
CMD []
