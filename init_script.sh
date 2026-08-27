#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PIDAP_NO_SYSTEMD=1
exec /usr/bin/perl /home/rodney/album_streamer/pidap
