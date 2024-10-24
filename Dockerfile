FROM registry.access.redhat.com/ubi8 AS builder

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

FROM registry.access.redhat.com/ubi8/ubi-minimal

WORKDIR /app

COPY --from=builder /app/unrar/unrar /app/unrar
COPY --from=builder /app/nzbget/nzbget /app/nzbget
COPY --from=builder /app/nzbget/nzbget.conf /config/nzbget.conf

USER 1001

VOLUME /config

CMD [ "/app/nzbget", "-s", "-o", "OutputMode=log", "-c", "/config/nzbget.conf" ]

#RUN cmake .. -DCMAKE_INSTALL_PREFIX=/app/nzbget && \
#  cmake --build . -j 2 && \
#  cmake --build . --target install-conf && \
#  cmake --install . && \
#  mv /app/nzbget/bin/nzbget /app/nzbget/ && \
#  rm -rf /app/nzbget/bin/ && \
#  rm -rf /app/nzbget/etc/ && \
#  sed -i \
#    -e "s|^MainDir=.*|MainDir=/downloads|g" \
#    -e "s|^ScriptDir=.*|ScriptDir=$\{MainDir\}/scripts|g" \
#    -e "s|^WebDir=.*|WebDir=$\{AppDir\}/webui|g" \
#    -e "s|^ConfigTemplate=.*|ConfigTemplate=$\{AppDir\}/webui/nzbget.conf.template|g" \
#    -e "s|^UnrarCmd=.*|UnrarCmd=unrar|g" \
#    -e "s|^SevenZipCmd=.*|SevenZipCmd=7z|g" \
#    -e "s|^CertStore=.*|CertStore=$\{AppDir\}/cacert.pem|g" \
#    -e "s|^CertCheck=.*|CertCheck=yes|g" \
#    -e "s|^DestDir=.*|DestDir=$\{MainDir\}/completed|g" \
#    -e "s|^InterDir=.*|InterDir=$\{MainDir\}/intermediate|g" \
#    -e "s|^LogFile=.*|LogFile=$\{MainDir\}/nzbget.log|g" \
#    -e "s|^AuthorizedIP=.*|AuthorizedIP=127.0.0.1|g" \
#  /app/nzbget/share/nzbget/nzbget.conf && \
#  mv /app/nzbget/share/nzbget/webui /app/nzbget/ && \
#  cp /app/nzbget/share/nzbget/nzbget.conf /app/nzbget/webui/nzbget.conf.template && \
#  ln -s /usr/bin/7z /app/nzbget/7za && \
#  ln -s /usr/bin/unrar /app/nzbget/unrar && \
#  cp /nzbget/pubkey.pem /app/nzbget/pubkey.pem && \
#  curl -o /app/nzbget/cacert.pem -L "https://curl.se/ca/cacert.pem"
