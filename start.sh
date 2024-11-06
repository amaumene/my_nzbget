#!/usr/bin/sh

if test ! -f "/config/nzbget.conf"; then
  cp /app/nzbget.conf /config/nzbget.conf
fi

/app/nzbget -s -o OutputMode=log -c /config/nzbget.conf &
