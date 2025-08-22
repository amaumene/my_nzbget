FROM alpine AS builder

RUN apk add --no-cache \
    clang \
    lscpu \
    autoconf \
    automake \
    make \
    cmake \
    linux-headers \
    perl \
    git \
    libxml2-static libxml2-dev xz-static zlib-static libxslt-static boost-static boost-dev curl cmake util-linux-misc

### Build unrar

FROM builder AS unrar

RUN apk add --no-cache \
    linux-headers

WORKDIR /app

RUN wget -O - https://api.github.com/repos/aawc/unrar/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs wget -O unrar.tar.gz

RUN mkdir unrar

RUN tar xaf unrar.tar.gz -C unrar --strip-components=1

WORKDIR /app/unrar

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then sed -i 's|CXXFLAGS=.*|CXXFLAGS=-march=armv8-a+crypto+crc -O2 -std=c++11 -Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else|' makefile; fi
RUN if [ $(lscpu | grep -c x86_64) -gt 0 ]; then sed -i 's|CXXFLAGS=.*|CXXFLAGS=-march=broadwell -O2 -std=c++11 -Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else|' makefile; fi
RUN sed -i 's|CXX=.*|CXX=clang++|' makefile

RUN sed -i 's|LDFLAGS=-pthread|LDFLAGS=-pthread -static|' makefile

RUN make -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

### Build nzbget

FROM builder AS nzbget

RUN apk add --no-cache \
    libxml2-static \
    libxml2-dev \
    xz-static \
    zlib-static \
    libxslt-static \
    boost-static \
    boost-dev \
    openssl-dev \
    openssl-libs-static

WORKDIR /app

RUN wget -O - https://api.github.com/repos/nzbgetcom/nzbget/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs wget -O nzbget.tar.gz

RUN mkdir nzbget

RUN tar xvaf nzbget.tar.gz -C nzbget --strip-components=1

WORKDIR /app/nzbget

RUN mkdir build && \
      cd build && \
      if [ $(lscpu | grep -c aarch64) -gt 0 ]; \
      then export CXXFLAGS="-march=armv8-a+crypto+crc -I/usr/include/libxml2"; export CFLAGS="-march=armv8-a+crypto+crc"; \
      else export CXXFLAGS="-I/usr/include/libxml2"; \
      fi && \
      if [ $(lscpu | grep -c x86_64) -gt 0 ]; \
      then export CXXFLAGS="-march=broadwell -I/usr/include/libxml2"; export CFLAGS="-march=broadwell"; \
      else export CXXFLAGS="-I/usr/include/libxml2"; \
      fi && \
      export LIBS="-lxml2 -lz -llzma -lrt -lboost_json -lssl -lcrypto -latomic -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" && \
      export CC=clang && export CXX=clang++ && \
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

FROM alpine

COPY --chown=65532 --from=unrar /app/unrar/unrar /app/unrar
COPY --chown=65532 --from=nzbget /app/nzbget/build/nzbget /app/nzbget
COPY --chown=65532 --from=nzbget /app/nzbget/webui /app/webui
COPY --chown=65532 --from=nzbget /app/nzbget/build/nzbget.conf /app/nzbget.conf.template
COPY --chown=65532 --from=nzbget /app/nzbget/build/nzbget.conf /config/nzbget.conf

VOLUME /config

VOLUME /data

EXPOSE 6789/tcp

CMD [ "/app/nzbget", "-s", "-o", "OutputMode=log", "-c", "/config/nzbget.conf" ]
