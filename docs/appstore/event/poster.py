import math, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def hexc(h): return tuple(int(h[i:i+2],16) for i in (0,2,4))

def poster(W,H, seed=7, portrait=False):
    S=2  # supersample
    w,h=W*S,H*S
    img=Image.new("RGB",(w,h))
    # vertical gradient: map teal to ink
    top,mid,bot=hexc("1d3b3f"),hexc("16292d"),hexc("0b0b0c")
    px=img.load()
    grad=Image.new("RGB",(1,h))
    for y in range(h):
        t=y/h
        c=lerp(top,mid,t/0.6) if t<0.6 else lerp(mid,bot,(t-0.6)/0.4)
        grad.putpixel((0,y),c)
    img=grad.resize((w,h))
    d=ImageDraw.Draw(img,"RGBA")
    rnd=random.Random(seed)
    # blocks (buildings) faint
    for _ in range(int(w*h/9000/S/S)):
        x=rnd.randrange(w); y=rnd.randrange(int(h*0.85))
        bw=rnd.randrange(14,60)*S; bh=rnd.randrange(14,50)*S
        d.rectangle([x,y,x+bw,y+bh],fill=(255,255,255,rnd.randrange(5,12)))
    # street grid, slightly rotated
    ang=math.radians(-18)
    def rot(x,y,cx=w/2,cy=h/2):
        x-=cx;y-=cy
        return (cx+x*math.cos(ang)-y*math.sin(ang), cy+x*math.sin(ang)+y*math.cos(ang))
    step=110*S
    for i in range(-30,31):
        a=rot(i*step*0.9+w/2,-h); b=rot(i*step*0.9+w/2,2*h)
        d.line([a,b],fill=(255,255,255,18),width=3*S)
        a=rot(-w,i*step+h/2); b=rot(2*w,i*step+h/2)
        d.line([a,b],fill=(255,255,255,14),width=2*S)
    # river
    pts=[]
    for k in range(0,101):
        t=k/100
        x=-0.1*w+t*1.2*w
        y=(0.72 if not portrait else 0.62)*h+math.sin(t*3.2+0.6)*0.07*h
        pts.append((x,y))
    rl=Image.new("RGBA",(w,h),(0,0,0,0)); ImageDraw.Draw(rl).line(pts,fill=(38,74,150,255),width=int(52*S),joint="curve")
    rl=rl.filter(ImageFilter.GaussianBlur(2*S)); rl.putalpha(rl.getchannel("A").point(lambda v:int(v*0.55)))
    img=Image.alpha_composite(img.convert("RGBA"),rl); d=ImageDraw.Draw(img,"RGBA")
    # transit lines
    def curve(p0,p1,p2,p3,n=120):
        out=[]
        for k in range(n+1):
            t=k/n
            x=(1-t)**3*p0[0]+3*(1-t)**2*t*p1[0]+3*(1-t)*t*t*p2[0]+t**3*p3[0]
            y=(1-t)**3*p0[1]+3*(1-t)**2*t*p1[1]+3*(1-t)*t*t*p2[1]+t**3*p3[1]
            out.append((x,y))
        return out
    lw=int((10 if not portrait else 9)*S)
    def P(fx,fy): return (fx*w,fy*h)
    if not portrait:
        lines=[("0065AE",[P(-0.05,0.18),P(0.3,0.25),P(0.45,0.55),P(1.05,0.6)]),
               ("16C0E9",[P(0.12,-0.05),P(0.25,0.4),P(0.6,0.3),P(0.85,1.05)]),
               ("E8642C",[P(-0.05,0.85),P(0.35,0.7),P(0.65,0.15),P(1.05,0.2)]),
               ("69BE28",[P(0.5,-0.05),P(0.55,0.35),P(0.75,0.5),P(1.05,0.95)])]
    else:
        lines=[("0065AE",[P(-0.05,0.2),P(0.4,0.25),P(0.5,0.5),P(1.05,0.55)]),
               ("16C0E9",[P(0.2,-0.05),P(0.3,0.35),P(0.7,0.3),P(0.8,1.05)]),
               ("E8642C",[P(-0.05,0.7),P(0.3,0.6),P(0.7,0.15),P(1.05,0.1)]),
               ("69BE28",[P(0.6,-0.05),P(0.55,0.3),P(0.8,0.45),P(1.05,0.8)])]
    paths=[]
    for col,cp in lines:
        pts=curve(*cp); paths.append(pts)
        ll=Image.new("RGBA",(w,h),(0,0,0,0)); ImageDraw.Draw(ll).line(pts,fill=hexc(col)+(255,),width=lw,joint="curve")
        ll.putalpha(ll.getchannel("A").point(lambda v:int(v*0.6)))
        img=Image.alpha_composite(img,ll)
    d=ImageDraw.Draw(img,"RGBA")
    # highlighted route: glow
    route=paths[0]
    glow=Image.new("RGBA",(w,h),(0,0,0,0)); gd=ImageDraw.Draw(glow)
    gd.line(route,fill=(80,160,255,200),width=lw*3,joint="curve")
    glow=glow.filter(ImageFilter.GaussianBlur(18*S))
    img=Image.alpha_composite(img.convert("RGBA"),glow)
    d=ImageDraw.Draw(img,"RGBA")
    rt=Image.new("RGBA",(w,h),(0,0,0,0)); rd=ImageDraw.Draw(rt)
    rd.line(route,fill=(255,255,255,255),width=lw+8*S,joint="curve")
    rd.line(route,fill=hexc("4f9dff")+(255,),width=lw,joint="curve")
    img=Image.alpha_composite(img,rt); d=ImageDraw.Draw(img,"RGBA")
    # stations along lines
    for pts in paths:
        for k in range(10,len(pts)-5,26):
            x,y=pts[k]; r=9*S
            d.ellipse([x-r,y-r,x+r,y+r],fill=(255,255,255,235))
    # destination: yellow signature dot
    dx,dy=route[int(len(route)*0.82)]
    r=24*S; d.ellipse([dx-r,dy-r,dx+r,dy+r],fill=(255,255,255,255)); r=13*S; d.ellipse([dx-r,dy-r,dx+r,dy+r],fill=hexc("ffc531"))
    # you: blue dot with beam, at the route start area
    ux,uy=route[int(len(route)*0.3)]
    import numpy as np
    R=230*S
    i0=int(len(route)*0.3)
    tx,ty=route[i0+3][0]-route[i0-3][0], route[i0+3][1]-route[i0-3][1]
    heading=math.atan2(ty,tx)
    yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    dx_,dy_=xx-ux,yy-uy
    dist=np.sqrt(dx_*dx_+dy_*dy_)
    ang=np.arctan2(dy_,dx_)-heading
    ang=(ang+np.pi)%(2*np.pi)-np.pi
    half=math.radians(30)
    edge=np.clip((half-np.abs(ang))/math.radians(8),0,1)   # soft sides
    fall=np.clip(1-dist/R,0,1)**1.4
    a_=(edge*fall*200).astype(np.uint8)
    beam=Image.new("RGBA",(w,h),(80,160,255,0)); beam.putalpha(Image.fromarray(a_,"L"))
    beam=beam.filter(ImageFilter.GaussianBlur(4*S))
    img=Image.alpha_composite(img,beam)
    d=ImageDraw.Draw(img,"RGBA")
    sh=Image.new("RGBA",(w,h),(0,0,0,0)); r=28*S; ImageDraw.Draw(sh).ellipse([ux-r,uy-r+4*S,ux+r,uy+r+4*S],fill=(0,0,0,120))
    img=Image.alpha_composite(img,sh.filter(ImageFilter.GaussianBlur(5*S))); d=ImageDraw.Draw(img,"RGBA")
    r=26*S
    d.ellipse([ux-r,uy-r,ux+r,uy+r],fill=(255,255,255,255)); r=19*S; d.ellipse([ux-r,uy-r,ux+r,uy+r],fill=hexc("0a84ff"))
    # bottom darkening for Apple's text overlay
    shade=Image.new("RGBA",(w,h),(0,0,0,0)); sd=ImageDraw.Draw(shade)
    start=0.55 if not portrait else 0.6
    for y in range(int(h*start),h):
        t=(y-h*start)/(h*(1-start))
        sd.line([(0,y),(w,y)],fill=(11,11,12,int(235*min(1,t**1.3))))
    img=Image.alpha_composite(img,shade)
    # vignette
    vig=Image.new("L",(w,h),0); vd=ImageDraw.Draw(vig)
    vd.ellipse([-w*0.25,-h*0.35,w*1.25,h*1.2],fill=255)
    vig=vig.filter(ImageFilter.GaussianBlur(120*S))
    dark=Image.new("RGBA",(w,h),(0,0,0,255))
    img=Image.composite(img,Image.alpha_composite(img,Image.new("RGBA",(w,h),(0,0,0,110))),vig)
    return img.convert("RGB").resize((W,H),Image.LANCZOS)

card=poster(1920,1080); card.save("event-card-1920x1080.png")
det=poster(1080,1920,portrait=True); det.save("event-details-1080x1920.png")

# Previews with the event text, as the App Store lays it over (only to look at)
def preview(img,name,short,badge,out,portrait=False):
    im=img.copy(); d=ImageDraw.Draw(im)
    W,H=im.size
    f_badge=ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Bold.otf",int(H*(0.026 if not portrait else 0.017)))
    f_name=ImageFont.truetype("/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf",int(H*(0.075 if not portrait else 0.042)))
    f_sub=ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Medium.otf",int(H*(0.034 if not portrait else 0.021)))
    x=int(W*0.05); y=int(H*(0.70 if not portrait else 0.76))
    d.text((x,y),badge,font=f_badge,fill=(255,255,255,180))
    y+=int(f_badge.size*1.6); d.text((x,y),name,font=f_name,fill="white")
    y+=int(f_name.size*1.25); d.text((x,y),short,font=f_sub,fill=(220,220,220))
    im.save(out)
preview(card,"Publit's biggest update","Smarter changes, live maps, your votes","MAJOR UPDATE","preview-card-en.png")
preview(det,"Publit's biggest update","Smarter changes, live maps, your votes","MAJOR UPDATE","preview-details-en.png",portrait=True)
preview(card,"Das große Publit-Update","Schlauer umsteigen, Live-Karten, eure Ideen","GROSSES UPDATE","preview-card-de.png")
print("ok")
