from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math, sys

bundle = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
out = bundle / 'branding'
out.mkdir(parents=True, exist_ok=True)
S=1024
img=Image.new('RGBA',(S,S),(8,35,105,255))
p=img.load()
for y in range(S):
    for x in range(S):
        dx=(x-S*0.35)/S; dy=(y-S*0.25)/S
        r=min(1, math.sqrt(dx*dx+dy*dy)*1.5)
        p[x,y]=(int(12+18*(1-r)), int(55+95*(1-r)), int(135+100*(1-r)),255)
mask=Image.new('L',(S,S),0); md=ImageDraw.Draw(mask); md.rounded_rectangle((15,15,S-15,S-15),radius=210,fill=255)
img.putalpha(mask)
d=ImageDraw.Draw(img)
for yy in range(650,980,55): d.arc((120,520,900,1180),200,340,fill=(80,190,255,85),width=2)
for xx in range(160,900,90): d.arc((xx-220,540,xx+220,980),80,280,fill=(80,190,255,55),width=2)
pts=[(250,330),(350,650),(465,430),(565,650),(690,330),(620,330),(560,520),(468,345),(365,520),(310,330)]
d.polygon(pts, fill=(245,250,255,255))
d.polygon([(565,650),(690,330),(620,330),(560,520),(468,345),(515,515)], fill=(50,205,255,255))
d.arc((190,210,835,790),205,345,fill=(85,225,255,245),width=18)
cx,cy=792,300
for r,w,a in [(38,8,255),(20,15,255)]:
    d.line((cx-r,cy,cx+r,cy),fill=(255,255,255,a),width=w)
    d.line((cx,cy-r,cx,cy+r),fill=(255,255,255,a),width=w)
font_path=Path(r'C:\Windows\Fonts\seguisb.ttf')
font=ImageFont.truetype(str(font_path),74) if font_path.exists() else ImageFont.load_default()
label='WEST BEAUTY'
bbox=d.textbbox((0,0),label,font=font); tw=bbox[2]-bbox[0]
d.text(((S-tw)/2,760),label,font=font,fill=(235,250,255,245))
img.save(out/'app.png')
for sz in [16,24,32,48,64,128,256,512]:
    img.resize((sz,sz),Image.Resampling.LANCZOS).save(out/f'icon-{sz}.png')
img.save(out/'app.ico',format='ICO',sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
print('Branding generated in',out)
