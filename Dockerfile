FROM alpine AS builder

RUN apk update \
  && apk upgrade \
  && apk add --no-cache \
    clang \
    clang-dev

RUN ln -sf /usr/bin/clang /usr/bin/cc \
  && ln -sf /usr/bin/clang++ /usr/bin/c++ 

RUN apk add git libxml2-static libxml2-dev xz-static zlib-static libxslt-static make openssl-libs-static openssl-dev boost-static boost-dev curl cmake util-linux-misc busybox-static

WORKDIR /app

RUN curl -s https://api.github.com/repos/aawc/unrar/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs curl -L -o unrar.tar.gz

RUN mkdir unrar

RUN tar xvaf unrar.tar.gz -C unrar --strip-components=1

WORKDIR /app/unrar

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then sed -i 's|CXXFLAGS=-march=native|CXXFLAGS=-mtune=cortex-a53 -march=armv8-a+crypto+crc|' makefile; fi

RUN sed -i 's|LDFLAGS=-pthread|LDFLAGS=-pthread -static|' makefile

RUN make -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

WORKDIR /app

RUN curl -s https://api.github.com/repos/nzbgetcom/nzbget/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs curl -L -o nzbget.tar.gz

RUN mkdir nzbget

RUN tar xvaf nzbget.tar.gz -C nzbget --strip-components=1

WORKDIR /app/nzbget

RUN mkdir build && \
      cd build && \
      if [ $(lscpu | grep -c aarch64) -gt 0 ]; then export CXXFLAGS="-mtune=cortex-a53 -march=armv8-a+crypto+crc -I/usr/include/libxml2"; else export CXXFLAGS="-I/usr/include/libxml2"; fi && \
      export LIBS="-lxml2 -lz -llzma -lrt -lboost_json -lssl -lcrypto -latomic -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" && \
      cmake .. -DDISABLE_CURSES=ON -DENABLE_STATIC=ON && \
      cmake --build . -v -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

RUN sed -i \
  -e "s|^MainDir=.*|MainDir=/data/nzbget|g" \
  -e "s|^ScriptDir=.*|ScriptDir=/config/scripts|g" \
  -e "s|^ConfigTemplate=.*|ConfigTemplate=$\{AppDir\}/nzbget.conf.template|g" \
  -e "s|^UnrarCmd=.*|UnrarCmd=/app/unrar|g" \
  -e "s|^WebDir=.*|WebDir=$\{AppDir}/webui|g" \
  -e "s|^DestDir=.*|DestDir=$\{MainDir\}/completed|g" \
  -e "s|^InterDir=.*|InterDir=$\{MainDir\}/intermediate|g" \
  -e "s|^LogFile=.*|LogFile=$\{MainDir\}/nzbget.log|g" \
  -e "s|^AuthorizedIP=.*|AuthorizedIP=127.0.0.1|g" \
  -e "s|^CertStore=.*|CertStore=/etc/ssl/certs/ca-certificates.crt|g" \
  build/nzbget.conf

FROM scratch

COPY --chown=65532 --from=builder /app/unrar/unrar /app/unrar
COPY --chown=65532 --from=builder /app/nzbget/build/nzbget /app/nzbget
COPY --chown=65532 --from=builder /app/nzbget/webui /app/webui
COPY --chown=65532 --from=builder /app/nzbget/build/nzbget.conf /app/nzbget.conf.template
COPY --chown=65532 --from=builder /app/nzbget/build/nzbget.conf /config/nzbget.conf

COPY --from=builder /bin/busybox.static /busybox
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

VOLUME /config

VOLUME /data

EXPOSE 6789/tcp

CMD [ "/app/nzbget", "-s", "-o", "OutputMode=log", "-c", "/config/nzbget.conf" ]
