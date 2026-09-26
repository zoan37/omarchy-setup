import importlib.machinery, importlib.util, sys
from evdev import ecodes as e
import os
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "a16-palm-filter")
loader = importlib.machinery.SourceFileLoader("pf", path)
spec = importlib.util.spec_from_loader("pf", loader)

class UI:
    def __init__(s): s.frames = []; s.cur = []
    def write(s, t, c, v): s.cur.append((t, c, v))
    def syn(s): s.frames.append(s.cur); s.cur = []

class Ev:
    def __init__(s, t, type, code, value): s.t, s.type, s.code, s.value = t, type, code, value
    def timestamp(s): return s.t

def fresh():
    m = importlib.util.module_from_spec(spec); loader.exec_module(m)
    m.ui = UI(); m.log = lambda msg: None
    return m

def frame(m, t, *evs):
    for ty, c, v in evs: m.pad_event(Ev(t, ty, c, v))
    m.pad_event(Ev(t, e.EV_SYN, e.SYN_REPORT, 0))

def down(m, t, slot, tid, x, y, tool=None):
    evs = [(e.EV_ABS, e.ABS_MT_SLOT, slot), (e.EV_ABS, e.ABS_MT_TRACKING_ID, tid),
           (e.EV_ABS, e.ABS_MT_POSITION_X, x), (e.EV_ABS, e.ABS_MT_POSITION_Y, y)]
    if tool is not None: evs.append((e.EV_ABS, e.ABS_MT_TOOL_TYPE, tool))
    frame(m, t, *evs)
def move(m, t, slot, x, y):
    frame(m, t, (e.EV_ABS, e.ABS_MT_SLOT, slot), (e.EV_ABS, e.ABS_MT_POSITION_X, x), (e.EV_ABS, e.ABS_MT_POSITION_Y, y))
def up(m, t, slot):
    frame(m, t, (e.EV_ABS, e.ABS_MT_SLOT, slot), (e.EV_ABS, e.ABS_MT_TRACKING_ID, -1))
def type_keys(m, t0, n, gap=0.12, hold=0.08):
    t = t0
    for i in range(n):
        m.key_event(e.KEY_A + i % 5, 1, t); m.key_event(e.KEY_A + i % 5, 0, t + hold); t += gap
    return t
def flat(m): return [x for f in m.ui.frames for x in f]
def has(m, code, value=None): return any(c == code and (value is None or v == value) for _, c, v in flat(m))
def tids(m): return [v for _, c, v in flat(m) if c == e.ABS_MT_TRACKING_ID]

ok = True
def check(name, cond):
    global ok; ok &= bool(cond); print(("PASS " if cond else "FAIL ") + name)

# 1 normal finger, no typing
m = fresh(); down(m, 100, 0, 7, 2000, 1500); move(m, 100.01, 0, 2050, 1500); up(m, 100.1, 0)
check("normal finger visible", tids(m)[0] > 0 and tids(m)[-1] == -1 and has(m, e.BTN_TOOL_FINGER, 1) and has(m, e.BTN_TOUCH, 0))
# 2 typing then palm lands mid-pad
m = fresh(); t = type_keys(m, 100, 5); down(m, t - 0.05, 0, 8, 2300, 1000); move(m, t + 0.2, 0, 2340, 1030); up(m, t + 0.4, 0)
check("palm creeping while typing hidden", m.ui.frames == [])
m = fresh(); t = type_keys(m, 100, 4); down(m, t, 0, 8, 2300, 1000); t = type_keys(m, t + 0.05, 4)
move(m, t + 0.1, 0, 2300 + 31 * 15, 1000)
check("palm sliding 15 mm between keystrokes stays hidden", m.ui.frames == [])
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 0.1, 0, 8, 2300, 1500); move(m, t + 0.15, 0, 2300 + 31 * 6, 1500)
check("reach after typing: 6 mm still hidden", m.ui.frames == [])
move(m, t + 0.2, 0, 2300 + 31 * 12, 1500)
check("reach after typing: 12 mm shown", tids(m) and tids(m)[0] > 0)
# 3 recent (0.8 s after typing): tap swallowed, moving finger promoted
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 0.8, 0, 9, 2300, 1500); up(m, t + 0.9, 0)
check("tap soon after typing swallowed", m.ui.frames == [])
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 0.8, 0, 9, 2300, 1500); move(m, t + 0.85, 0, 2300 + 31 * 5, 1500)
check("move soon after typing promoted", tids(m) and tids(m)[0] > 0)
# 4 held game key does not mute
m = fresh(); m.key_event(e.KEY_W, 1, 100); down(m, 100.5, 0, 10, 2300, 1500); move(m, 100.51, 0, 2310, 1500)
m.key_event(e.KEY_W, 0, 102)
check("held W: finger visible immediately", tids(m) and tids(m)[0] > 0)
m = fresh(); m.key_event(e.KEY_W, 1, 100); m.key_event(e.KEY_W, 0, 101); m.key_event(e.KEY_A, 1, 101.02)
down(m, 101.05, 0, 10, 2300, 1500); move(m, 101.06, 0, 2310, 1500)
check("WASD holds then touch: visible", tids(m) and tids(m)[0] > 0)
# 5 resting finger demoted during typing, re-promoted on movement
m = fresh(); down(m, 100, 0, 11, 2300, 1500)
for i in range(20): move(m, 100.1 + i * 0.05, 0, 2300 + (i % 2), 1500)
t = type_keys(m, 101.2, 6)
for i in range(10): move(m, t + i * 0.05, 0, 2300 + (i % 2), 1500)
check("resting finger hidden once typing", tids(m) == [tids(m)[0], -1])
move(m, t + 1, 0, 2300 + 31 * 6, 1500)
check("resting finger re-shown after moving", len(tids(m)) == 3 and tids(m)[2] > 0 and tids(m)[2] != tids(m)[0])
# 6 slot reuse with only X sent
m = fresh(); down(m, 100, 0, 12, 2000, 1500); up(m, 100.1, 0)
frame(m, 101, (e.EV_ABS, e.ABS_MT_SLOT, 0), (e.EV_ABS, e.ABS_MT_TRACKING_ID, 13), (e.EV_ABS, e.ABS_MT_POSITION_X, 2100))
check("slot reuse carries Y", len([v for v in tids(m) if v > 0]) == 2 and (e.EV_ABS, e.ABS_MT_POSITION_Y, 1500) in flat(m)[-12:])
# 7 two fingers
m = fresh(); down(m, 100, 0, 14, 2000, 1500); down(m, 100.02, 1, 15, 2600, 1500)
check("two fingers -> DOUBLETAP", has(m, e.BTN_TOOL_DOUBLETAP, 1))
# 8 hardware palm
m = fresh(); down(m, 100, 0, 16, 2300, 1500, tool=2); move(m, 100.1, 0, 2400, 1500)
check("hw palm hidden", m.ui.frames == [])
# 9 edge contact in session needs 8 mm
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 2, 0, 17, 100, 1500); move(m, t + 2.1, 0, 100 + 31 * 5, 1500)
check("edge contact 5 mm: still hidden", m.ui.frames == [])
move(m, t + 2.2, 0, 100 + 31 * 9, 1500)
check("edge contact 9 mm: shown", tids(m) and tids(m)[0] > 0)
# 10 pending then keystroke -> palm for life
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 0.8, 0, 18, 2300, 1500); type_keys(m, t + 0.9, 1)
move(m, t + 1.0, 0, 2300 + 31 * 10, 1500)
check("pending + keystroke -> palm", m.ui.frames == [])
# 11 physical click promotes pending
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 0.8, 0, 19, 2300, 2500); frame(m, t + 0.9, (e.EV_KEY, e.BTN_LEFT, 1))
check("click promotes pending", has(m, e.BTN_LEFT, 1) and tids(m) and tids(m)[0] > 0)
# 12 palm hidden but real finger alongside still works (typing palm + later finger)
m = fresh(); t = type_keys(m, 100, 5); down(m, t + 0.1, 0, 20, 300, 400); down(m, t + 3.5, 1, 21, 2300, 1500)
move(m, t + 3.6, 1, 2400, 1500)
check("finger works while palm rests", tids(m) and tids(m)[0] > 0 and not has(m, e.BTN_TOOL_DOUBLETAP, 1))
# 13 ctrl held: contact passes even while typing
m = fresh(); t = type_keys(m, 100, 5); m.key_event(e.KEY_LEFTCTRL, 1, t); down(m, t + 0.05, 0, 22, 2300, 1500)
check("ctrl+touch passes", tids(m) and tids(m)[0] > 0)
print("ALL PASS" if ok else "SOME FAILED")
