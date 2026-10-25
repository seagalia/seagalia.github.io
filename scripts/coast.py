"""Draw the coast illustration at the bottom of the page and inline it into an HTML file.

Old town on its ramparts on the left, forested hill with the square lighthouse on the
right, mountains behind, three wave layers in front. Colors live in assets/site.css.

Usage: python3 scripts/coast.py index.html
"""
import re, sys
path = sys.argv[1]
SEA = 240

# old town houses standing on the ramparts: (x1, x2, top, roof)
houses = [
    (112, 142, 170, "flat"), (142, 176, 158, "pitched"), (176, 214, 150, "pitched"),
    (214, 250, 164, "flat"), (250, 292, 140, "pitched"), (292, 332, 152, "pitched"),
    (362, 402, 136, "pitched"), (402, 442, 150, "flat"), (442, 482, 128, "pitched"),
    (482, 522, 144, "pitched"), (556, 600, 150, "pitched"), (600, 646, 170, "flat"),
    (646, 700, 158, "pitched"), (700, 742, 176, "pitched"),
]
walls, roofs, windows = [], [], []
for x1, x2, top, roof in houses:
    walls.append(f"M{x1} 205 V{top} H{x2} V205Z")
    if roof == "pitched":
        roofs.append(f"M{x1-3} {top} L{(x1+x2)//2} {top-12} L{x2+3} {top}Z")
    else:
        roofs.append(f"M{x1-2} {top} H{x2+2} V{top-4} H{x1-2}Z")
    for wx in range(x1 + 8, x2 - 8, 12):
        for wy in range(top + 10, 196, 16):
            windows.append(f"M{wx} {wy} h5 v8 h-5Z")

# outline of the lighthouse hill, used to place the trees on its slope
hill = [(1000, 240), (1040, 226), (1080, 208), (1120, 192), (1160, 180), (1200, 171),
        (1260, 166), (1300, 168), (1340, 180), (1380, 205), (1420, 240)]
def hill_y(x):
    for (x1, y1), (x2, y2) in zip(hill, hill[1:]):
        if x1 <= x <= x2:
            return y1 + (y2 - y1) * (x - x1) / (x2 - x1)
    return 240

# dense rounded canopy wrapping the hill: a far layer behind the lighthouse, a near layer hiding its base
def canopy(spacing, y_offset, radii, x_start=1006, x_end=1416):
    puffs = []
    for i, x in enumerate(range(x_start, x_end, spacing)):
        r = radii[i % len(radii)]
        cy = hill_y(x) + y_offset
        puffs.append(f"M{x - r} {cy:.0f} a{r} {r} 0 1 1 {2 * r} 0 a{r} {r} 0 1 1 {-2 * r} 0Z")
    return " ".join(puffs)

far_canopy = canopy(20, -8, (18, 22, 16, 24, 20))
near_canopy = canopy(24, 16, (16, 20, 14, 18), x_start=1018, x_end=1404)
cypresses = []
for x, h in ((1190, 58), (1204, 44), (1290, 52)):
    base = hill_y(x) + 6
    top = base - h
    cypresses.append(f"M{x} {base:.0f} C{x - 9} {base - 18:.0f} {x - 6} {top + 12:.0f} {x} {top:.0f} C{x + 6} {top + 12:.0f} {x + 9} {base - 18:.0f} {x} {base:.0f}Z")

coast = f'''<div class="coast" aria-hidden="true">
      <svg class="coast-far" viewBox="0 140 1440 110" preserveAspectRatio="none">
        <path class="far" d="M0 214 L70 186 L130 198 L210 164 L290 192 L380 150 L450 176 L520 158 L610 184 L700 146 L790 172 L880 140 L960 170 L1040 152 L1130 180 L1220 160 L1320 186 L1440 168 V250 H0Z"/>
      </svg>
      <svg class="coast-town" viewBox="80 50 1360 200" preserveAspectRatio="xMidYMax meet">
        <!-- headland with the lighthouse across the bay -->
        <path class="forest-far" d="M1000 250 V{SEA} C1070 214 1140 176 1230 168 C1310 162 1360 186 1420 {SEA} V250Z {far_canopy}"/>
        <!-- square stone lighthouse: corbelled gallery, red lantern room, white dome -->
        <path class="town" d="M1223 176 L1225 97 H1247 L1249 176Z M1219 97 H1253 V91 H1219Z"/>
        <path class="window" d="M1224 97 h3 v2 h-3Z M1230 97 h3 v2 h-3Z M1236 97 h3 v2 h-3Z M1242 97 h3 v2 h-3Z M1234 112 h4 v7 h-4Z M1234 132 h4 v7 h-4Z M1234 152 h4 v7 h-4Z"/>
        <path class="lantern" d="M1227 91 V78 H1245 V91Z"/>
        <path class="dome" d="M1225 78 C1225 66 1247 66 1247 78Z M1235.4 69 V60 h1.2 V69Z"/>
        <path class="forest-deep" d="{" ".join(cypresses)}"/>
        <path class="forest" d="{near_canopy}"/>
        <!-- old town: ramparts, houses, bell tower, castle tower -->
        <path class="town" d="M100 250 V{SEA} L108 200 H566 L574 {SEA} V250Z M560 250 V{SEA} L566 206 H760 C780 214 790 226 800 {SEA} V250Z"/>
        <path class="town" d="{" ".join(walls)}"/>
        <path class="roof" d="{" ".join(roofs)}"/>
        <path class="town" d="M332 205 V112 H362 V205Z M330 112 L347 100 L364 112Z"/>
        <path class="town" d="M520 205 V90 H556 V205Z M518 90 H558 V84 H518Z"/>
        <path class="window" d="{" ".join(windows)} M342 126 a5 5 0 0 1 10 0 v14 h-10Z M532 104 h12 v6 h-12Z"/>
        <path class="town" d="M538 84 V58 h2 V84Z"/>
        <path class="flag" d="M540 58 L556 63 L540 68Z"/>
        <!-- palms on the ramparts -->
        <path class="palm" d="M150 200 C152 180 150 170 147 158 l2 0 C154 170 155 182 154 200Z M148 158 c-12 -6 -22 -2 -28 6 c10 -8 20 -6 28 -4 c-8 0 -16 6 -18 14 c6 -8 14 -12 20 -12 c4 6 4 14 2 20 c4 -6 6 -14 0 -22 c10 -2 18 2 24 10 c-4 -10 -14 -14 -24 -12 c8 -4 18 -4 26 2 c-8 -8 -20 -10 -30 -4Z"/>
        <path class="palm" d="M182 200 C184 184 183 176 181 166 l2 0 C186 176 187 186 186 200Z M182 166 c-10 -5 -18 -2 -23 5 c8 -6 16 -5 23 -3 c-6 0 -13 5 -15 11 c5 -6 11 -9 16 -9 c3 5 3 11 2 16 c3 -5 5 -11 0 -18 c8 -2 15 2 20 8 c-3 -8 -11 -11 -20 -10 c6 -3 15 -3 21 2 c-6 -6 -16 -8 -24 -3Z"/>
        <path class="town" d="M780 250 V{SEA} c6 -10 18 -12 26 -4 c8 -8 20 -4 22 4 V250Z M860 250 V{SEA} c4 -6 12 -6 16 0 V250Z"/>
      </svg>
      <svg class="coast-sea" viewBox="0 0 1440 64" preserveAspectRatio="none">
        <path class="w1" d="M0 16 C240 -6 480 38 720 16 S1200 -6 1440 16 V64 H0Z"/>
        <path class="w2" d="M0 34 C240 12 480 56 720 34 S1200 12 1440 34 V64 H0Z"/>
        <path class="w3" d="M0 52 C240 32 480 72 720 52 S1200 32 1440 52 V64 H0Z"/>
      </svg>
    </div>'''

s = open(path).read()
s, n = re.subn(r'<(svg|div) class="(sea-waves|coast)".*?</\1>(\s*</svg>\s*</div>)?', lambda m: coast, s, count=1, flags=re.S)
assert n == 1
open(path, "w").write(s)
