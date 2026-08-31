# Only clean up the TFT console on /dev/tty1; leave SSH untouched
if [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    export PS1=''
    export TERM=linux
    printf '\033[?25l' > /dev/tty1 2>/dev/null
fi
