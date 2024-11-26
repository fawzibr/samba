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

# create dynamic/persistent directories

RUN mkdir -p /dynamic-volumes

# install crudini/webhook/jq/jo

RUN apk add --no-cache python3 py3-pip webhook jq moreutils
RUN pip3 install --break-system-packages iniparse
#RUN pip3 install --break-system-packages crudini
# remove after crudini package updated
RUN apk add --no-cache git
RUN pip3 install --break-system-packages git+https://github.com/pixelb/crudini.git#egg=crudini
#

# udp port 137: Netbios Name Service
# udp port 138: Netbios Datagram Service
# tcp port 139: SMB for Windows NT or older
# tcp port 445: SMB for Windows 2000 or newer

EXPOSE 137/udp 138/udp 139 445

COPY . /container/

HEALTHCHECK CMD ["/container/scripts/docker-healthcheck.sh"]
ENTRYPOINT ["/container/scripts/entrypoint.sh"]

CMD [ "runsvdir","-P", "/container/config/runit" ]
