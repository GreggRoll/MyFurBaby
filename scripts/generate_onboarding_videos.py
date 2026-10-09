"""Build bundled, silent onboarding demos from the existing validated pet assets.
Requires Pillow and ffmpeg. These are demo previews, not recordings of widget motion.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import math, subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/live-validation'
OUT = ROOT / 'Resources/Onboarding'
OUT.mkdir(parents=True, exist_ok=True)
SIZE, FPS = 720, 24
INK, PINK, CREAM, LAVENDER = '#30263b', '#eb5c85', '#fcf7ed', '#dcd1f7'
FONT = '/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf'
def font(size): return ImageFont.truetype(FONT, size)
def label(image, text, xy, size=26, fill=INK): ImageDraw.Draw(image).text(xy, text, font=font(size), fill=fill)
def asset(name, size): return ImageOps.contain(Image.open(SOURCE / name).convert('RGBA'), size)
pet = asset('pet.png', (270, 270))
sleep = [asset(f'sleep-frame-{i}.png', (420, 420)) for i in range(1, 5)]
photo = Image.open(SOURCE / 'photo-adventure.png').convert('RGB')

def adventure(t):
    if t < 3.5:
        zoom = 1.0 + 0.04 * math.sin(t / 3.5 * math.pi)
        side = round(SIZE * zoom)
        image = ImageOps.fit(photo, (side, side))
        delta = (side - SIZE) // 2
        image = image.crop((delta, delta, delta + SIZE, delta + SIZE))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((28, 28, 435, 86), 29, fill=CREAM)
        label(image, 'Adventure, anywhere.', (49, 43), 26)
        return image
    image = Image.new('RGB', (SIZE, SIZE), LAVENDER)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((50, 145, 670, 647), 40, fill='white')
    label(image, 'Or a cozy day together.', (102, 65), 34)
    frame = sleep[int((t - 3.5) * 3) % 4]
    image.paste(frame, ((SIZE-frame.width)//2, 195), frame)
    label(image, 'Just happy to be with you.', (160, 580), 25)
    return image

def widgets(t):
    image = Image.new('RGB', (SIZE, SIZE), CREAM)
    draw = ImageDraw.Draw(image)
    label(image, 'A little closer, always.', (116, 35), 37)
    # Two actual supported layouts; the camera glide demonstrates their sizes.
    rise = round(10 * math.sin(t * math.pi / 3.5))
    draw.rounded_rectangle((62, 124 + rise, 315, 377 + rise), 38, fill='white')
    small = pet.resize((213, 213))
    image.paste(small, (82, 130 + rise), small)
    label(image, 'Mochi', (91, 338 + rise), 22)
    label(image, 'SMALL', (367, 211), 27, PINK)
    label(image, 'Their own little', (367, 256), 24)
    label(image, 'corner.', (367, 288), 24)
    draw.rounded_rectangle((62, 431 - rise, 658, 675 - rise), 38, fill='white')
    medium = pet.resize((217, 217))
    image.paste(medium, (77, 443 - rise), medium)
    label(image, 'MEDIUM', (332, 470 - rise), 20, PINK)
    label(image, 'Mochi', (332, 513 - rise), 36)
    label(image, 'A little love, always.', (332, 567 - rise), 21)
    return image

for name, render in [('onboarding-adventures', adventure), ('onboarding-widgets', widgets)]:
    args = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', f'{SIZE}x{SIZE}', '-framerate', str(FPS), '-i', '-', '-an', '-c:v', 'libx264', '-crf', '23', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(OUT / (name + '.mp4'))]
    process = subprocess.Popen(args, stdin=subprocess.PIPE)
    for frame in range(FPS * 7): process.stdin.write(render(frame / FPS).tobytes())
    process.stdin.close()
    if process.wait(): raise RuntimeError('ffmpeg failed')
    catalog = ROOT / 'Resources/Assets.xcassets' / (name + '.imageset')
    catalog.mkdir(exist_ok=True)
    render(0).save(catalog / 'poster.jpg', quality=90)
    (catalog / 'Contents.json').write_text('{"images":[{"filename":"poster.jpg","idiom":"universal"}],"info":{"author":"xcode","version":1}}\n')
    print(OUT / (name + '.mp4'))
