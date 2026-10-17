#!/usr/bin/env python3
"""The keyboard themes' reference renderer: an HTML page that draws every
theme (light and dark) with its faces, legends and ornaments exactly as
docs/THEMES.md and shared/themes/styles.py describe them. The iPhone and
Android keyboards must match it; compare screenshots against it.

    python3 tools/theme_mock.py [id,id,...] [out.html]

Serve the output over http (the textures load as data URLs; the fonts too)
and open it in a browser.
"""
import json, base64, os, sys
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = json.load(open(R + '/shared/themes/themes.json'))
only = sys.argv[1].split(',') if len(sys.argv) > 1 and sys.argv[1] else None
if only:
    T = [t for t in T if t['id'] in only]
tex = {}
for f in os.listdir(R + '/shared/themes/textures'):
    tex[f[:-4]] = 'data:image/png;base64,' + base64.b64encode(open(R + '/shared/themes/textures/' + f, 'rb').read()).decode()
fonts = {}
FD = R + '/app/ios/GlyfKeyboard/Fonts/'
for t in T:
    f = t['font']
    if f.get('family', 'system') != 'system':
        file = f['file']
        if '[' in file and not f['rfn']:
            file = '%s-%s.ttf' % (file.split('[')[0], {400: 'Regular', 500: 'Medium', 600: 'SemiBold'}[f['weight']])
        if not os.path.exists(FD + file):
            file = {'IM Fell English': 'IMFeENrm28P.ttf'}.get(f['family'], file)
        fonts[f['family']] = 'data:font/ttf;base64,' + base64.b64encode(open(FD + file, 'rb').read()).decode()
css = '\n'.join("@font-face{font-family:'%s';src:url(%s);}" % (k, v) for k, v in fonts.items())
html = '''<!doctype html><html><head><meta charset="utf-8"><title>Theme finishes</title><style>%s
body{margin:0;background:#fff;font:14px -apple-system,system-ui}
.row{display:flex;gap:8px;padding:4px 8px}
.t{font:600 15px -apple-system;margin:8px 12px 0}
canvas{width:385px;height:198px;border-radius:14px}
</style></head><body><div id="root"></div><script>
const THEMES=%s, TEX=%s;
const SHEET={light:'#E2E4E8',dark:'#1B1B1D'};
const imgs={};
function load(){return Promise.all(Object.entries(TEX).map(([k,v])=>new Promise(r=>{const i=new Image();i.onload=()=>{imgs[k]=i;r()};i.src=v})));}
function rgb(h){h=h.replace('#','');return [0,2,4].map(i=>parseInt(h.substr(i,2),16))}
function lum(h){const c=rgb(h).map(v=>{v/=255;return v<=0.04045?v/12.92:Math.pow((v+0.055)/1.055,2.4)});return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]}
function rr(c,x,y,w,h,r){c.beginPath();c.moveTo(x+r,y);c.arcTo(x+w,y,x+w,y+h,r);c.arcTo(x+w,y+h,x,y+h,r);c.arcTo(x,y+h,x,y,r);c.arcTo(x,y,x+w,y,r);c.closePath()}
function a(h,al){const [r,g,b]=rgb(h);return `rgba(${r},${g},${b},${al})`}
function drawFace(c,x,y,w,h,fill,f,mode,S){
  if(f.shape=='round'){
    const d=w, cx=x+w/2, cy=y+h/2, R=d/2;
    // the keycap's drop shadow, the chrome bezel, then the face
    c.beginPath();c.arc(cx,cy+1.4*S,R,0,7);c.fillStyle='rgba(0,0,0,'+(mode=='dark'?0.6:0.30)+')';c.fill();
    const ring=f.ring[mode];const g0=c.createLinearGradient(0,cy-R,0,cy+R);g0.addColorStop(0,'#F4F4F2');g0.addColorStop(0.45,ring);g0.addColorStop(0.55,'#6E6E6A');g0.addColorStop(1,'#D8D8D4');
    c.beginPath();c.arc(cx,cy,R,0,7);c.fillStyle=g0;c.fill();
    const ri=R-2.4*S;
    c.save();c.beginPath();c.arc(cx,cy,ri,0,7);c.clip();
    c.fillStyle=fill;c.fillRect(cx-R,cy-R,2*R,2*R);
    if(f.texture&&imgs[f.texture]){c.globalAlpha=f.textureAlpha;c.fillStyle=c.createPattern(imgs[f.texture],'repeat');c.fillRect(cx-R,cy-R,2*R,2*R);c.globalAlpha=1}
    const g=c.createRadialGradient(cx,cy-ri*0.35,ri*0.1,cx,cy,ri);g.addColorStop(0,'rgba(255,255,255,'+f.gloss+')');g.addColorStop(0.7,'rgba(255,255,255,0)');g.addColorStop(1,'rgba(0,0,0,'+(f.sheen[1]+0.06)+')');
    c.fillStyle=g;c.fillRect(cx-R,cy-R,2*R,2*R);c.restore();
    return;
  }
  const r=9.5*S;
  // shadow edge
  rr(c,x,y+1*S,w,h,r); c.fillStyle='rgba(0,0,0,'+(mode=='dark'?0.55:0.28)+')'; c.fill();
  c.save(); rr(c,x,y,w,h,r); c.clip();
  if(f.fill2){const g=c.createLinearGradient(x,y,x+w,y+h);g.addColorStop(0,fill);g.addColorStop(1,f.fill2[mode]);c.fillStyle=g}else c.fillStyle=fill;
  c.fillRect(x,y,w,h);
  if(f.texture&&imgs[f.texture]){c.globalAlpha=f.textureAlpha;c.fillStyle=c.createPattern(imgs[f.texture],'repeat');c.fillRect(x,y,w,h);c.globalAlpha=1}
  if(f.sheen[0]||f.sheen[1]){const g=c.createLinearGradient(0,y,0,y+h);g.addColorStop(0,'rgba(255,255,255,'+f.sheen[0]+')');g.addColorStop(0.5,'rgba(255,255,255,0)');g.addColorStop(0.5,'rgba(0,0,0,0)');g.addColorStop(1,'rgba(0,0,0,'+f.sheen[1]+')');c.fillStyle=g;c.fillRect(x,y,w,h)}
  if(f.metal){for(const [p,s] of [[0.22,0.10],[0.58,0.16],[0.84,0.08]]){const g=c.createLinearGradient(0,y+h*(p-s),0,y+h*(p+s));g.addColorStop(0,'rgba(255,255,255,0)');g.addColorStop(0.5,'rgba(255,255,255,'+f.metal+')');g.addColorStop(1,'rgba(255,255,255,0)');c.fillStyle=g;c.fillRect(x,y+h*(p-s),w,h*2*s)}}
  if(f.gloss){const g=c.createLinearGradient(0,y,0,y+h*0.48);g.addColorStop(0,'rgba(255,255,255,'+f.gloss+')');g.addColorStop(1,'rgba(255,255,255,0)');c.fillStyle=g;c.fillRect(x,y,w,h*0.48)}
  if(f.highlight){c.fillStyle='rgba(255,255,255,'+f.highlight+')';c.fillRect(x,y,w,1)}
  c.restore();
}
function legendText(c,txt,cx,cy,font,ink,fill,lg,S){
  c.font=font;c.textAlign='center';c.textBaseline='middle';
  const light=lum(fill)>0.45;
  if(lg.style=='engraved'||lg.style=='letterpress'){
    if(light){c.fillStyle='rgba(255,255,255,0.75)';c.fillText(txt,cx,cy+0.7*S)}else{c.fillStyle='rgba(0,0,0,0.6)';c.fillText(txt,cx,cy-0.6*S)}
  }
  if(lg.style=='letterpress'){c.save();c.shadowColor=a(ink,0.55);c.shadowBlur=0.6*S;c.fillStyle=ink;c.fillText(txt,cx,cy);c.restore();return}
  if(lg.style=='foil'){
    c.fillStyle='rgba(0,0,0,0.45)';c.fillText(txt,cx,cy-0.6*S);
    const m=c.measureText(txt);const t=cy-m.actualBoundingBoxAscent,b=cy+m.actualBoundingBoxDescent;
    const g=c.createLinearGradient(0,t,0,b);g.addColorStop(0,lg.foil[0]);g.addColorStop(0.55,lg.foil[1]);g.addColorStop(1,lg.foil[2]);c.fillStyle=g;c.fillText(txt,cx,cy);return}
  if(lg.style=='glow'){c.save();c.shadowColor=a(ink,0.9);c.shadowBlur=6*S;c.fillStyle=ink;c.fillText(txt,cx,cy);c.fillText(txt,cx,cy);c.restore();return}
  c.fillStyle=ink;c.fillText(txt,cx,cy);
}
function roleColor(role,v,cls,fill){
  if(role&&role[0]=='#')return role;
  return {ink:cls=='function'?v.functionGlyph:v.keyText,fnInk:v.functionGlyph,accent:v.returnPrimary.fill,accentInk:v.returnPrimary.text,fill:fill}[role]||v.keyText;
}
function ornaments(c,v,on,x,y,w,h,cls,fill,mode,fam,S){
  for(const o of v.style.ornaments){
    const hit=o.on==on||(o.on=='function'&&cls=='function'&&on!=='return');
    if(!hit)continue;
    const ax=o.anchor=='left'?x:o.anchor=='right'?x+w:x+w/2;
    c.save();rr(c,x,y,w,h,9.5*S);c.clip();
    for(const p of o.ops){
      const col=roleColor(p.color||o.color,v,cls,fill);c.globalAlpha=(p.color&&p.color[0]=='#'&&o.alpha<0.9)?Math.max(o.alpha,0.9):o.alpha;
      const X=u=>ax+u*h,Y=u=>y+u*h;
      c.strokeStyle=col;c.fillStyle=col;c.lineCap='round';
      if(p.t=='line'){c.lineWidth=p.w*h;c.beginPath();c.moveTo(X(p.p[0]),Y(p.p[1]));c.lineTo(X(p.p[2]),Y(p.p[3]));c.stroke()}
      else if(p.t=='poly'){c.beginPath();for(let i=0;i<p.p.length;i+=2){i?c.lineTo(X(p.p[i]),Y(p.p[i+1])):c.moveTo(X(p.p[i]),Y(p.p[i+1]))}c.closePath();c.fill()}
      else if(p.t=='circle'){c.beginPath();c.arc(X(p.p[0]),Y(p.p[1]),p.p[2]*h,0,7);if(p.w){c.lineWidth=p.w*h;c.stroke()}else c.fill()}
      else if(p.t=='rect'){rr(c,X(p.p[0]),Y(p.p[1]),p.p[2]*h,p.p[3]*h,Math.max(0.01,p.p[4]*h));if(p.w){c.lineWidth=p.w*h;c.stroke()}else c.fill()}
      else if(p.t=='text'){const ff=p.font=='mono'?'Menlo':p.font=='theme'?("'"+fam+"'"):'-apple-system';c.font=`${p.weight} ${p.size*h}px ${ff}`;c.textAlign='center';c.textBaseline='middle';c.fillText(p.s,X(p.p[0]),Y(p.p[1]))}
    }
    c.restore();c.globalAlpha=1;
  }
}
function kb(t,mode){
  const S=3,W=440,H=226,cv=document.createElement('canvas');cv.width=W*S;cv.height=H*S;const c=cv.getContext('2d');
  const v=t.variants[mode],st=v.style;c.fillStyle=SHEET[mode];c.fillRect(0,0,W*S,H*S);
  const fam=t.font.family&&t.font.family!='system'?t.font.family:null;
  const LF=(sz)=>`400 ${sz*S}px ${fam?("'"+fam+"'"):'-apple-system'}`;
  const kw=(440-13-54)/10,kh=45,rowp=56,top=12;
  const key=(x,yy,w,cls,label,on)=>{
    const X=x*S,Y=yy*S,Wd=w*S,Hd=kh*S;
    let fill,ink,f=st.faces[cls=='letter'?'letter':cls=='space'?'space':cls=='return'?'return':'function'];
    if(cls=='letter'){fill=v.letterKey.fill;ink=v.keyText}
    else if(cls=='space'){fill=v.spaceKey.fill;ink=v.keyText}
    else if(cls=='return'){fill=v.returnPrimary.fill;ink=v.returnPrimary.text}
    else {const o=v.keyOverrides[on];fill=o?o.fill:v.functionKey.fill;ink=o?o.glyph:v.functionGlyph}
    drawFace(c,X,Y,Wd,Hd,fill,f,mode,S);
    ornaments(c,v,on||cls,X,Y,Wd,Hd,cls,fill,mode,fam,S);
    if(label){const isL=cls=='letter';legendText(c,label,X+Wd/2,Y+Hd/2+(isL?0:0),isL?LF(24.5):`400 ${(label=='123'?17:20)*S}px -apple-system`,ink,fill,st.legend,S)}
    if(cls=='space'){c.font=`400 ${15*S}px -apple-system`;c.textAlign='center';c.textBaseline='middle';c.fillStyle=a(v.keyText,0.4);c.fillText('glyf',X+Wd/2,Y+Hd/2)}
  };
  'qwertyuiop'.split('').forEach((ch,i)=>key(6.5+i*(kw+6),top,kw,'letter',ch));
  const off=6.5+(kw+6)/2;'asdfghjkl'.split('').forEach((ch,i)=>key(off+i*(kw+6),top+rowp,kw,'letter',ch));
  const sw=kw*1.35;key(6.5,top+2*rowp,sw,'function','⇧','shift');
  const x3=(440-7*kw-36)/2;'zxcvbnm'.split('').forEach((ch,i)=>key(x3+i*(kw+6),top+2*rowp,kw,'letter',ch));
  key(440-6.5-sw,top+2*rowp,sw,'function','⌫','delete');
  const y4=top+3*rowp,w1=kw*1.35+4;key(6.5,y4,w1,'function','123','mode');key(6.5+w1+6,y4,w1,'function','☺','emoji');
  const rw=kw*2.6,sx=6.5+2*(w1+6),sp=440-6.5-rw-6-sx;key(sx,y4,sp,'space','', 'space');key(440-6.5-rw,y4,rw,'return','⏎','return');
  return cv;
}
load().then(()=>Promise.all(Object.keys(%s).map(f=>document.fonts.load(`40px "${f}"`))) ).then(()=>{const root=document.getElementById('root');for(const t of THEMES){const d=document.createElement('div');d.innerHTML='<div class="t">'+t.name+'</div>';const r=document.createElement('div');r.className='row';r.appendChild(kb(t,'light'));r.appendChild(kb(t,'dark'));d.appendChild(r);root.appendChild(d)}document.title='ready';});
</script></body></html>''' % (css, json.dumps(T), json.dumps(tex), json.dumps(fonts and {k: 1 for k in fonts}))
open(sys.argv[2] if len(sys.argv) > 2 else 'theme-mock.html', 'w').write(html)
print('ok', len(html))
