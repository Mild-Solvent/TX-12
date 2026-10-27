import sys
from PIL import Image
o=sys.argv[1]; fs=sys.argv[2:]
ims=[Image.open(f) for f in fs]; cols=min(3,len(ims)); rows=(len(ims)+cols-1)//cols
w,h=ims[0].size; c=Image.new('RGB',(cols*(w+8),rows*(h+8)),'white')
for k,i in enumerate(ims): c.paste(i,((k%cols)*(w+8),(k//cols)*(h+8)))
c.save(o)
