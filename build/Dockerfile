FROM alpine:3.9

ENV OPERATOR=/usr/local/bin/goserv \
    USER_UID=1001 \
    USER_NAME=goserv

# install operator binary
COPY build/_output/bin/goserv ${OPERATOR}

COPY build/bin /usr/local/bin

RUN  /usr/local/bin/user_setup

ENTRYPOINT ["/usr/local/bin/entrypoint"]

USER ${USER_UID}
