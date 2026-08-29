\
#!/usr/bin/env python3
import os, sys, zipfile, tempfile, shutil

def _ensure_sounddevice_portaudio_filesystem():
    zip_paths = [p for p in sys.path if p and p.endswith(".zip") and os.path.basename(p).startswith("python")]
    if not zip_paths:
        return
    pyzip = zip_paths[0]
    try:
        with zipfile.ZipFile(pyzip, "r") as z:
            prefix = "_sounddevice_data/"
            want = [n for n in z.namelist() if n.startswith(prefix)]
            if not want:
                return
            outdir = os.path.join(tempfile.gettempdir(), "lidaccordion_sounddevice_data")
            if os.path.exists(outdir):
                shutil.rmtree(outdir, ignore_errors=True)
            os.makedirs(outdir, exist_ok=True)
            for n in want:
                if not n.endswith("/"):
                    z.extract(n, outdir)
            sys.path.insert(0, outdir)
    except Exception:
        pass

_ensure_sounddevice_portaudio_filesystem()

import glob
import math
import subprocess
import time
import threading
from dataclasses import dataclass
import numpy as np
import pygame
import pygame.freetype
from pygame import gfxdraw
import sounddevice as sd

APP_ICON_RELATIVE_PATH = os.path.join("assets", "MacbookAccordion-AppIcon.png")

def resource_path(relative_path: str) -> str:
    """Return a resource path that works both from source and a py2app bundle."""
    if getattr(sys, "frozen", False):
        resources_dir = os.path.normpath(
            os.path.join(os.path.dirname(sys.executable), "..", "Resources")
        )
        return os.path.join(resources_dir, relative_path)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), relative_path)

def try_read_lid_angle():
    try:
        from pybooklid import read_lid_angle
        a = read_lid_angle()
        if a is None:
            return False, None
        return True, float(a)
    except Exception:
        return False, None

SAMPLE_RATE = 44100
BLOCK_SIZE = 256

NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
def midi_to_name(m: int) -> str:
    m = int(max(0, min(127, m)))
    n = NOTE_NAMES[m % 12]
    o = (m // 12) - 1
    return f"{n}{o}"

def midi_to_freq(midi: int) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))

@dataclass
class Param:
    key: str
    label: str
    value: float
    minv: float
    maxv: float
    step: float
    fmt: str
    group: str
    inverted: bool = False

    def clamp(self):
        if self.value < self.minv: self.value = self.minv
        if self.value > self.maxv: self.value = self.maxv

class PolyAccordionSynth:
    def __init__(self):
        self.voices = {}
        self.held = set()
        self.bellows = 0.0
        self.master = 0.30       # 5 音和弦也不削波（0.45 时 10% 采样被硬削）
        self.attack = 0.020      # 簧片起音
        self.release = 0.120
        self.detune = 0.005      # 中音区约 4Hz 拍频，湿而不吵
        self.noise_amount = 0.008
        self._lock = threading.Lock()

    def set_bellows(self, bellows: float):
        with self._lock:
            self.bellows = float(max(0.0, min(1.0, bellows)))

    def note_on(self, voice_key: str, midi: int):
        with self._lock:
            self.held.add(voice_key)
            if voice_key not in self.voices:
                self.voices[voice_key] = {"freq": midi_to_freq(midi), "p1": 0.0, "p2": 0.0, "env": 0.0}
            else:
                self.voices[voice_key]["freq"] = midi_to_freq(midi)

    def note_off(self, voice_key: str):
        with self._lock:
            self.held.discard(voice_key)

    def retune(self, voice_key: str, midi: int):
        with self._lock:
            v = self.voices.get(voice_key)
            if v is not None:
                v["freq"] = midi_to_freq(midi)

    def generate_frames(self, frames: int) -> np.ndarray:
        out = np.zeros(frames, dtype=np.float32)
        with self._lock:
            held = set(self.held)
            bellows = self.bellows
            voices_snapshot = list(self.voices.items())
            master = self.master
            attack = self.attack
            release = self.release
            detune = self.detune
            noise_amount = self.noise_amount

        idx = np.arange(frames, dtype=np.float32)
        att_step = 1.0 / max(1e-6, attack * SAMPLE_RATE)
        rel_step = 1.0 / max(1e-6, release * SAMPLE_RATE)

        remove = []
        updated = {}
        for k, v in voices_snapshot:
            f = v["freq"]
            p1, p2, e = v["p1"], v["p2"], v["env"]

            if k in held:
                e_end = min(1.0, e + att_step * frames)
                env = np.linspace(e, e_end, frames, dtype=np.float32)
            else:
                e_end = max(0.0, e - rel_step * frames)
                env = np.linspace(e, e_end, frames, dtype=np.float32)

            if e_end <= 0.0 and k not in held:
                remove.append(k)
                continue

            f1, f2 = f * (1.0 - detune), f * (1.0 + detune)
            inc1, inc2 = f1 / SAMPLE_RATE, f2 / SAMPLE_RATE
            ph1 = (p1 + inc1 * idx) % 1.0
            ph2 = (p2 + inc2 * idx) % 1.0

            saw1 = 2.0 * ph1 - 1.0
            saw2 = 2.0 * ph2 - 1.0
            sig = 0.6 * saw1 + 0.4 * saw2
            sig = np.tanh(1.6 * sig)

            out += sig * env

            updated[k] = {
                "freq": f,
                "p1": float((p1 + inc1 * frames) % 1.0),
                "p2": float((p2 + inc2 * frames) % 1.0),
                "env": float(e_end),
            }

        with self._lock:
            for k, nv in updated.items():
                current = self.voices.get(k)
                if current is not None:
                    nv["freq"] = current.get("freq", nv["freq"])
                self.voices[k] = nv
            for k in remove:
                if k not in self.held:
                    self.voices.pop(k, None)
            bellows = self.bellows

        if bellows > 0.0 and noise_amount > 0.0:
            out += (np.random.randn(frames).astype(np.float32) * noise_amount) * (bellows * 0.7)

        out *= (master * bellows)
        return np.clip(out, -1.0, 1.0).astype(np.float32)

# --- Key mapping ---
WHITE_Q = [(pygame.K_q, 60),(pygame.K_w, 62),(pygame.K_e, 64),(pygame.K_r, 65),(pygame.K_t, 67),
           (pygame.K_y, 69),(pygame.K_u, 71),(pygame.K_i, 72),(pygame.K_o, 74),(pygame.K_p, 76)]
BLACK_1 = [(pygame.K_1, 61),(pygame.K_2, 63),(pygame.K_4, 66),(pygame.K_5, 68),(pygame.K_6, 70),
           (pygame.K_8, 73),(pygame.K_9, 75),(pygame.K_0, 78)]
WHITE_Z = [(pygame.K_z, 72),(pygame.K_x, 74),(pygame.K_c, 76),(pygame.K_v, 77),(pygame.K_b, 79),
           (pygame.K_n, 81),(pygame.K_m, 83),(pygame.K_COMMA, 84),(pygame.K_PERIOD, 86),(pygame.K_SLASH, 88)]
BLACK_A = [(pygame.K_a, 73),(pygame.K_s, 75),(pygame.K_d, 78),(pygame.K_f, 80),(pygame.K_g, 82),
           (pygame.K_h, 85),(pygame.K_j, 87),(pygame.K_k, 90),(pygame.K_l, 92),(pygame.K_SEMICOLON, 94)]
KEY_TO_MIDI = {k: m for k, m in (WHITE_Q + BLACK_1 + WHITE_Z + BLACK_A)}
def voice_key(kconst: int) -> str:
    return f"K_{kconst}"


# ---------------- appearance ----------------
def _dark_mode() -> bool:
    try:
        out = subprocess.run(["defaults", "read", "-g", "AppleInterfaceStyle"],
                             capture_output=True, text=True, timeout=1.0)
        return "Dark" in out.stdout
    except Exception:
        return False

LIGHT = {
    "bg": (242, 242, 247), "toolbar": (250, 250, 252), "card": (255, 255, 255),
    "chip": (234, 234, 240), "chip_down": (214, 214, 222), "text": (28, 28, 30), "text2": (124, 124, 130),
    "text3": (168, 168, 176), "sep": (226, 226, 231), "track": (206, 206, 212),
    "accent": (0, 122, 255), "knob": (255, 255, 255), "knob_edge": (0, 0, 0, 40),
    "shadow": (0, 0, 0, 46), "key_w": (255, 255, 255), "key_line": (219, 219, 226),
    "key_b": (52, 52, 58), "key_w_text": (150, 150, 158), "key_b_text": (198, 198, 206),
    "live": (52, 199, 89), "sim": (255, 159, 10), "scroll": (0, 0, 0, 55),
}
DARK = {
    "bg": (22, 22, 24), "toolbar": (32, 32, 35), "card": (38, 38, 41),
    "chip": (58, 58, 63), "chip_down": (78, 78, 84), "text": (245, 245, 247), "text2": (146, 146, 153),
    "text3": (108, 108, 116), "sep": (56, 56, 60), "track": (72, 72, 78),
    "accent": (10, 132, 255), "knob": (250, 250, 252), "knob_edge": (0, 0, 0, 90),
    "shadow": (0, 0, 0, 110), "key_w": (222, 222, 229), "key_line": (140, 140, 150),
    "key_b": (26, 26, 30), "key_w_text": (108, 108, 118), "key_b_text": (172, 172, 180),
    "live": (48, 209, 88), "sim": (255, 159, 10), "scroll": (255, 255, 255, 60),
}

# ---------------- typography (SF Pro for latin, PingFang SC for CJK) ----------------
_PF = glob.glob("/System/Library/AssetsV2/*/*/AssetData/PingFang.ttc")
CJK_FACE = (_PF[0], {400: 3, 500: 7, 600: 11}) if _PF else \
           ("/System/Library/Fonts/Hiragino Sans GB.ttc", {400: 0, 500: 1, 600: 1})
LATIN_FACE = ("/System/Library/Fonts/SFNS.ttf", {400: 4 << 16, 500: 5 << 16, 600: 6 << 16})

class Type:
    def __init__(self):
        self._faces = {}
        self._cache = {}

    def _face(self, cjk: bool, size: int, weight: int):
        path, table = CJK_FACE if cjk else LATIN_FACE
        key = (path, table[weight], size)
        f = self._faces.get(key)
        if f is None:
            f = pygame.freetype.Font(path, size, font_index=table[weight])
            f.origin = True
            self._faces[key] = f
        return f

    @staticmethod
    def _runs(text: str):
        runs, buf, cur = [], [], None
        for ch in text:
            cjk = ord(ch) > 0x2E7F
            if cur is None:
                cur = cjk
            if cjk != cur:
                runs.append((cur, "".join(buf)))
                buf, cur = [], cjk
            buf.append(ch)
        if buf:
            runs.append((bool(cur), "".join(buf)))
        return runs

    def render(self, text: str, size: int, weight: int, color) -> pygame.Surface:
        key = (text, size, weight, tuple(color))
        surf = self._cache.get(key)
        if surf is None:
            if len(self._cache) > 2400:
                self._cache.clear()
            surf = self._build(text, size, weight, color)
            self._cache[key] = surf
        return surf

    def _build(self, text, size, weight, color):
        parts = [(self._face(cjk, size, weight), t) for cjk, t in self._runs(text)]
        if not parts:
            return pygame.Surface((1, size), pygame.SRCALPHA)
        asc = max(f.get_sized_ascender() for f, _ in parts)
        desc = min(f.get_sized_descender() for f, _ in parts)
        widths = [sum(m[4] for m in f.get_metrics(t) if m) for f, t in parts]
        surf = pygame.Surface((max(1, int(sum(widths)) + 2), asc - desc + 2), pygame.SRCALPHA)
        x = 0.0
        for (f, t), w in zip(parts, widths):
            f.render_to(surf, (int(round(x)), asc + 1), t, color)
            x += w
        return surf

TY = Type()

# 布局/命中判定一律用逻辑点，只有真正落笔时才乘 S（Retina 上 S=2）
S = 1

def text(dst, s, x, y, size, weight=400, color=(0, 0, 0), align="left", vcenter=False):
    surf = TY.render(s, size * S, weight, color)
    w, h = surf.get_size()
    x, y = x * S, y * S
    if align == "right":
        x -= w
    elif align == "center":
        x -= w // 2
    if vcenter:
        y -= h // 2
    dst.blit(surf, (int(x), int(y)))

def text_w(s, size, weight=400):
    return TY.render(s, size * S, weight, (0, 0, 0)).get_width() / S

# ---------------- antialiased primitives ----------------
_RR = {}

def rr_surface(w, h, radius, color):
    key = (w, h, radius, tuple(color))
    surf = _RR.get(key)
    if surf is None:
        if len(_RR) > 160:
            _RR.clear()
        s = 3 if S == 1 else 2
        big = pygame.Surface((w * s, h * s), pygame.SRCALPHA)
        pygame.draw.rect(big, color, (0, 0, w * s, h * s), border_radius=radius * s)
        surf = pygame.transform.smoothscale(big, (w, h))
        _RR[key] = surf
    return surf

def rr(dst, rect, radius, color):
    if rect.w <= 0 or rect.h <= 0:
        return
    dst.blit(rr_surface(rect.w * S, rect.h * S, radius * S, color), (rect.x * S, rect.y * S))

def capsule(dst, x, y, w, h, color):
    """Rounded-end bar built from two cached caps plus a plain middle."""
    if w <= 0:
        return
    x, y, w, h = int(x * S), int(y * S), int(max(w, h) * S), int(h * S)
    r = h // 2
    cap = rr_surface(h, h, r, color)
    dst.blit(cap, (x, y), area=(0, 0, r, h))
    dst.blit(cap, (x + w - (h - r), y), area=(r, 0, h - r, h))
    if w > h:
        pygame.draw.rect(dst, color, (x + r, y, w - h, h))

def knob(dst, x, y, r, th):
    x, y, r = int(x * S), int(y * S), int(r * S)
    gfxdraw.filled_circle(dst, x, y + S, r, th["shadow"])
    gfxdraw.filled_circle(dst, x, y, r, th["knob"])
    gfxdraw.aacircle(dst, x, y, r, th["knob"])
    gfxdraw.aacircle(dst, x, y, r, th["knob_edge"])

def dot(dst, x, y, r, color):
    x, y, r = int(x * S), int(y * S), int(r * S)
    gfxdraw.filled_circle(dst, x, y, r, color)
    gfxdraw.aacircle(dst, x, y, r, color)

def box(dst, x, y, w, h, color, bl=0, br=0):
    pygame.draw.rect(dst, color, (int(x * S), int(y * S), int(w * S), int(h * S)),
                     border_bottom_left_radius=int(bl * S), border_bottom_right_radius=int(br * S))

def hairline(dst, x, y, w, color):
    """真·发丝线：永远 1 个物理像素"""
    dst.fill(color, (int(x * S), int(y * S), int(w * S), 1))

# ---------------- widgets ----------------
class Slider:
    R = 9

    def __init__(self, param: Param):
        self.p = param
        self.base_y = 0
        self.rect = pygame.Rect(0, 0, 200, 26)
        self.drag = False

    def set_base_pos(self, x, y, w, h):
        self.rect.x, self.rect.w, self.rect.h = x, w, h
        self.base_y = y

    def apply_scroll(self, scroll_y: int):
        self.rect.y = self.base_y + scroll_y

    def handle_event(self, e):
        if e.type == pygame.MOUSEBUTTONDOWN and e.button == 1:
            if self.rect.inflate(0, 8).collidepoint(e.pos):
                self.drag = True
                self._set_from_mouse(e.pos[0])
                return True
        elif e.type == pygame.MOUSEBUTTONUP and e.button == 1:
            self.drag = False
        elif e.type == pygame.MOUSEMOTION and self.drag:
            self._set_from_mouse(e.pos[0])
            return True
        return False

    def _set_from_mouse(self, mx):
        t = clamp((mx - self.rect.x) / max(1, self.rect.w), 0.0, 1.0)
        if self.p.inverted:
            t = 1.0 - t
        v = self.p.minv + t * (self.p.maxv - self.p.minv)
        if self.p.step > 0:
            v = round(v / self.p.step) * self.p.step
        self.p.value = float(v)
        self.p.clamp()

    def draw(self, dst, th, clip_rect):
        if not self.rect.colliderect(clip_rect):
            return
        r = self.rect
        cy = r.centery
        span = self.p.maxv - self.p.minv
        t = clamp((self.p.value - self.p.minv) / span, 0.0, 1.0) if span > 0 else 0.0
        if self.p.inverted:
            t = 1.0 - t
        capsule(dst, r.x, cy - 2, r.w, 4, th["track"])
        fill = int(r.w * t)
        if fill > 0:
            capsule(dst, r.x, cy - 2, fill, 4, th["accent"])
        knob(dst, r.x + fill, cy, self.R, th)

class Button:
    """圆角小按钮：按下时变深，松手才触发"""

    def __init__(self, label, size=12, weight=500, tinted=False, pad=14, h=24):
        self.label = label
        self.size = size
        self.weight = weight
        self.tinted = tinted
        self.pad = pad
        self.rect = pygame.Rect(0, 0, 0, 0)
        self.down = False
        self.selected = False

    def measure(self):
        return int(text_w(self.label, self.size, self.weight)) + self.pad * 2

    def place(self, x, y, h=24):
        self.rect = pygame.Rect(x, y, self.measure(), h)
        return self.rect

    def handle_event(self, e):
        if e.type == pygame.MOUSEBUTTONDOWN and e.button == 1 and self.rect.collidepoint(e.pos):
            self.down = True
            return True
        if e.type == pygame.MOUSEBUTTONUP and e.button == 1:
            fired = self.down and self.rect.collidepoint(e.pos)
            self.down = False
            return "fire" if fired else False
        return False

    def draw(self, dst, th):
        if self.selected:
            bg = th["accent"]
            fg = (255, 255, 255)
        else:
            bg = th["chip_down"] if self.down else th["chip"]
            fg = th["accent"] if self.tinted else th["text"]
        rr(dst, self.rect, self.rect.h // 2, bg)
        text(dst, self.label, self.rect.centerx, self.rect.centery, self.size, self.weight,
             fg, align="center", vcenter=True)

class ScrollBar:
    def __init__(self):
        self.drag = False
        self.grab_off = 0

    def handle_event(self, e, bar_rect, knob_rect):
        if e.type == pygame.MOUSEBUTTONDOWN and e.button == 1:
            if knob_rect.collidepoint(e.pos):
                self.drag = True
                self.grab_off = e.pos[1] - knob_rect.y
                return True
            if bar_rect.collidepoint(e.pos):
                return "jump"
        elif e.type == pygame.MOUSEBUTTONUP and e.button == 1:
            self.drag = False
        elif e.type == pygame.MOUSEMOTION and self.drag:
            return "drag"
        return False

def clamp(v, a, b):
    return a if v < a else b if v > b else v

# ---------------- keyboard map for the on-screen piano ----------------
MIDI_LO, MIDI_HI = 60, 95
WHITE_PC = (0, 2, 4, 5, 7, 9, 11)
WHITE_MIDI = [m for m in range(MIDI_LO, MIDI_HI + 1) if m % 12 in WHITE_PC]
BLACK_MIDI = [m for m in range(MIDI_LO, MIDI_HI + 1) if m % 12 not in WHITE_PC]

def _caps():
    out = {}
    for kconst, midi in (WHITE_Q + BLACK_1 + WHITE_Z + BLACK_A):
        name = pygame.key.name(kconst).upper()
        out.setdefault(midi, []).append(name)
    return {m: "/".join(v) for m, v in out.items()}

# ---------------- layout metrics ----------------
TOOLBAR_H = 56
COL_MAX = 780
MARGIN = 24
CARD_R = 12
CARD_A_H = 156
CARD_B_H = 128
HERO_H = 14 + CARD_A_H + 12 + CARD_B_H + 18
SCROLL_TOP = TOOLBAR_H + HERO_H
ROW_H = 48
HEAD_H = 34
SEC_GAP = 22
SCROLL_STEP = 48
LABEL_W = 138
VALUE_W = 74

class Display:
    """pygame-ce 下用 allow_high_dpi 窗口拿到 1:1 的 Retina 画布；上游 pygame 退回 1x。"""

    def __init__(self, size, title, icon):
        if hasattr(pygame, "Window"):
            # 在创建窗口前先预设图标，再以隐藏状态创建窗口。这样 Dock 从窗口出现的
            # 第一帧开始就是应用图标，不会先闪出 pygame_icon_mac.bmp。
            if icon is not None:
                pygame.display.set_icon(icon)
            self.win = pygame.Window(
                title, size, resizable=True, allow_high_dpi=True, hidden=True
            )
            if icon is not None:
                self.win.set_icon(icon)
            self.surface = self.win.get_surface()
            self.win.show()
        else:
            self.win = None
            if icon is not None:
                pygame.display.set_icon(icon)
            self.surface = pygame.display.set_mode(size, pygame.RESIZABLE | pygame.DOUBLEBUF)
            pygame.display.set_caption(title)
        self.scale = max(1, round(self.surface.get_width() / max(1, self.size[0])))

    @property
    def size(self):
        return tuple(self.win.size) if self.win else self.surface.get_size()

    def resized(self):
        if self.win:
            self.surface = self.win.get_surface()
        else:
            self.surface = pygame.display.set_mode(self.size, pygame.RESIZABLE | pygame.DOUBLEBUF)
        return self.surface

    def flip(self):
        if self.win:
            self.win.flip()
        else:
            pygame.display.flip()

INFO_ROWS = [("屏幕控制", "sensor"), ("声音输出", "audio"),
             ("音高调整", "octave"), ("试玩方式", "sim")]

def main():
    pygame.init()
    pygame.freetype.init()
    W, H = 940, 800
    global S
    try:
        icon = pygame.image.load(resource_path(APP_ICON_RELATIVE_PATH))
    except (FileNotFoundError, pygame.error) as e:
        icon = None
        print("无法加载应用图标:", e)
    disp = Display((W, H), "MacbookAccordion", icon)
    S = disp.scale
    screen = disp.surface
    clock = pygame.time.Clock()
    th = DARK if _dark_mode() else LIGHT
    caps = _caps()

    synth = PolyAccordionSynth()
    held = {}
    octave_off = 0

    def clamp_oct(off: int) -> int:
        return max(-36, min(36, off))

    def retune_all():
        for _, (vk, base_midi) in held.items():
            synth.retune(vk, max(0, min(127, base_midi + octave_off)))

    ok, angle = try_read_lid_angle()
    simulated = not ok
    angle_sim = 45.0
    prev_angle = angle if ok else angle_sim
    prev_t = time.time()

    params = [
        Param("master",    "音量",             synth.master, 0.05, 1.20, 0.01, ".2f", "轻松设置"),
        Param("vel_max",   "开合灵敏度",       160.0, 30.0, 400.0, 1.0,  ".0f", "轻松设置", True),
        Param("fill_rate", "进气速度",          2.2,   0.1,  8.0,   0.1,  ".1f", "开合细节"),
        Param("leak_rate", "漏气速度",          0.12,  0.00, 2.0,   0.01, ".2f", "开合细节"),
        Param("deadzone",  "微小动作过滤",      0.010, 0.000, 0.080, 0.001, ".3f", "开合细节"),
        Param("rise_a",    "力度上升平滑度",    0.70,  0.00, 0.99,  0.01, ".2f", "开合细节"),
        Param("fall_a",    "力度下降平滑度",    0.96,  0.00, 0.999, 0.001,".3f", "开合细节"),
        Param("attack_s",  "起音时间（秒）",    synth.attack, 0.001,0.200,0.001,".3f", "声音细节"),
        Param("release_s", "释音时间（秒）",    synth.release,0.010,1.000,0.005,".3f", "声音细节"),
        Param("detune",    "簧片厚度（失谐）",  synth.detune, 0.000,0.050,0.001,".3f", "声音细节"),
        Param("noise",     "气流与簧片噪声",    synth.noise_amount,0.000,0.080,0.001,".3f", "声音细节"),
    ]
    by_key = {p.key: p for p in params}
    defaults = {p.key: p.value for p in params}

    sound_presets = {
        "经典": {"attack_s": 0.020, "release_s": 0.120, "detune": 0.005, "noise": 0.008},
        "柔和": {"attack_s": 0.045, "release_s": 0.280, "detune": 0.003, "noise": 0.003},
        "明亮": {"attack_s": 0.008, "release_s": 0.080, "detune": 0.002, "noise": 0.004},
        "搞怪": {"attack_s": 0.015, "release_s": 0.200, "detune": 0.022, "noise": 0.025},
    }
    sound_keys = set(next(iter(sound_presets.values())))
    sound_style = "经典"
    advanced_open = False

    def apply_synth_params():
        synth.master = by_key["master"].value
        synth.attack = by_key["attack_s"].value
        synth.release = by_key["release_s"].value
        synth.detune = by_key["detune"].value
        synth.noise_amount = by_key["noise"].value

    sliders = {p.key: Slider(p) for p in params}
    btn_reset = Button("恢复默认", tinted=True)
    btn_more = Button("更多设置")
    btn_oct_down = Button("−", size=14, weight=600, pad=10)
    btn_oct_up = Button("+", size=14, weight=600, pad=10)
    preset_buttons = {name: Button(name, pad=15, h=28) for name in sound_presets}
    preset_buttons[sound_style].selected = True
    buttons = (btn_reset, btn_more, btn_oct_down, btn_oct_up, *preset_buttons.values())
    scrollbar = ScrollBar()
    cursor_hand = False

    def choose_sound_style(name):
        nonlocal sound_style
        sound_style = name
        for key, value in sound_presets[name].items():
            by_key[key].value = value
        for label, button in preset_buttons.items():
            button.selected = label == name

    scroll_y = 0
    content_h = 0
    panel = []
    col_x, col_w = MARGIN, COL_MAX

    def layout(win_w, win_h):
        nonlocal content_h, scroll_y, panel, col_x, col_w
        col_w = max(360, min(COL_MAX, win_w - 2 * MARGIN))
        col_x = (win_w - col_w) // 2
        panel = []
        y = SCROLL_TOP + 14

        easy_params = [by_key["master"], by_key["vel_max"]]
        card = pygame.Rect(col_x, y + HEAD_H, col_w, ROW_H * 3)
        rows = []
        for i, p in enumerate(easy_params):
            s = sliders[p.key]
            sx = col_x + 20 + LABEL_W
            sw = max(90, col_w - 20 - LABEL_W - VALUE_W - 20 - 14)
            s.set_base_pos(sx, card.y + i * ROW_H + (ROW_H - 26) // 2, sw, 26)
            rows.append(("slider", p, s))
        preset_y = card.y + 2 * ROW_H + (ROW_H - 28) // 2
        preset_x = col_x + 20 + LABEL_W
        for button in preset_buttons.values():
            button.place(preset_x, preset_y, h=28)
            preset_x = button.rect.right + 8
        rows.append(("preset", "声音风格", preset_buttons))
        panel.append({"title": "轻松设置", "head_y": y, "card": card, "rows": rows})
        y = card.bottom + SEC_GAP

        advanced_groups = ("开合细节", "声音细节") if advanced_open else ()
        for group in advanced_groups:
            group_params = [p for p in params if p.group == group]
            card = pygame.Rect(col_x, y + HEAD_H, col_w, ROW_H * len(group_params))
            rows = []
            for i, p in enumerate(group_params):
                s = sliders[p.key]
                sx = col_x + 20 + LABEL_W
                sw = max(90, col_w - 20 - LABEL_W - VALUE_W - 20 - 14)
                s.set_base_pos(sx, card.y + i * ROW_H + (ROW_H - 26) // 2, sw, 26)
                rows.append(("slider", p, s))
            panel.append({"title": group, "head_y": y, "card": card, "rows": rows})
            y = card.bottom + SEC_GAP

        if advanced_open:
            card = pygame.Rect(col_x, y + HEAD_H, col_w, ROW_H * len(INFO_ROWS))
            panel.append({"title": "状态与按键", "head_y": y, "card": card,
                          "rows": [("info", lbl, key) for lbl, key in INFO_ROWS]})
            y = card.bottom
        content_h = (y + 24) - SCROLL_TOP
        view_h = max(80, win_h - SCROLL_TOP)
        scroll_y = int(clamp(scroll_y, min(0, view_h - content_h), 0))

    def apply_scroll():
        for s in sliders.values():
            s.apply_scroll(scroll_y)

    def set_scroll_from_ratio(r, win_h):
        nonlocal scroll_y
        view_h = max(80, win_h - SCROLL_TOP)
        scroll_y = int(round(min(0, view_h - content_h) * r))
        apply_scroll()

    layout(W, H)
    apply_scroll()

    air = 0.0
    bellows = 0.0
    vel = 0.0

    audio_ok = True
    stream = None

    def audio_callback(outdata, frames, time_info, status):
        outdata[:, 0] = synth.generate_frames(frames)

    try:
        stream = sd.OutputStream(samplerate=SAMPLE_RATE, blocksize=BLOCK_SIZE, channels=1,
                                 dtype="float32", callback=audio_callback)
        stream.start()
    except Exception as e:
        audio_ok = False
        print("Failed to start audio OutputStream:", e)

    running = True
    while running:
        dt = clock.tick(60) / 1000.0
        now = time.time()
        win_w, win_h = disp.size

        apply_synth_params()

        view_h = max(80, win_h - SCROLL_TOP)
        max_scroll_down = min(0, view_h - content_h)
        scrollable = content_h > view_h

        bar_rect = pygame.Rect(win_w - 13, SCROLL_TOP + 8, 6, max(60, view_h - 16))
        if scrollable:
            r = clamp(scroll_y / max_scroll_down if max_scroll_down else 0.0, 0.0, 1.0)
            knob_h = max(48, int(bar_rect.h * (view_h / content_h)))
            knob_rect = pygame.Rect(bar_rect.x, int(bar_rect.y + (bar_rect.h - knob_h) * r),
                                    bar_rect.w, knob_h)
        else:
            knob_rect = bar_rect.copy()

        for event in pygame.event.get():
            if event.type in (pygame.QUIT, pygame.WINDOWCLOSE):
                running = False
            elif event.type in (pygame.VIDEORESIZE, pygame.WINDOWRESIZED):
                screen = disp.resized()
                layout(*disp.size)
                apply_scroll()

            hit_button = False
            for b in buttons:
                r = b.handle_event(event)
                if r == "fire":
                    if b is btn_reset:
                        for prm in params:
                            prm.value = defaults[prm.key]
                        choose_sound_style("经典")
                        advanced_open = False
                        btn_more.label = "更多设置"
                        octave_off = 0
                        retune_all()
                        angle_sim = 45.0
                        scroll_y = 0
                        layout(win_w, win_h)
                        apply_scroll()
                    elif b is btn_more:
                        advanced_open = not advanced_open
                        btn_more.label = "收起设置" if advanced_open else "更多设置"
                        scroll_y = 0
                        layout(win_w, win_h)
                        apply_scroll()
                    elif b is btn_oct_down:
                        octave_off = clamp_oct(octave_off - 12); retune_all()
                    elif b is btn_oct_up:
                        octave_off = clamp_oct(octave_off + 12); retune_all()
                    else:
                        for label, button in preset_buttons.items():
                            if b is button:
                                choose_sound_style(label)
                                break
                if r:
                    hit_button = True
            if hit_button:
                continue

            if scrollable:
                sb = scrollbar.handle_event(event, bar_rect.inflate(12, 0), knob_rect.inflate(12, 0))
                if sb:
                    if sb == "jump" and event.type == pygame.MOUSEBUTTONDOWN:
                        t = clamp((event.pos[1] - bar_rect.y) / max(1, bar_rect.h), 0.0, 1.0)
                        set_scroll_from_ratio(t, win_h)
                    elif sb == "drag" and event.type == pygame.MOUSEMOTION:
                        ky = event.pos[1] - scrollbar.grab_off
                        t = clamp((ky - bar_rect.y) / max(1, bar_rect.h - knob_rect.h), 0.0, 1.0)
                        set_scroll_from_ratio(t, win_h)
                    continue

            if event.type == pygame.MOUSEWHEEL and scrollable:
                if pygame.mouse.get_pos()[1] >= SCROLL_TOP:
                    scroll_y = int(clamp(scroll_y + event.y * SCROLL_STEP, max_scroll_down, 0))
                    apply_scroll()
                    continue

            if event.type in (pygame.MOUSEBUTTONDOWN, pygame.MOUSEBUTTONUP, pygame.MOUSEMOTION):
                if event.type == pygame.MOUSEBUTTONDOWN and event.pos[1] < SCROLL_TOP:
                    continue
                used = False
                for key, s in sliders.items():
                    if s.handle_event(event):
                        if key in sound_keys:
                            sound_style = "自定义"
                            for button in preset_buttons.values():
                                button.selected = False
                        used = True
                if used:
                    continue

            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                if simulated:
                    if event.key == pygame.K_UP:
                        angle_sim = min(110.0, angle_sim + 3.0)
                    elif event.key == pygame.K_DOWN:
                        angle_sim = max(0.0, angle_sim - 3.0)

                if event.key in KEY_TO_MIDI and event.key not in held:
                    base_midi = KEY_TO_MIDI[event.key]
                    vk = voice_key(event.key)
                    held[event.key] = (vk, base_midi)
                    synth.note_on(vk, max(0, min(127, base_midi + octave_off)))

            elif event.type == pygame.KEYUP:
                if event.key in (pygame.K_LSHIFT, pygame.K_RSHIFT):
                    octave_off = clamp_oct(octave_off + 12); retune_all()
                elif event.key in (pygame.K_LCTRL, pygame.K_RCTRL):
                    octave_off = clamp_oct(octave_off - 12); retune_all()
                elif event.key == pygame.K_TAB:
                    octave_off = 0; retune_all()

                if event.key in held:
                    vk, _ = held.pop(event.key)
                    synth.note_off(vk)

        if not simulated:
            ok, a = try_read_lid_angle()
            if ok and a is not None:
                angle = a
            else:
                simulated = True
                angle = angle_sim
        else:
            angle = angle_sim

        dt_vel = max(1e-6, now - prev_t)
        vel = (angle - prev_angle) / dt_vel
        prev_angle, prev_t = angle, now

        vel_max = by_key["vel_max"].value
        deadzone = by_key["deadzone"].value
        fill_rate = by_key["fill_rate"].value
        leak_rate = by_key["leak_rate"].value
        rise_a = by_key["rise_a"].value
        fall_a = by_key["fall_a"].value

        b_raw = min(1.0, abs(vel) / max(1e-6, vel_max))
        b_raw = 0.0 if b_raw < deadzone else b_raw

        air = max(0.0, min(1.0, air + (b_raw * fill_rate - leak_rate) * dt))
        target = air
        bellows = (bellows * rise_a + target * (1.0 - rise_a)) if target > bellows else (bellows * fall_a + target * (1.0 - fall_a))
        synth.set_bellows(bellows)

        # ---------- paint ----------
        screen.fill(th["bg"])
        held_bases = {base for (_, base) in held.values()}
        octave_txt = f"{octave_off // 12:+d}" if octave_off != 0 else "0"

        # toolbar
        box(screen, 0, 0, win_w, TOOLBAR_H, th["toolbar"])
        hairline(screen, 0, TOOLBAR_H - 1, win_w, th["sep"])
        text(screen, "MacbookAccordion", col_x, TOOLBAR_H // 2, 16, 600, th["text"], vcenter=True)
        btn_reset.place(col_x + col_w - btn_reset.measure(), (TOOLBAR_H - 24) // 2)
        btn_reset.draw(screen, th)
        btn_more.place(btn_reset.rect.x - 10 - btn_more.measure(), (TOOLBAR_H - 24) // 2)
        btn_more.draw(screen, th)
        pill_label = "键盘试玩模式" if simulated else "屏幕控制已连接"
        pill_w = text_w(pill_label, 12, 500) + 40
        pill = pygame.Rect(btn_more.rect.x - 10 - pill_w, (TOOLBAR_H - 24) // 2, pill_w, 24)
        rr(screen, pill, 12, th["chip"])
        dot(screen, pill.x + 14, pill.centery, 4, th["sim"] if simulated else th["live"])
        text(screen, pill_label, pill.x + 25, pill.centery, 12, 500, th["text2"], vcenter=True)

        # hero card A — beginner-friendly play feedback
        a = pygame.Rect(col_x, TOOLBAR_H + 14, col_w, CARD_A_H)
        rr(screen, a, CARD_R, th["card"])
        pad = 20
        inner = col_w - pad * 2
        text(screen, "开合力度", a.x + pad, a.y + 16, 12, 600, th["text2"])
        text(screen, f"{bellows:0.2f}", a.x + pad, a.y + 32, 32, 600, th["text"])
        tip = "使用 ↑ / ↓ 模拟开合，按下方提示的按键开始演奏" if simulated else \
              "开合 MacBook 屏幕控制力度，按下方提示的按键开始演奏"
        text(screen, tip, a.right - pad, a.y + 28, 13, 400, th["text2"], align="right")
        meter_y = a.y + 84
        capsule(screen, a.x + pad, meter_y, inner, 10, th["track"])
        capsule(screen, a.x + pad, meter_y, int(inner * bellows), 10, th["accent"])
        air_x = a.x + pad + int(inner * air)
        box(screen, clamp(air_x, a.x + pad, a.x + pad + inner - 2), meter_y - 4, 2, 18, th["card"])
        hairline(screen, a.x + pad, a.y + 110, inner, th["sep"])

        note_names = [midi_to_name(base + octave_off) for (_, base) in held.values()]
        playing = " ".join(note_names)
        movement = "静止" if abs(vel) < 2 else "轻轻开合" if abs(vel) < 30 else "用力开合"
        stats = [("屏幕角度", f"{angle:0.1f}°"), ("开合状态", movement),
                 ("音高", octave_txt), ("正在演奏", playing if playing else "—")]
        stat_w = inner // 4
        for i, (cap, val) in enumerate(stats):
            sx = a.x + pad + i * stat_w
            text(screen, cap, sx, a.y + 120, 11, 500, th["text3"])
            if i == 3 and playing:
                names = list(note_names)
                val = " ".join(names)
                while names and text_w(val, 17, 600) > stat_w - 8:
                    names.pop()
                    val = " ".join(names) + " …"
            text(screen, val, sx, a.y + 134, 17, 600, th["text"])
            if i == 2:
                bx = sx + 42
                btn_oct_down.place(bx, a.y + 132, h=22)
                btn_oct_up.place(btn_oct_down.rect.right + 6, a.y + 132, h=22)
                btn_oct_down.draw(screen, th)
                btn_oct_up.draw(screen, th)

        # hero card B — on-screen keyboard
        b = pygame.Rect(col_x, a.bottom + 12, col_w, CARD_B_H)
        rr(screen, b, CARD_R, th["card"])
        kb_x, kb_y = b.x + 16, b.y + 16
        kb_w = col_w - 32
        wh = CARD_B_H - 32
        ww = kb_w / len(WHITE_MIDI)
        rr(screen, pygame.Rect(kb_x - 1, kb_y - 1, kb_w + 2, wh + 2), 7, th["key_line"])
        for i, m in enumerate(WHITE_MIDI):
            x = int(kb_x + i * ww)
            w = int(kb_x + (i + 1) * ww) - x - 1
            on = m in held_bases
            box(screen, x, kb_y, w, wh, th["accent"] if on else th["key_w"], bl=5, br=5)
            if m % 12 == 0:
                text(screen, midi_to_name(m), x + w // 2, kb_y + wh - 34,
                     9, 500, (255, 255, 255) if on else th["key_w_text"], align="center")
            if m in caps and ww >= 26:
                text(screen, caps[m], x + w // 2, kb_y + wh - 20,
                     10, 600, (255, 255, 255) if on else th["key_w_text"], align="center")
        bw = int(ww * 0.62)
        bh = int(wh * 0.62)
        for m in BLACK_MIDI:
            n_below = sum(1 for w in WHITE_MIDI if w < m)
            x = int(kb_x + n_below * ww - bw / 2)
            on = m in held_bases
            box(screen, x, kb_y, bw, bh, th["accent"] if on else th["key_b"], bl=4, br=4)
            if m in caps and bw >= 17:
                text(screen, caps[m], x + bw // 2, kb_y + bh - 18,
                     10, 600, (255, 255, 255) if on else th["key_b_text"], align="center")

        # scrollable settings
        clip = pygame.Rect(0, SCROLL_TOP, win_w, view_h)
        prev_clip = screen.get_clip()
        screen.set_clip(pygame.Rect(clip.x * S, clip.y * S, clip.w * S, clip.h * S))
        for sec in panel:
            card = sec["card"].move(0, scroll_y)
            if card.bottom < clip.y - 40 or card.y > clip.bottom + 40:
                continue
            text(screen, sec["title"], card.x + 4, sec["head_y"] + scroll_y + 8, 13, 600, th["text2"])
            rr(screen, card, CARD_R, th["card"])
            for i, row in enumerate(sec["rows"]):
                ry = card.y + i * ROW_H
                if i:
                    hairline(screen, card.x + 20, ry, card.w - 20, th["sep"])
                if row[0] == "slider":
                    p, s = row[1], row[2]
                    text(screen, p.label, card.x + 20, ry + ROW_H // 2, 14, 400, th["text"], vcenter=True)
                    s.draw(screen, th, clip)
                    if p.key == "master":
                        shown_value = f"{round(p.value * 100)}%"
                    elif p.key == "vel_max":
                        sensitivity = 1.0 - (p.value - p.minv) / (p.maxv - p.minv)
                        shown_value = "灵敏" if sensitivity >= 0.67 else "适中" if sensitivity >= 0.34 else "稳重"
                    else:
                        shown_value = format(p.value, p.fmt)
                    text(screen, shown_value, card.right - 20, ry + ROW_H // 2,
                         14, 500, th["text2"], align="right", vcenter=True)
                elif row[0] == "preset":
                    text(screen, row[1], card.x + 20, ry + ROW_H // 2,
                         14, 400, th["text"], vcenter=True)
                    preset_x = card.x + 20 + LABEL_W
                    for button in row[2].values():
                        button.place(preset_x, ry + (ROW_H - 28) // 2, h=28)
                        button.draw(screen, th)
                        preset_x = button.rect.right + 8
                else:
                    key = row[2]
                    if key == "sensor":
                        val = "未检测到，当前使用键盘试玩" if simulated else "已连接，可以开合屏幕"
                    elif key == "audio":
                        val = "正常" if audio_ok else "启动失败（请检查终端 / PortAudio）"
                    elif key == "octave":
                        val = "上方 − / + · Shift 升高 · Ctrl 降低 · Tab 重置"
                    else:
                        val = "使用 ↑ / ↓ 模拟开合屏幕" if simulated else "直接开合 MacBook 屏幕"
                    text(screen, row[1], card.x + 20, ry + ROW_H // 2, 14, 400, th["text"], vcenter=True)
                    text(screen, val, card.right - 20, ry + ROW_H // 2, 13, 400, th["text2"],
                         align="right", vcenter=True)
        screen.set_clip(prev_clip)

        if scrollable:
            rr(screen, knob_rect, 3, th["scroll"])

        mpos = pygame.mouse.get_pos()
        over = any(b.rect.collidepoint(mpos) for b in buttons)
        if not over and mpos[1] >= SCROLL_TOP:
            over = any(sl.rect.inflate(6, 10).collidepoint(mpos) for sl in sliders.values())
        if over != cursor_hand:
            cursor_hand = over
            try:
                pygame.mouse.set_cursor(pygame.SYSTEM_CURSOR_HAND if over else pygame.SYSTEM_CURSOR_ARROW)
            except pygame.error:
                pass  # 无头 / 特殊驱动下拿不到系统光标，不影响功能

        disp.flip()

    try:
        if stream is not None:
            stream.stop()
            stream.close()
    except Exception:
        pass

    pygame.quit()
    sys.exit(0)

if __name__ == "__main__":
    main()
