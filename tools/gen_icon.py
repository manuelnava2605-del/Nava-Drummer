from PIL import Image, ImageDraw
import math

SIZE = 1024
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

# ── Background: warm cream gradient ──────────────────────────────────────────
bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
bg_draw = ImageDraw.Draw(bg)
for y in range(SIZE):
    t = y / SIZE
    r = int(245 + (225 - 245) * t)
    g = int(238 + (215 - 238) * t)
    b = int(220 + (195 - 220) * t)
    bg_draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

# Rounded rectangle mask
mask = Image.new("L", (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
radius = 200
mask_draw.rounded_rectangle([0, 0, SIZE-1, SIZE-1], radius=radius, fill=255)
bg.putalpha(mask)
img.paste(bg, (0, 0), bg)

draw = ImageDraw.Draw(img)

# ── Blue border ───────────────────────────────────────────────────────────────
border_steps = 30
for i in range(border_steps):
    t = i / border_steps
    r = int(60 + (130 - 60) * t)
    g = int(160 + (210 - 160) * t)
    b = int(235 + (255 - 235) * t)
    draw.rounded_rectangle(
        [i, i, SIZE-1-i, SIZE-1-i],
        radius=max(10, radius - i),
        outline=(r, g, b, 255),
        width=1
    )

# ── Floor shadow ─────────────────────────────────────────────────────────────
floor_y = 790
draw.ellipse([120, floor_y, 904, floor_y + 70], fill=(195, 180, 160, 160))

# ── DRUM KIT ──────────────────────────────────────────────────────────────────

# Bass drum
bx, by, brx, bry = 510, 705, 155, 115
draw.ellipse([bx-brx, by-bry, bx+brx, by+bry], fill=(95, 28, 28, 255))
draw.ellipse([bx-brx, by-bry, bx+brx, by+bry], outline=(55, 12, 12, 255), width=7)
draw.ellipse([bx-brx+10, by-bry+10, bx+brx-10, by+bry-10], fill=(215, 205, 195, 255))
draw.ellipse([bx-brx+20, by-bry+20, bx+brx-20, by+bry-20], fill=(200, 188, 172, 255))
draw.ellipse([bx-42, by-32, bx+42, by+32], fill=(75, 18, 18, 255))
draw.ellipse([bx-32, by-24, bx+32, by+24], fill=(175, 28, 28, 255))

# Snare
sx, sy, srx, sry = 358, 615, 78, 33
draw.ellipse([sx-srx, sy-sry, sx+srx, sy+sry], fill=(135, 135, 145, 255))
draw.ellipse([sx-srx, sy-sry, sx+srx, sy+sry], outline=(75, 75, 85, 255), width=5)
draw.ellipse([sx-srx+7, sy-sry+7, sx+srx-7, sy+sry-7], fill=(228, 222, 215, 255))
draw.line([sx-12, sy+sry, sx-35, floor_y], fill=(100, 100, 110, 255), width=5)
draw.line([sx+12, sy+sry, sx+35, floor_y], fill=(100, 100, 110, 255), width=5)

# Tom 1
t1x, t1y, t1rx, t1ry = 388, 462, 63, 27
draw.ellipse([t1x-t1rx, t1y-t1ry, t1x+t1rx, t1y+t1ry], fill=(95, 28, 28, 255))
draw.ellipse([t1x-t1rx, t1y-t1ry, t1x+t1rx, t1y+t1ry], outline=(55, 12, 12, 255), width=4)
draw.ellipse([t1x-t1rx+6, t1y-t1ry+6, t1x+t1rx-6, t1y+t1ry-6], fill=(222, 212, 200, 255))

# Tom 2
t2x, t2y, t2rx, t2ry = 540, 452, 63, 27
draw.ellipse([t2x-t2rx, t2y-t2ry, t2x+t2rx, t2y+t2ry], fill=(95, 28, 28, 255))
draw.ellipse([t2x-t2rx, t2y-t2ry, t2x+t2rx, t2y+t2ry], outline=(55, 12, 12, 255), width=4)
draw.ellipse([t2x-t2rx+6, t2y-t2ry+6, t2x+t2rx-6, t2y+t2ry-6], fill=(222, 212, 200, 255))

# Floor tom
ftx, fty, ftrx, ftry = 698, 645, 83, 36
draw.ellipse([ftx-ftrx, fty-ftry, ftx+ftrx, fty+ftry], fill=(95, 28, 28, 255))
draw.ellipse([ftx-ftrx, fty-ftry, ftx+ftrx, fty+ftry], outline=(55, 12, 12, 255), width=5)
draw.ellipse([ftx-ftrx+7, fty-ftry+7, ftx+ftrx-7, fty+ftry-7], fill=(222, 212, 200, 255))

# Hi-hat left
hx, hy = 258, 492
draw.line([hx, hy+22, hx-18, floor_y], fill=(115, 115, 125, 255), width=5)
draw.line([hx, hy+22, hx+18, floor_y], fill=(115, 115, 125, 255), width=5)
draw.ellipse([hx-62, hy-8, hx+62, hy+8], fill=(208, 172, 48, 255))
draw.ellipse([hx-62, hy-8, hx+62, hy+8], outline=(175, 140, 28, 255), width=3)
draw.ellipse([hx-62, hy-20, hx+62, hy-4], fill=(218, 182, 58, 255))
draw.ellipse([hx-62, hy-20, hx+62, hy-4], outline=(175, 140, 28, 255), width=3)

# Ride cymbal right
rcx, rcy = 742, 472
draw.line([rcx, rcy+12, rcx+22, floor_y], fill=(115, 115, 125, 255), width=5)
draw.ellipse([rcx-77, rcy-13, rcx+77, rcy+13], fill=(208, 172, 48, 255))
draw.ellipse([rcx-77, rcy-13, rcx+77, rcy+13], outline=(175, 140, 28, 255), width=3)

# Crash cymbal
crx, cry = 298, 382
draw.ellipse([crx-58, cry-11, crx+58, cry+11], fill=(212, 178, 52, 190))

# ── STOOL ─────────────────────────────────────────────────────────────────────
stx, sty = 510, 775
draw.line([stx-10, sty, stx-42, floor_y+12], fill=(75, 75, 80, 255), width=9)
draw.line([stx+10, sty, stx+42, floor_y+12], fill=(75, 75, 80, 255), width=9)
draw.ellipse([stx-52, sty-16, stx+52, sty+16], fill=(55, 38, 28, 255))
draw.ellipse([stx-44, sty-12, stx+44, sty+12], fill=(75, 52, 38, 255))

# ── LEGS ─────────────────────────────────────────────────────────────────────
draw.polygon([(428, 772), (462, 772), (448, 862), (416, 862)], fill=(78, 82, 92, 255))
draw.polygon([(558, 772), (592, 772), (608, 862), (574, 862)], fill=(78, 82, 92, 255))
draw.ellipse([398, 848, 462, 878], fill=(38, 32, 28, 255))
draw.ellipse([566, 848, 630, 878], fill=(38, 32, 28, 255))

# ── TORSO blue polo ───────────────────────────────────────────────────────────
draw.polygon([(418, 598), (602, 598), (622, 772), (398, 772)], fill=(68, 138, 208, 255))
draw.polygon([(478, 598), (542, 598), (518, 642), (492, 642)], fill=(198, 228, 255, 255))
draw.line([(510, 642), (510, 772)], fill=(52, 118, 188, 255), width=5)

# ── ARMS ─────────────────────────────────────────────────────────────────────
# Left arm to hi-hat
draw.polygon([(418, 608), (395, 618), (305, 538), (332, 522)], fill=(68, 138, 208, 255))
draw.ellipse([292, 518, 335, 558], fill=(228, 182, 142, 255))
draw.line([312, 538, 228, 458], fill=(198, 162, 98, 255), width=9)
draw.ellipse([222, 452, 236, 466], fill=(208, 172, 108, 255))

# Right arm to tom area
draw.polygon([(592, 608), (618, 618), (692, 498), (665, 482)], fill=(68, 138, 208, 255))
draw.ellipse([662, 475, 705, 515], fill=(228, 182, 142, 255))
draw.line([682, 495, 758, 412], fill=(198, 162, 98, 255), width=9)
draw.ellipse([752, 406, 766, 420], fill=(208, 172, 108, 255))

# ── HEAD ─────────────────────────────────────────────────────────────────────
hcx, hcy = 510, 468
hrx, hry = 102, 118

# Neck
draw.rectangle([hcx-28, hcy+hry-12, hcx+28, hcy+hry+52], fill=(218, 172, 132, 255))

# Face
draw.ellipse([hcx-hrx, hcy-hry, hcx+hrx, hcy+hry], fill=(232, 188, 148, 255))

# ── HAIR ─────────────────────────────────────────────────────────────────────
draw.ellipse([hcx-hrx, hcy-hry, hcx+hrx, hcy-18], fill=(22, 18, 16, 255))
draw.ellipse([hcx-hrx-12, hcy-hry+28, hcx-hrx+38, hcy+18], fill=(22, 18, 16, 255))
draw.ellipse([hcx+hrx-38, hcy-hry+28, hcx+hrx+12, hcy+18], fill=(22, 18, 16, 255))
draw.ellipse([hcx-62, hcy-hry+3, hcx+62, hcy-48], fill=(28, 22, 18, 255))
# Tuft
draw.polygon([(hcx-20, hcy-hry+5), (hcx+20, hcy-hry+5),
              (hcx+12, hcy-hry-22), (hcx-12, hcy-hry-22)], fill=(22, 18, 16, 255))

# ── HEADPHONES ───────────────────────────────────────────────────────────────
steps = 14
for i in range(steps + 1):
    t = i / steps
    px = int((hcx - hrx - 18) + t * (hrx * 2 + 36))
    py = int(hcy - hry - 18 + math.sin(math.pi * t) * (-28))
    draw.ellipse([px-8, py-8, px+8, py+8], fill=(18, 18, 22, 255))

draw.ellipse([hcx-hrx-30, hcy-62, hcx-hrx+20, hcy+12], fill=(14, 14, 18, 255))
draw.ellipse([hcx-hrx-24, hcy-56, hcx-hrx+14, hcy+6], fill=(32, 32, 38, 255))
draw.ellipse([hcx+hrx-20, hcy-62, hcx+hrx+30, hcy+12], fill=(14, 14, 18, 255))
draw.ellipse([hcx+hrx-14, hcy-56, hcx+hrx+24, hcy+6], fill=(32, 32, 38, 255))

# ── FACE FEATURES ────────────────────────────────────────────────────────────
# Sunglasses
gly = hcy - 14
draw.rounded_rectangle([hcx-77, gly-23, hcx-8, gly+23], radius=10, fill=(135, 88, 18, 228))
draw.rounded_rectangle([hcx-77, gly-23, hcx-8, gly+23], radius=10, outline=(78, 48, 8, 255), width=4)
draw.rounded_rectangle([hcx+8, gly-23, hcx+77, gly+23], radius=10, fill=(135, 88, 18, 228))
draw.rounded_rectangle([hcx+8, gly-23, hcx+77, gly+23], radius=10, outline=(78, 48, 8, 255), width=4)
draw.line([hcx-8, gly, hcx+8, gly], fill=(78, 48, 8, 255), width=5)
draw.line([hcx-77, gly+2, hcx-hrx-8, gly+6], fill=(78, 48, 8, 255), width=4)
draw.line([hcx+77, gly+2, hcx+hrx+8, gly+6], fill=(78, 48, 8, 255), width=4)
# Lens shine
draw.ellipse([hcx-70, gly-17, hcx-52, gly-5], fill=(255, 232, 148, 75))
draw.ellipse([hcx+15, gly-17, hcx+33, gly-5], fill=(255, 232, 148, 75))

# Nose
draw.ellipse([hcx-13, hcy+6, hcx+13, hcy+30], fill=(212, 168, 128, 255))

# Smile
draw.arc([hcx-42, hcy+22, hcx+42, hcy+66], start=12, end=168, fill=(155, 75, 55, 255), width=7)
draw.arc([hcx-32, hcy+25, hcx+32, hcy+60], start=22, end=158, fill=(255, 252, 248, 195), width=5)

# Cheeks
draw.ellipse([hcx-82, hcy+16, hcx-46, hcy+42], fill=(232, 148, 128, 72))
draw.ellipse([hcx+46, hcy+16, hcx+82, hcy+42], fill=(232, 148, 128, 72))

# ── Glow overlay ─────────────────────────────────────────────────────────────
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for rad in range(220, 0, -12):
    alpha = int(15 * (1 - rad / 220))
    gd.ellipse([90-rad, 70-rad, 90+rad, 70+rad], fill=(255, 252, 235, alpha))
glow.putalpha(mask)
img = Image.alpha_composite(img, glow)

# ── Apply mask ────────────────────────────────────────────────────────────────
out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
out.paste(img, (0, 0), mask)

out.save("C:/Proyectos/nava_drummer/assets/icon/app_icon.png")
out.save("C:/Proyectos/nava_drummer/assets/icon/app_icon_fg.png")
print("Done: app_icon.png and app_icon_fg.png saved (1024x1024)")
