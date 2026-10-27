import sys
from PIL import Image
for p in sys.argv[1:]:
    lines=open(p).read().split('\n')
    w,h=map(int,lines[1].split())
    im=Image.new('RGB',(w,h))
    for y in range(h):
        row=lines[2+y]
        for x in range(w):
            im.putpixel((x,y),(20,30,60) if row[x]=='1' else (170,210,230))
    im=im.resize((w*4,h*4),Image.NEAREST)
    # combine later
    im.save(p[:-4]+'.png')
