FROM alpine AS wsdd2-builder

RUN apk add --no-cache make gcc libc-dev linux-headers && wget -O - https://github.com/Netgear/wsdd2/archive/refs/heads/master.tar.gz | tar zxvf - \
 && cd wsdd2-master && make

FROM alpine
# alpine:3.14

COPY --from=wsdd2-builder /wsdd2-master/wsdd2 /usr/sbin

ENV PATH="/container/scripts:${PATH}"

RUN apk add --no-cache runit \
                       tzdata \
                       avahi \
                       samba \
 \
 && sed -i 's/#enable-dbus=.*/enable-dbus=no/g' /etc/avahi/avahi-daemon.conf \
 && rm -vf /etc/avahi/services/* \
 \
 && mkdir -p /external/avahi \
 && touch /external/avahi/not-mounted \
 && echo done

# install crudini

RUN apk update
RUN apk upgrade
RUN apk add python3
RUN apk add py3-pip
RUN pip3 install --break-system-packages iniparse
RUN pip3 install --break-system-packages crudini

#

VOLUME ["/shares"]

EXPOSE 137/udp 139 445

COPY . /container/

HEALTHCHECK CMD ["/container/scripts/docker-healthcheck.sh"]
ENTRYPOINT ["/container/scripts/entrypoint.sh"]

CMD [ "runsvdir","-P", "/container/config/runit" ]
