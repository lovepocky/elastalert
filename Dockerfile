FROM alpine:latest as py-ea

ARG ELASTALERT_GIT=https://github.com/nrvnrvn/elastalert.git
ARG ELASTALERT_COMMIT=5da3e2ac15b37cc29d444c57e0ffbb28e5cc598d
# Elastalert home directory full path.
ENV ELASTALERT_HOME /opt/elastalert

WORKDIR /opt

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --update --no-cache ca-certificates openssl-dev openssl python2-dev python2 py2-pip py2-yaml libffi-dev gcc musl-dev wget git
ARG GIT_HTTPS_PROXY=
RUN HTTPS_PROXY=$GIT_HTTPS_PROXY git clone $ELASTALERT_GIT "${ELASTALERT_HOME}"

WORKDIR "${ELASTALERT_HOME}"

RUN git checkout ${ELASTALERT_COMMIT}

# * prepare pip
ARG PROXY_PYPI='https://mirrors.aliyun.com/pypi/simple'
ARG PROXY_HOST='mirrors.aliyun.com'

RUN printf "[easy_install]\n\
index-url=https://mirrors.aliyun.com/pypi/simple/\n\
find-links=https://mirrors.aliyun.com/pypi/simple/" > ~/.pydistutils.cfg

# bugfix: https://github.com/Yelp/elastalert/issues/2204
RUN pip install elasticsearch==6.3.0 -i $PROXY_PYPI

# Install Elastalert.
# see: https://github.com/Yelp/elastalert/issues/1654
RUN sed -i 's/jira>=1.0.10/jira>=1.0.10,<1.0.15/g' setup.py && \
    python setup.py install
RUN pip install -r requirements.txt -i $PROXY_PYPI

FROM node:alpine
LABEL maintainer="BitSensor <dev@bitsensor.io>"
# Set timezone for this container
ENV TZ Etc/UTC

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
RUN apk add --update --no-cache curl tzdata python2 make libmagic

COPY --from=py-ea /usr/lib/python2.7/site-packages /usr/lib/python2.7/site-packages
COPY --from=py-ea /opt/elastalert /opt/elastalert
COPY --from=py-ea /usr/bin/elastalert* /usr/bin/

WORKDIR /opt/elastalert-server
COPY . /opt/elastalert-server

COPY .npmrc /root/
RUN npm install --production --quiet
COPY config/elastalert.yaml /opt/elastalert/config.yaml
COPY config/elastalert-test.yaml /opt/elastalert/config-test.yaml
COPY config/config.json config/config.json
COPY rule_templates/ /opt/elastalert/rule_templates
COPY elastalert_modules/ /opt/elastalert/elastalert_modules

# Add default rules directory
# Set permission as unpriviledged user (1000:1000), compatible with Kubernetes
RUN mkdir -p /opt/elastalert/rules/ /opt/elastalert/server_data/tests/ \
    && chown -R node:node /opt

USER node

EXPOSE 3030
ENTRYPOINT ["npm", "start"]
