"""Render the application's simple geometric icon at native toolbar/app sizes.
The matching editable vector master is Design/icon.svg. Pillow is needed only for rebuilding assets.
"""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
def render(size):
    scale=8 if size<128 else 2
    pixels=size*scale; unit=pixels/128
    image=Image.new('RGBA',(pixels,pixels)); draw=ImageDraw.Draw(image)
    def bounds(value):return tuple(round(x*unit) for x in value)
    draw.rounded_rectangle(bounds((6,6,122,122)),radius=round(28*unit),fill='#14272C',outline='#29444A',width=max(1,round(unit)))
    draw.rounded_rectangle(bounds((27,28,101,83)),radius=round(14*unit),fill='#72EBC8')
    draw.polygon([tuple(round(x*unit) for x in point) for point in [(56,42),(56,70),(79,56)]],fill='#14272C')
    draw.rounded_rectangle(bounds((29,95,99,100)),radius=max(1,round(2.5*unit)),fill='#36545A')
    draw.rounded_rectangle(bounds((29,95,76,100)),radius=max(1,round(2.5*unit)),fill='#72EBC8')
    return image.resize((size,size),Image.Resampling.LANCZOS)
icons=ROOT/'extension/icons';icons.mkdir(exist_ok=True)
for size in (16,32,48,128):render(size).save(icons/f'icon{size}.png')
iconset=ROOT/'Icon.iconset';iconset.mkdir(exist_ok=True)
for size,names in {16:['icon_16x16.png'],32:['icon_16x16@2x.png','icon_32x32.png'],64:['icon_32x32@2x.png'],128:['icon_128x128.png'],256:['icon_128x128@2x.png','icon_256x256.png'],512:['icon_256x256@2x.png','icon_512x512.png'],1024:['icon_512x512@2x.png']}.items():
    for name in names:render(size).save(iconset/name)
render(512).save(ROOT/'Design/icon-preview.png')
