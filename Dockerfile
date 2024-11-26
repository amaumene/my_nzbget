FROM registry.access.redhat.com/ubi9 AS builder

RUN dnf install gcc gcc-c++ make libstdc++-devel cmake libxml2-devel openssl-devel -y

RUN export VERSION=$(curl -s https://api.github.com/repos/aawc/unrar/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)",/\1/') \
  && echo $VERSION > version.txt

WORKDIR /app

RUN curl -s https://api.github.com/repos/aawc/unrar/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs curl -L -o unrar.tar.gz

RUN mkdir unrar

RUN tar xvaf unrar.tar.gz -C unrar --strip-components=1

WORKDIR /app/unrar

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then sed -i 's|CXXFLAGS=-march=native|CXXFLAGS=-march=armv8-a+crypto+crc|' makefile; fi
RUN cat makefile | grep CXXFLAGS
RUN make
#RUN install -v -m755 unrar /usr/bin

WORKDIR /app

RUN curl -s https://api.github.com/repos/nzbgetcom/nzbget/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs curl -L -o nzbget.tar.gz

RUN mkdir nzbget

RUN tar xvaf nzbget.tar.gz -C nzbget --strip-components=1

WORKDIR /app/nzbget
RUN cmake . -DDISABLE_CURSES=ON
RUN cmake --build .
RUN ls -lah

FROM registry.access.redhat.com/ubi9/ubi-minimal

RUN microdnf install util-linux which -y

WORKDIR /app

COPY --from=builder /app/unrar/unrar /app/unrar
COPY --from=builder /app/nzbget/webui /app/webui
COPY --from=builder /app/nzbget/nzbget /app/nzbget
COPY --from=builder /app/nzbget/nzbget.conf /app/webui/nzbget.conf.template
COPY --from=builder /app/nzbget/nzbget.conf /app/nzbget.conf

COPY ./start.sh .

RUN sed -i \
    -e "s|^MainDir=.*|MainDir=/data/nzbget|g" \
    -e "s|^ScriptDir=.*|ScriptDir=$\{MainDir\}/scripts|g" \
    -e "s|^WebDir=.*|WebDir=$\{AppDir\}/webui|g" \
    -e "s|^ConfigTemplate=.*|ConfigTemplate=$\{AppDir\}/webui/nzbget.conf.template|g" \
    -e "s|^UnrarCmd=.*|UnrarCmd=unrar|g" \
    -e "s|^DestDir=.*|DestDir=$\{MainDir\}/completed|g" \
    -e "s|^InterDir=.*|InterDir=$\{MainDir\}/intermediate|g" \
    -e "s|^LogFile=.*|LogFile=$\{MainDir\}/nzbget.log|g" \
    -e "s|^AuthorizedIP=.*|AuthorizedIP=127.0.0.1|g" \
    /app/nzbget.conf

USER 1001

VOLUME /config

VOLUME /data

EXPOSE 6789/tcp

CMD [ "/app/start.sh" ]
