#!/usr/bin/env python3
import os
import sys
import time
import signal
import subprocess
import threading
import logging

LOG_FILE = os.environ.get('PIDAP_LOG_FILE', '/tmp/pidap_buttons.log')
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    force=True,
)


def log(msg):
    print(msg, flush=True)
    logging.info(msg)

log(f'pidap_buttons.py starting, argv={sys.argv}')

try:
    import RPi.GPIO as GPIO
except ImportError as e:
    log(f'RPi.GPIO not available; button handler cannot start: {e}')
    sys.exit(1)

BUTTONS = [5, 6, 16, 24]
LABELS = ['A', 'B', 'X', 'Y']

DEFAULT_MAP = 'A:lock,B:vol_down,X:next,Y:vol_up'


def parse_map(s):
    m = {}
    for pair in s.split(','):
        if ':' not in pair:
            continue
        key, val = pair.split(':', 1)
        key = key.strip().upper()
        val = val.strip().lower()
        if key in LABELS:
            m[key] = val
    return m


BUTTON_MAP = parse_map(os.environ.get('PIDAP_BUTTON_MAP', DEFAULT_MAP))
PID_FILE = os.environ.get('PIDAP_PID_FILE')
if not PID_FILE:
    PID_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pidap.play_pid')

VOLUME_CONTROL = os.environ.get('PIDAP_VOLUME_CONTROL', '').strip() or 'Amp'
try:
    VOLUME_STEP = int(os.environ.get('PIDAP_VOLUME_STEP', '5'))
except ValueError:
    VOLUME_STEP = 5

try:
    LOCK_HOLD_SEC = float(os.environ.get('PIDAP_LOCK_HOLD_SEC', '3.0'))
except ValueError:
    LOCK_HOLD_SEC = 3.0

locked = False
lock_lock = threading.Lock()


def get_play_pid():
    try:
        with open(PID_FILE, 'r') as f:
            return int(f.read().strip().split()[0])
    except Exception:
        return 0


def check_volume_control():
    cmd = ['amixer', 'sget', VOLUME_CONTROL]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out = res.stdout.decode().strip()
        err = res.stderr.decode().strip()
        if res.returncode != 0:
            log(f'Volume control "{VOLUME_CONTROL}" not found or amixer error: {err}')
        else:
            first = out.splitlines()[0] if out else 'no output'
            log(f'Volume control OK: {cmd} -> {first}')
    except Exception as e:
        log(f'Could not check volume control: {e}')


def run_amixer(direction):
    sign = '+' if direction == 'up' else '-'
    cmd = ['amixer', 'sset', VOLUME_CONTROL, f'{VOLUME_STEP}%{sign}']
    log(f'Running: {" ".join(cmd)}')
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out = res.stdout.decode().strip()
        err = res.stderr.decode().strip()
        log(f'amixer rc={res.returncode} out={out!r} err={err!r}')
        if res.returncode != 0:
            log(f'Volume {direction} failed')
        else:
            log(f'Volume {direction} ok')
    except Exception as e:
        log(f'Volume {direction} error: {e}')


def get_children(ppid):
    children = []
    if not os.path.isdir('/proc'):
        return children
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/status') as f:
                for line in f:
                    if line.startswith('PPid:'):
                        p = int(line.split()[1])
                        if p == ppid:
                            children.append(int(pid))
                        break
        except Exception:
            pass
    return children


def kill_family(pid, sig):
    for child in get_children(pid):
        kill_family(child, sig)
    try:
        os.kill(pid, sig)
    except Exception:
        pass


def kill_play(sig=signal.SIGKILL):
    pid = get_play_pid()
    if pid <= 0:
        log('No play process')
        return
    kill_family(pid, sig)
    log(f'Killed play family starting at {pid}')


def is_pressed(pin):
    return GPIO.input(pin) == GPIO.LOW


def lock_thread(pin):
    global locked
    start = time.time()
    while is_pressed(pin):
        time.sleep(0.05)
    duration = time.time() - start
    if duration >= LOCK_HOLD_SEC:
        with lock_lock:
            locked = not locked
        log(f'Lock toggled: {"locked" if locked else "unlocked"}')
    else:
        log(f'Lock button short press ({duration:.2f}s) - no action')


def handle_button(pin):
    label = LABELS[BUTTONS.index(pin)]
    func = BUTTON_MAP.get(label)
    log(f'Button {label} pressed, func={func}')
    if func is None:
        return

    if func == 'lock':
        t = threading.Thread(target=lock_thread, args=(pin,), daemon=True)
        t.start()
        return

    with lock_lock:
        is_locked = locked

    if is_locked and func == 'next':
        log(f'Button {label} ({func}) ignored (locked)')
        return

    if func == 'next':
        log(f'Button {label}: next album')
        kill_play(signal.SIGKILL)
    elif func == 'vol_up':
        run_amixer('up')
    elif func == 'vol_down':
        run_amixer('down')
    else:
        log(f'Unknown function {func} for button {label}')


def watch_parent():
    parent = os.getppid()
    while True:
        time.sleep(1)
        if os.getppid() != parent:
            log('Parent died, exiting')
            try:
                GPIO.cleanup()
            except Exception:
                pass
            os._exit(0)


def signal_cleanup(signum, frame):
    log(f'Received signal {signum}, cleaning up')
    try:
        GPIO.cleanup()
    except Exception:
        pass
    sys.exit(0)


def main():
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(BUTTONS, GPIO.IN, pull_up_down=GPIO.PUD_UP)

    for pin in BUTTONS:
        label = LABELS[BUTTONS.index(pin)]
        func = BUTTON_MAP.get(label)
        bounce = 300 if func == 'lock' else 100
        GPIO.add_event_detect(pin, GPIO.FALLING, callback=handle_button, bouncetime=bounce)

    signal.signal(signal.SIGTERM, signal_cleanup)
    signal.signal(signal.SIGINT, signal_cleanup)

    watcher = threading.Thread(target=watch_parent, daemon=True)
    watcher.start()

    log(f'pidap button handler running, PID={os.getpid()}')
    log(f'Button map: {BUTTON_MAP}')
    check_volume_control()
    signal.pause()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log(f'Fatal error in button handler: {e}')
        try:
            GPIO.cleanup()
        except Exception:
            pass
        sys.exit(1)
