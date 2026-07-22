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

DEFAULT_MAP = 'A:vol_up,B:vol_down,X:lock,Y:next_track'


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

RESUME_FILE = os.path.join(os.path.dirname(PID_FILE), 'pidap.resume')
CURRENT_ALBUM_FILE = os.path.join(os.path.dirname(PID_FILE), 'pidap.current_album')

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

paused = False
state_lock = threading.RLock()

album_path = ''
album_start = 0.0
total_pause_time = 0.0
pause_start = 0.0
resume_valid = False
last_play_pid = 0

_last_press = {pin: 0 for pin in BUTTONS}
DEBOUNCE = 0.15

A_PIN = BUTTONS[LABELS.index('A')]
B_PIN = BUTTONS[LABELS.index('B')]
X_PIN = BUTTONS[LABELS.index('X')]
Y_PIN = BUTTONS[LABELS.index('Y')]

COMBO_TIMEOUT = 0.5
COMBO_CLEAR = 0.5

_combo_lock = threading.Lock()
_combo_active = False
_combo_clear_timer = None


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


def read_current_album():
    data = {}
    try:
        with open(CURRENT_ALBUM_FILE, 'r') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    data[k] = v
    except Exception:
        pass
    return data.get('album', ''), float(data.get('offset', '0'))


def write_resume():
    with state_lock:
        if not album_path or not resume_valid or not paused:
            return
        offset = time.time() - album_start - total_pause_time
        if offset < 0:
            offset = 0
        try:
            with open(RESUME_FILE, 'w') as f:
                f.write(f'album={album_path}\n')
                f.write(f'offset={offset:.2f}\n')
                f.write('paused=1\n')
            log(f'Resume saved: {album_path} offset={offset:.2f}s')
        except Exception as e:
            log(f'Could not write resume file: {e}')


def delete_resume():
    try:
        if os.path.exists(RESUME_FILE):
            os.remove(RESUME_FILE)
            log('Resume file deleted')
    except Exception as e:
        log(f'Could not delete resume file: {e}')


def monitor_playback():
    global album_path, album_start, total_pause_time, paused, pause_start, resume_valid, last_play_pid
    while True:
        time.sleep(0.5)
        pid = get_play_pid()
        with state_lock:
            if pid != last_play_pid:
                last_play_pid = pid
                if pid > 0:
                    path, start_offset = read_current_album()
                    album_path = path
                    album_start = time.time() - start_offset
                    total_pause_time = 0.0
                    paused = False
                    pause_start = 0.0
                    resume_valid = True
                    delete_resume()
                    log(f'New play process: album={album_path} start_offset={start_offset} pid={pid}')


def is_paused():
    with state_lock:
        return paused


def toggle_pause():
    global paused, pause_start, total_pause_time
    pid = get_play_pid()
    if pid <= 0:
        log('No play process, cannot toggle pause')
        return
    with state_lock:
        if paused:
            kill_family(pid, signal.SIGCONT)
            paused = False
            total_pause_time += time.time() - pause_start
            delete_resume()
            log('Resumed playback')
        else:
            kill_family(pid, signal.SIGSTOP)
            paused = True
            pause_start = time.time()
            write_resume()
            log('Paused playback')


def _set_combo_active(active=True):
    global _combo_active, _combo_clear_timer
    with _combo_lock:
        _combo_active = active
        if active:
            if _combo_clear_timer:
                _combo_clear_timer.cancel()
            _combo_clear_timer = threading.Timer(COMBO_CLEAR, _set_combo_active, args=(False,))
            _combo_clear_timer.start()
        else:
            _combo_clear_timer = None


def next_album():
    global resume_valid
    log('Next album')
    if is_paused():
        toggle_pause()
    with state_lock:
        delete_resume()
        resume_valid = False
    kill_play(signal.SIGKILL)
    _set_combo_active(True)


def next_track():
    global resume_valid
    log('Next track')
    if is_paused():
        toggle_pause()
    with state_lock:
        delete_resume()
        resume_valid = False
    kill_play(signal.SIGINT)


def restart_album():
    global resume_valid
    pid = get_play_pid()
    if pid <= 0:
        log('No play process to restart')
        return
    flag_file = os.path.join(os.path.dirname(PID_FILE), 'pidap.restart')
    try:
        with open(flag_file, 'w') as f:
            f.write('1\n')
    except Exception as e:
        log(f'Could not write restart flag: {e}')
    log('Restart current album requested')
    if is_paused():
        toggle_pause()
    with state_lock:
        delete_resume()
        resume_valid = False
    kill_play(signal.SIGKILL)
    _set_combo_active(True)


def vol_button_thread(pin, func):
    start = time.time()
    while is_pressed(pin):
        if _combo_active or is_pressed(Y_PIN) or is_pressed(X_PIN):
            return
        if time.time() - start > COMBO_TIMEOUT:
            break
        time.sleep(0.02)

    if _combo_active:
        return

    if func == 'vol_up':
        run_amixer('up')
    elif func == 'vol_down':
        run_amixer('down')


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
    elif locked:
        log(f'X short press ignored (locked)')
    else:
        toggle_pause()


def handle_button(pin):
    now = time.time()
    if now - _last_press.get(pin, 0) < DEBOUNCE:
        return
    _last_press[pin] = now

    label = LABELS[BUTTONS.index(pin)]
    func = BUTTON_MAP.get(label)
    log(f'Button {label} pressed, func={func}')
    if func is None:
        return

    with lock_lock:
        if locked and func != 'lock':
            log(f'Button {label} ({func}) ignored (locked)')
            return

    if func == 'lock':
        t = threading.Thread(target=lock_thread, args=(pin,), daemon=True)
        t.start()
        return

    if func == 'next_track':
        if is_pressed(A_PIN):
            log('Y + A -> next album')
            next_album()
            return
        if is_pressed(B_PIN):
            log('Y + B -> restart album')
            restart_album()
            return
        next_track()
        return

    if func in ('vol_up', 'vol_down'):
        threading.Thread(target=vol_button_thread, args=(pin, func), daemon=True).start()
        return

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

    playback_monitor = threading.Thread(target=monitor_playback, daemon=True)
    playback_monitor.start()

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
