#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw

paths = [Path(p) for p in __import__('sys').argv[1:]]
if len(paths) < 2:
    raise SystemExit('usage: make_contact_sheet.py <img...> <out>')
out = paths[-1]
imgs = [Image.open(p).convert('RGB') for p in paths[:-1]]
thumbs = []
for img in imgs:
    t = img.copy()
    t.thumbnail((260, 420))
    card = Image.new('RGB', (280, 440), (245, 245, 250))
    x = (280 - t.width) // 2
    y = (440 - t.height) // 2
    card.paste(t, (x, y))
    thumbs.append(card)
cols = 2
rows = (len(thumbs) + cols - 1) // cols
sheet = Image.new('RGB', (cols * 300, rows * 460), (255, 255, 255))
for i, card in enumerate(thumbs):
    x = (i % cols) * 300 + 10
    y = (i // cols) * 460 + 10
    sheet.paste(card, (x, y))
sheet.save(out)
print(out)
