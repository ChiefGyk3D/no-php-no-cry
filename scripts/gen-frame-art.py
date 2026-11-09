#!/usr/bin/env python3
"""Frame art generator (issue 283, docs/borders.md). Writes the faithful button frame art under static/brand/.

faithful: traced from the owner's button art (1332x318 frame box): stepped metallic brackets, end-cap plates with amber dashes, double amber rules, mid-edge split with an amber stub. clean: plain graphite L brackets plus two thin amber rules. Static art, no glow. One SVG per size class (it is applied at 100% by 100%, so it is not stretch-safe); the "-amber" files carry the rules and dashes in ink so they show on a solid amber fill. Usage: scripts/gen-frame-art.py [--check] [outdir]"""
import sys
AMBER="#FBB03B"
TL_OUT=[(0,3),(201,3),(147,52),(97,52),(83,70),(55,70),(54.5,98),(41,112),(38,151),(0,151)]
TL_HOLE=[(21,24),(148,24),(139,32),(91,33),(73,51),(34,52),(33,89),(21,102)]
TOP_PLATE=[(253.3,29.5),(276,2.5),(364,2.5),(379,17),(474,17.5),(456,29.5)]
BOT_PLATE=[(240.7,278.3),(456.7,278.3),(493.3,302.7),(378.3,302.7),(366.7,317.3),(272.7,317.3)]
BOT_WIN=[(266.7,290.7),(376,290.7),(362.7,305.7),(278.3,305.7)]
GRAD=('<linearGradient id="m" x1="0" x2="1" y1="0" y2="0"><stop offset="0" stop-color="#050505"/>'
 '<stop offset=".5" stop-color="#555"/><stop offset="1" stop-color="#1c1c1c"/></linearGradient>')
EDGE='stroke="#8a8a8a" stroke-opacity=".75" stroke-width="{w}" stroke-linejoin="round"'

def f(v): return ("%.2f"%v).rstrip("0").rstrip(".")
def path(polys, fx, fy):
    return "M"+"M".join(" ".join(f"{f(fx(x))},{f(fy(y))}" for x,y in p).replace(" ","L",0) for p in polys) if False else \
      " ".join("M"+" L".join(f"{f(fx(x))} {f(fy(y))}" for x,y in p)+"Z" for p in polys)
RULE=[AMBER]
FILL=[None]   # (color, opacity) of the fill drawn inside the art, or None
def rrect(x,y,w,h,fill=None):
    fill=fill or RULE[0]
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(min(h,w)/2)}" fill="{fill}"/>'

def shape(polys, fx, fy, mirror_x, mirror_y, W, H, ew):
    X=(lambda x:W-fx(x)) if mirror_x else fx
    Y=(lambda y:H-fy(y)) if mirror_y else fy
    return f'<path d="{path(polys,X,Y)}" fill="url(#m)" fill-rule="evenodd" {EDGE.format(w=ew)}/>'

def reduced_bracket(a,b,t):
    out=[(0,0),(a,0),(a-1.2*t,t),(3.4*t,t),(2.4*t,2*t),(t,2*t),(t,b),(0,b)]
    return [out]

def clean_bracket(a,b,t):
    return [[(0,0),(a,0),(a,t),(t,t),(t,b),(0,b)]]

def svg(W,H,level,rule=AMBER,hs=None,fill=None):
    RULE[0]=rule
    FILL[0]=fill
    if level=="none":
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" preserveAspectRatio="none"/>'
    h0=hs or H   # the height the frame is scaled to; a tall box keeps the bracket size of a shorter one
    s=h0/318.0
    o=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" preserveAspectRatio="none"><defs>{GRAD}</defs>']
    small=H<60
    ew=max(.7,.9*min(1,s*3))
    if level=="clean":
        t=max(3,h0*.06); a=max(16,min(h0*.5,W*.16)); b=max(12,min(h0*.42,H/2-3))
        rt=max(1.5,h0*.012); ry=max(5,h0*.075)
        rule=lambda y,x1,x2:f'<rect x="{f(x1)}" y="{f(y)}" width="{f(x2-x1)}" height="{f(rt)}" fill="{RULE[0]}"/>'
        o.append(rule(ry,a+4,W-a-4)); o.append(rule(H-ry-rt,a+4,W-a-4))
        br=clean_bracket(a,b,t)
        for mx in (0,1):
            for my in (0,1):
                o.append(shape(br,lambda x:x,lambda y:y,mx,my,W,H,ew))
        o.append('</svg>'); return "".join(o)
    # faithful
    sx=sy=s
    # plate scale / placement
    sp=min(s,(W/2-6-240.7*s)/252.6)
    Xl=240.7*s
    if sp<s:
        Xl=200*s; sp=max(.04,min(s,(W/2-6-Xl)/252.6))
    spy=sp
    if small:
        spy=max(sp,.26)   # keep plates tall enough to carry a dash
    # vertical anchoring helpers
    def px(x): return Xl+(x-240.7)*sp
    rt=max(1.5,6*s) if not small else 1.5
    if small:
        # reduced: rules and plates compressed into the top/bottom 9px
        ry1=1.0; ry2=1+rt+2.2
        yl_top=ry2; 
    else:
        ry1=1*s; ry2=18*s
    yl_top=ry2
    yl_bot=H-ry2-rt
    ys_top=ry1
    ys_bot=H-ry1-rt
    # rules (behind everything)
    lx1,lx2=180*s,W-180*s
    if small: lx1,lx2=22,W-22
    sx1=max(.287*W,px(379)+4); sx2=W-sx1
    o.append(rrect(lx1,yl_top,lx2-lx1,rt)); o.append(rrect(lx1,yl_bot,lx2-lx1,rt))
    # the short rules sit on the outer edge, outside the fill: always amber, so they show on the dark ground
    o.append(rrect(sx1,ys_top,sx2-sx1,rt,AMBER)); 
    if not small: o.append(rrect(sx1,ys_bot,sx2-sx1,rt,AMBER))
    # brackets
    if small:
        t=4.2; a=max(26,min(H*1.0,W*.24)); b=H/2-1.2
        br=reduced_bracket(max(a,22),b,t)
    else:
        br=[TL_OUT,TL_HOLE]
    bfx=(lambda x:x) if small else (lambda x:x*s)
    bfy=(lambda y:y) if small else (lambda y:y*s)
    if FILL[0]:
        # The fill is part of the art, clipped to the brackets' inner outline, so a box's own
        # background never shows past the chamfered frame (issue 285). It is drawn first, under
        # every rule and plate, and stays strictly inside the viewBox on all four sides.
        o.insert(1, fill_poly(br[0],bfx,bfy,W,H,FILL[0]))
    for mx in (0,1):
        for my in (0,1):
            o.append(shape(br,bfx,bfy,mx,my,W,H,ew))
    # bracket dashes + mid stub + outer dashes
    dh=max(1.6,6*s)
    for mx in (0,1):
        for my in (0,1):
            if small and my: continue
            x=33*s if not small else 5.5; w=43*s if not small else 9
            y=31*s if not small else 4.2
            xx=W-x-w if mx else x
            yy=H-y-dh if my else y
            if not small or True: o.append(rrect(xx,yy,w,dh))
    if not small:
        for mx in (0,1):
            x=13*s; w=max(1.5,5*s); xx=W-x-w if mx else x
            o.append(f'<rect x="{f(xx)}" y="{f(151*s)}" width="{f(w)}" height="{f(H-302*s)}" fill="{AMBER}"/>')   # the mid-edge stub is outside the fill: amber
        for mx in (0,1):
            for my in (0,1):
                x=212*s; w=42*s; xx=W-x-w if mx else x
                if my: continue
                o.append(rrect(xx,H-6*s-3*s-dh+6*s-dh*0 -(318*s-318*s)-(0),w,dh)) if False else o.append(rrect(xx,309*s+(H-318*s),w,dh))
    # plates
    for mx in (0,1):
        def X(x): 
            v=px(x); return W-v if mx else v
        # top plate
        ty=2.5*s-2.5*spy
        if small: ty=0.8-2.5*spy
        pts=[(X(x),ty+y*spy) for x,y in TOP_PLATE]
        d="M"+" L".join(f"{f(a)} {f(b)}" for a,b in pts)+"Z"
        o.append(f'<path d="{d}" fill="url(#m)" {EDGE.format(w=ew)}/>')
        dx0=X(284.5); dx1=X(357)
        x0=min(dx0,dx1); w=abs(dx1-dx0)
        o.append(rrect(x0,ty+14.5*spy,w,max(1.6,6.25*spy),AMBER))
        if not small:
            # bottom plate with window
            by=lambda y:H-(2.5*s-2.5*spy)- (y-0)*0 if False else None
            off=H-(318*s) # zero when s=H/318
            ty2=317.3*s-317.3*spy
            def Yb(y): return ty2+y*spy+off
            pts=[(X(x),Yb(y)) for x,y in BOT_PLATE]
            win=[(X(x),Yb(y)) for x,y in BOT_WIN]
            d="M"+" L".join(f"{f(a)} {f(b)}" for a,b in pts)+"Z M"+" L".join(f"{f(a)} {f(b)}" for a,b in win)+"Z"
            o.append(f'<path d="{d}" fill="url(#m)" fill-rule="evenodd" {EDGE.format(w=ew)}/>')
            dx0=X(395); dx1=X(460)
            o.append(rrect(min(dx0,dx1),Yb(290),abs(dx1-dx0),max(1.6,6*spy),AMBER))
    o.append('</svg>'); return "".join(o)

def fill_poly(out,fx,fy,W,H,fill):
    """Inner vertices of the four corner brackets, clockwise: the outline the fill follows."""
    pts=[(fx(x),fy(y)) for x,y in out]
    y0=min(y for _,y in pts)
    chains=[]
    for mx,my,rev in ((0,0,1),(1,0,0),(1,1,1),(0,1,0)):
        c=[(W-x if mx else x, H-y if my else y) for x,y in pts if x>0 and y>y0]
        chains.append(c[::-1] if rev else c)
    allp=[p for c in chains for p in c]
    d="M"+" L".join(f"{f(x)} {f(y)}" for x,y in allp)+"Z"
    color,op=fill
    return f'<path d="{d}" fill="{color}" fill-opacity="{op}"/>'

# The fills are the site tints (--frame-fill .16 and --frame-fill-hover .26 in borders.css; scripts/test-borders.sh keeps them equal).
FILLS={"button":(AMBER,".16"),"tile":(AMBER,".16")}
TILE_HOVER=(AMBER,".26")
SIZES=[("button",140,44,None),("tile",330,79,None)]


def files():
    for name,W,H,hs in SIZES:
        for lv in ("faithful",):
            # the fill is inside the art: a tint (a ghost button, a support tile and its brighter hover) or solid amber (the primary button)
            yield f"frame-{lv}-{name}.svg", svg(W,H,lv,hs=hs,fill=FILLS[name])
            if name=="tile":
                yield f"frame-{lv}-{name}-hover.svg", svg(W,H,lv,hs=hs,fill=TILE_HOVER)   # one tint step brighter
            else:
                yield f"frame-{lv}-{name}-amber.svg", svg(W,H,lv,"#2D200B",hs,fill=(AMBER,"1"))


if __name__=="__main__":
    import os
    args=[a for a in sys.argv[1:] if a!="--check"]
    out=args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","static","brand")
    bad=0
    for fn,data in files():
        p=os.path.join(out,fn)
        if "--check" in sys.argv:
            if not os.path.exists(p) or open(p).read()!=data:
                print("stale:",fn); bad=1
        else:
            open(p,"w").write(data)
    sys.exit(bad)
