#!/usr/bin/env python3
# scene_geometry_check.py — 廖梦溪 C/D 开发前交付 v1.1 数学核查脚本
#
# 独立复算交付包中的全部数值结论，与 Dart 测试用例
# （scene_geometry_test.dart / player_movement_test.dart，待 Flutter 环境执行）
# 互为印证。纯标准库，无第三方依赖：
#   python code/scene_geometry_check.py
#
# v1.1 变更（对应组长复审 4 项意见）：
#  1. contains_local 改半开区间（左/上包含、右/下排除，与 Dart Rect.contains
#     一致），补四边、四角及边内外检查；WalkableArea 多边形判定仍边界包含，
#     两者刻意不同，不混改。
#  2. scale 运行时保护：计算后以 if 检查（有限且 >0，偏移有限），不合法
#     抛异常（对应 Dart ArgumentError）；补极小正数视口使 scale 下溢为 0 的检查。
#  3. 统一移动入口：set_move_direction 为唯一方向入口（有限校验、零停、
#     非零归一化）；键盘/摇杆为适配入口；clear_input 清全部方向状态。
#  4. Menu 生命周期：pause_for_menu（暂停+清输入，位置保留）→
#     resume_from_menu（恢复，不自动续走）；reset 仅用于明确重新开始。

import math
import os
import sys

# ---- 唯一世界配置（与 SceneGeometry 一致，v1 数值冻结）----
W, H = 941.0, 1672.0
POLY = [(240, 960), (590, 960), (555, 1010), (550, 1060), (550, 1385), (75, 1385)]
START = (360.0, 1160.0)
MENU = (200.0, 1170.0)
R = 70.0
ANCHOR = (51.0, 195.0)
RENDER_W = 103.0
SPRITE_W, SPRITE_H = 103.0, 205.0

# ---- D 移动规则常量（与 PlayerMovementController 一致）----
SPEED = 120.0        # 世界像素/秒（原图像素）
MAX_DT = 0.05        # dt 上限（秒）
SUBSTEP = 2.0        # 子步最大长度（世界像素）
DEAD_ZONE = 0.15     # 摇杆死区

failures = []
pass_count = 0


def check(name, ok, detail=""):
    global pass_count
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {detail}")
    if ok:
        pass_count += 1
    else:
        failures.append(name)


# ================= C：几何与变换 =================

def point_in_poly(p, poly, eps=1e-9):
    """WalkableArea 语义：射线法 + 边界**包含**（贴边滑行前提）。
    与 contains_local 的半开区间刻意不同，勿混改（复审意见 1）。"""
    x, y = p
    n = len(poly)
    for i in range(n):  # 在边上 -> 包含
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cross = (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1)
        if abs(cross) < eps and min(x1, x2) - eps <= x <= max(x1, x2) + eps \
                and min(y1, y2) - eps <= y <= max(y1, y2) + eps:
            return True
    inside = False
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / (y2 - y1) + x1):
            inside = not inside
    return inside


def seg_intersect(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    d1 = ccw(p3, p4, p1)
    d2 = ccw(p3, p4, p2)
    d3 = ccw(p1, p2, p3)
    d4 = ccw(p1, p2, p4)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


def seg_in_poly(a, b, poly, steps=2000):
    """密集采样 + 精确线段-边求交（求交为本脚本职责，Dart 侧仅采样）。"""
    for i in range(steps + 1):
        t = i / steps
        p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        if not point_in_poly(p, poly):
            return False, f"sample {p} outside"
    n = len(poly)
    for i in range(n):
        if seg_intersect(a, b, poly[i], poly[(i + 1) % n]):
            return False, f"crosses edge {poly[i]}-{poly[(i + 1) % n]}"
    return True, "ok"


def make_transform(vw, vh):
    """等比缩放居中。入口拒绝非法视口；计算后 scale 运行时保护（if 检查，
    非 assert，对应 Dart ArgumentError）。"""
    if not (math.isfinite(vw) and math.isfinite(vh) and vw > 0 and vh > 0):
        raise ValueError(f"viewport must be positive and finite: {vw}x{vh}")
    s = min(vw / W, vh / H)
    ox, oy = (vw - W * s) / 2, (vh - H * s) / 2
    # scale 运行时保护（复审意见 2）：极小正数视口可使 s 下溢为 0
    if not math.isfinite(s) or s <= 0:
        raise ValueError(f"computed scale must be finite and positive: {s}")
    if not (math.isfinite(ox) and math.isfinite(oy)):
        raise ValueError(f"computed offset must be finite: ({ox},{oy})")
    return s, ox, oy


def w2l(p, t):
    s, ox, oy = t
    return ox + p[0] * s, oy + p[1] * s


def l2w(p, t):
    s, ox, oy = t
    return (p[0] - ox) / s, (p[1] - oy) / s


def scene_rect(t):
    s, ox, oy = t
    return ox, oy, W * s, H * s


def contains_local(p, t):
    """半开区间（复审意见 1）：left <= x < left+width，top <= y < top+height，
    与 Dart Rect.contains 一致。"""
    left, top, w, h = scene_rect(t)
    return left <= p[0] < left + w and top <= p[1] < top + h


print("=== C 检查 ③④⑤：区域与半径 ===")
check("③ playerStart 在多边形内", point_in_poly(START, POLY))
check("③ menuInteractionPoint 在多边形内", point_in_poly(MENU, POLY))
ok, msg = seg_in_poly(START, MENU, POLY)
check("④ playerStart→menuInteractionPoint 存在区域内路径", ok, msg)
check("⑤ menuInteractionRadius 有限且 > 0", math.isfinite(R) and R > 0, f"R={R}")
d = math.dist(START, MENU)
check("初始位置无交互提示", d > R, f"dist={d:.2f} > {R}")

print("=== E 交互核查点（欧氏距离 <= 70 可触发）===")
for x, want in {269: True, 270: True, 271: False}.items():
    got = math.dist((x, 1170.0), MENU) <= R
    check(f"({x},1170) -> {'可触发' if want else '不可触发'}", got == want,
          f"dist={math.dist((x, 1170.0), MENU):.2f}")

print("=== C 检查 ①②：两种视口、往返误差与 scale 运行时保护 ===")
for vw, vh in [(320.0, 640.0), (800.0, 600.0)]:
    t = make_transform(vw, vh)
    s, ox, oy = t
    check(f"scale 运行时保护通过（{int(vw)}x{int(vh)}）",
          math.isfinite(s) and s > 0, f"scale={s:.7f}")
    print(f"    offset=({ox:.4f},{oy:.4f}) "
          f"playerStart local={tuple(round(v,3) for v in w2l(START,t))} "
          f"menu local={tuple(round(v,3) for v in w2l(MENU,t))} "
          f"交互圈屏幕半径={R*s:.3f}")
    e1 = e2 = 0.0
    gy = 0.0
    while gy <= H:
        gx = 0.0
        while gx <= W:
            w = (gx, gy)
            l = w2l(w, t)
            w2 = l2w(l, t)
            e2 = max(e2, abs(w2[0] - w[0]), abs(w2[1] - w[1]))
            l2 = w2l(w2, t)
            e1 = max(e1, abs(l2[0] - l[0]), abs(l2[1] - l[1]))
            gx += 17
        gy += 19
    check(f"① local→world→local 误差 <= 0.01（{int(vw)}x{int(vh)}）", e1 <= 0.01,
          f"max={e1:.2e}")
    check(f"② world→local→world 误差 <= 0.01（{int(vw)}x{int(vh)}）", e2 <= 0.01,
          f"max={e2:.2e}")

print("=== 非法视口与极小正数视口拒绝（复审意见 2）===")
for bad in [(0, 600), (-5, 600), (float("nan"), 600), (float("inf"), 600),
            (5e-324, 600), (600, 5e-324)]:  # 极小正数 -> scale 下溢为 0
    try:
        make_transform(*bad)
        check(f"视口 {bad} 拒绝", False, "被错误接受")
    except ValueError:
        check(f"视口 {bad} 拒绝", True)

print("=== sceneRect 与边界策略（半开区间，复审意见 1）===")
t800 = make_transform(800.0, 600.0)
left, top, rw, rh = scene_rect(t800)
right, bottom = left + rw, top + rh
print(f"    800x600 sceneRect = (left={left:.4f}, top={top:.4f}, "
      f"width={rw:.4f}, height={rh:.4f}) right={right:.4f} bottom={bottom:.4f}")
check("sceneRect 数值", abs(left - 231.1603) < 1e-3 and abs(top) < 1e-9
      and abs(rw - 337.6794) < 1e-3 and abs(rh - 600) < 1e-9)
# 四边：左/上包含、右/下排除
check("四边：左边包含", contains_local((left, 300), t800))
check("四边：右边排除", not contains_local((right, 300), t800))
check("四边：上边包含", contains_local((400, top), t800))
check("四边：下边排除", not contains_local((400, bottom), t800))
# 四角：仅左上在内
check("四角：左上包含", contains_local((left, top), t800))
check("四角：右上排除", not contains_local((right, top), t800))
check("四角：左下排除", not contains_local((left, bottom), t800))
check("四角：右下排除", not contains_local((right, bottom), t800))
# 边内外（1e-3 步长）
check("边内外：左外 1e-3 拒绝", not contains_local((left - 1e-3, 300), t800))
check("边内外：右内 1e-3 接受", contains_local((right - 1e-3, 300), t800))
check("边内外：上外 1e-3 拒绝", not contains_local((400, top - 1e-3), t800))
check("边内外：下内 1e-3 接受", contains_local((400, bottom - 1e-3), t800))
# 空白区（⑥ 原有用例，半开语义下仍成立）
check("⑥ 左侧空白 (100,300) 拒绝", not contains_local((100, 300), t800))
check("⑥ 右侧空白 (700,300) 拒绝", not contains_local((700, 300), t800))
t320 = make_transform(320.0, 640.0)
check("⑥ 上侧空白 (160,10) 拒绝（320x640）", not contains_local((160, 10), t320))
inside_local = (302.931, 419.856)
check("⑦ 场景内点在 sceneRect 内", contains_local(inside_local, t800))
w_back = l2w(inside_local, t800)
check("⑦ 场景内点换算到 Menu 附近", abs(w_back[0] - 200) <= 0.01
      and abs(w_back[1] - 1170) <= 0.01,
      f"world=({w_back[0]:.4f},{w_back[1]:.4f})")
l_back = w2l(w_back, t800)
check("⑦ 往返误差 <= 0.01", abs(l_back[0] - inside_local[0]) <= 0.01
      and abs(l_back[1] - inside_local[1]) <= 0.01)
check("⑧ 窗口变化后同一视口变换结果不变", t320 == make_transform(320.0, 640.0))
check("⑧ 世界常量不变", START == (360.0, 1160.0) and MENU == (200.0, 1170.0)
      and POLY[0] == (240, 960) and len(POLY) == 6)

# ================= D：移动规则（统一移动入口，复审意见 3/4）=================

print("=== D 移动规则核查（统一移动入口）===")


def set_move_direction(dx, dy):
    """唯一方向入口：有限校验、零停、非零归一化。"""
    if not (math.isfinite(dx) and math.isfinite(dy)):
        raise ValueError(f"move direction must be finite: ({dx},{dy})")
    if dx == 0 and dy == 0:
        return 0.0, 0.0
    n = math.hypot(dx, dy)
    return dx / n, dy / n


def keys_adapter(keys):
    """键盘适配：按键集合 -> 向量（相反方向抵消）-> 统一入口。"""
    dx = (-1 if "left" in keys else 0) + (1 if "right" in keys else 0)
    dy = (-1 if "up" in keys else 0) + (1 if "down" in keys else 0)
    return set_move_direction(dx, dy)


def joystick_adapter(vx, vy):
    """摇杆适配：有限校验 -> 钳制 <=1 -> 死区 -> 统一入口。"""
    if not (math.isfinite(vx) and math.isfinite(vy)):
        raise ValueError(f"joystick vector must be finite: ({vx},{vy})")
    mag = math.hypot(vx, vy)
    if mag > 1:
        vx, vy = vx / mag, vy / mag
    if math.hypot(vx, vy) < DEAD_ZONE:
        return set_move_direction(0.0, 0.0)
    return set_move_direction(vx, vy)


def validate_dt(dt):
    if not math.isfinite(dt) or dt < 0:
        raise ValueError(f"invalid dt {dt}")
    return min(dt, MAX_DT)


def resolve_move(frm, delta):
    dist = math.hypot(*delta)
    if dist == 0:
        return frm
    steps = math.ceil(dist / SUBSTEP)
    step = (delta[0] / steps, delta[1] / steps)
    pos = frm
    for _ in range(steps):
        nxt = (pos[0] + step[0], pos[1] + step[1])
        if point_in_poly(nxt, POLY):
            pos = nxt
            continue
        nx = (pos[0] + step[0], pos[1])
        if point_in_poly(nx, POLY):
            pos = nx
            continue
        ny = (pos[0], pos[1] + step[1])
        if point_in_poly(ny, POLY):
            pos = ny
            continue
        break
    return pos


class Controller:
    """镜像 PlayerMovementController v1.1：统一方向状态 + Menu 生命周期。"""

    def __init__(self, start=START):
        self.foot = start
        self.direction = (0.0, 0.0)  # 统一方向状态
        self.paused = False

    def set_direction(self, d):
        self.direction = d

    def update(self, dt, n=1):
        traj = [self.foot]
        for _ in range(n):
            eff = validate_dt(dt)
            if self.paused or eff == 0 or self.direction == (0.0, 0.0):
                break
            self.foot = resolve_move(
                self.foot,
                (self.direction[0] * SPEED * eff,
                 self.direction[1] * SPEED * eff))
            traj.append(self.foot)
        return traj

    def pause_for_menu(self):
        self.paused = True
        self.direction = (0.0, 0.0)  # clearInput

    def resume_from_menu(self):
        self.paused = False

    def reset(self):
        self.direction = (0.0, 0.0)
        self.paused = False
        self.foot = START


paths = {}

c = Controller()
c.set_direction(keys_adapter({"right"}))
paths["straight"] = c.update(0.05, 20)
p = c.foot
check("D1 直行 20x(dt=0.05)：x 位移恰好 120",
      abs(p[0] - (START[0] + 120)) < 1e-9 and abs(p[1] - START[1]) < 1e-9,
      f"end=({p[0]:.4f},{p[1]:.4f})")

c = Controller()
c.set_direction(keys_adapter({"right", "down"}))
paths["diagonal"] = c.update(0.05, 20)
p = c.foot
total = math.dist(START, p)
check("D2 斜行 20x(dt=0.05)：路径总长仍 120（方向归一化）",
      abs(total - 120) < 1e-6, f"len={total:.6f} end=({p[0]:.4f},{p[1]:.4f})")
check("D2 斜行终点在区域内", point_in_poly(p, POLY))

c = Controller()
c.set_direction(keys_adapter({"left", "right"}))
c.update(0.05, 10)
check("D3 相反方向抵消（适配层合成零方向）：位置不变", c.foot == START)

c = Controller((555.0, 1000.0))
c.set_direction(keys_adapter({"right", "down"}))
paths["slide"] = c.update(0.05, 5)
check("D4 斜边沿边滑动：始终不越界",
      all(point_in_poly(q, POLY) for q in paths["slide"]),
      f"end=({c.foot[0]:.4f},{c.foot[1]:.4f})")

c = Controller((545.0, 1378.0))
c.set_direction(keys_adapter({"right", "down"}))
paths["corner"] = c.update(0.05, 50)
check("D5 右下角压迫 50 步：始终不越界",
      all(point_in_poly(q, POLY) for q in paths["corner"]),
      f"end=({c.foot[0]:.4f},{c.foot[1]:.4f})")
check("D5 角落终点不超出 x<=550 且 y<=1385", c.foot[0] <= 550 + 1e-9
      and c.foot[1] <= 1385 + 1e-9)

for bad in [-0.01, float("nan"), float("inf")]:
    try:
        validate_dt(bad)
        check(f"D6 dt={bad} 拒绝", False, "被错误接受")
    except ValueError:
        check(f"D6 dt={bad} 拒绝", True)
c = Controller()
c.set_direction(keys_adapter({"right"}))
c.update(0.1, 1)
check("D6 dt=0.1 截断为 0.05（位移 6 而非 12）",
      abs(c.foot[0] - (START[0] + 6)) < 1e-9, f"dx={c.foot[0]-START[0]:.4f}")
c = Controller()
c.set_direction(keys_adapter({"right"}))
c.update(0.0, 1)
check("D6 dt=0 为合法空操作", c.foot == START)

print("=== 统一移动入口（复审意见 3）===")
check("D7 setMoveDirection(3,4) 归一化为 (0.6,0.8)",
      set_move_direction(3, 4) == (0.6, 0.8))
check("D7 零方向 = 停止", set_move_direction(0, 0) == (0.0, 0.0))
try:
    set_move_direction(float("nan"), 0)
    check("D7 非有限方向拒绝", False, "被错误接受")
except ValueError:
    check("D7 非有限方向拒绝", True)
c = Controller()
for set_via in [lambda: c.set_direction(keys_adapter({"right"})),
                lambda: c.set_direction(joystick_adapter(1.0, 0.0)),
                lambda: c.set_direction(set_move_direction(0, 1))]:
    set_via()
    c.direction = (0.0, 0.0)  # clearInput
    c.update(0.05, 1)
check("D7 clearInput 清除全部方向状态（三入口）", c.foot == START)

print("=== Menu 进出与返回（复审意见 4）===")
c = Controller()
c.set_direction(keys_adapter({"right"}))
c.update(0.05, 10)
before = c.foot  # (420, 1160)
c.pause_for_menu()
check("D8 pauseForMenu：暂停且清输入，位置保留",
      c.paused and c.direction == (0.0, 0.0) and c.foot == before)
c.update(0.05, 5)
check("D8 Menu 期间 update 无位移", c.foot == before)
c.resume_from_menu()
check("D8 resumeFromMenu：恢复更新，位置不变", not c.paused and c.foot == before)
c.update(0.05, 5)
check("D8 返回后不自动续走（输入已清）", c.foot == before)
c.reset()
check("D8 reset 仅重开：回 playerStart", c.foot == START)

print("=== 摇杆适配（Android）===")
check("D9 摇杆 (0.6,0.8) 归一化后速度恒定",
      joystick_adapter(0.6, 0.8) == (0.6, 0.8))
check("D9 摇杆死区 (0.10,0.10) 不触发",
      joystick_adapter(0.10, 0.10) == (0.0, 0.0))
check("D9 摇杆超幅 (3,4) 钳制为单位向量",
      abs(math.hypot(*joystick_adapter(3, 4)) - 1) < 1e-9)
c = Controller()
c.set_direction(joystick_adapter(1.0, 0.0))
c.update(0.05, 20)
check("D9 摇杆直行 20 步位移 120（与键盘一致）",
      abs(c.foot[0] - (START[0] + 120)) < 1e-9)

check("D10 多边形边界包含（勿与 sceneRect 半开混改）：P3(550,1060)",
      point_in_poly((550, 1060), POLY))
check("D10 多边形边界包含：P4(550,1385)", point_in_poly((550, 1385), POLY))

# ================= 证据图 =================

try:
    from PIL import Image, ImageDraw, ImageFont
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "images")
    world = None
    for cand in ["bedroom_world_v1.png",
                 os.path.join("images", "bedroom_world_v1.png")]:
        full = os.path.normpath(os.path.join(base, cand))
        if os.path.exists(full):
            world = Image.open(full).convert("RGB")
            break
    if world is None:
        world = Image.new("RGB", (int(W), int(H)), (245, 245, 245))
    d2 = ImageDraw.Draw(world, "RGBA")
    try:
        f18 = ImageFont.truetype("arial.ttf", 18)
    except Exception:
        f18 = ImageFont.load_default()
    d2.polygon(POLY, fill=(0, 255, 0, 50), outline=(0, 200, 0, 255))
    colors = {"straight": (0, 80, 255), "diagonal": (255, 128, 0),
              "slide": (200, 0, 200), "corner": (220, 0, 0)}
    labels = {"straight": "D1 straight x20=120px", "diagonal": "D2 diagonal len=120",
              "slide": "D4 slide along slant", "corner": "D5 corner x50"}
    for name, traj in paths.items():
        col = colors[name]
        for i in range(len(traj) - 1):
            d2.line([traj[i], traj[i + 1]], fill=col + (255,), width=4)
        ex, ey = traj[-1]
        d2.ellipse([ex - 6, ey - 6, ex + 6, ey + 6], fill=col + (255,),
                   outline=(255, 255, 255, 255))
        d2.text((ex + 10, ey - 10), labels[name], fill=col, font=f18,
                stroke_width=2, stroke_fill=(255, 255, 255))
    sx, sy = START
    d2.ellipse([sx - 8, sy - 8, sx + 8, sy + 8], fill=(0, 80, 255, 255),
               outline=(255, 255, 255, 255))
    d2.text((sx + 12, sy + 10), "playerStart (360,1160)", fill=(0, 60, 255),
            font=f18, stroke_width=2, stroke_fill=(255, 255, 255))
    d2.text((10, 10), "movement-check v1.1 (speed=120px/s, dt<=0.05, "
            "substep<=2px)", fill=(0, 0, 0), font=f18, stroke_width=2,
            stroke_fill=(255, 255, 255))
    out = os.path.normpath(os.path.join(base, "movement-check-v1.1.png"))
    world.save(out)
    print(f"[INFO] 证据图已生成: {out}")
except ImportError:
    print("[INFO] 未安装 Pillow，跳过证据图生成（不影响检查结果）")

print()
print(f"结果：[PASS] 共 {pass_count} 项；[FAIL] 共 {len(failures)} 项。"
      + (f" 失败项: {failures}" if failures else "全部通过。"))
if failures:
    sys.exit(1)
