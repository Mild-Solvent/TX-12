// levels.txt -> GDASH/L<n>.lua ; segments bottom-aligned, "~N" = N empty columns
const fs=require("fs");
const src=fs.readFileSync(process.argv[2],"utf8").replace(/\r/g,"").split("\n");
const out=process.argv[3]; fs.mkdirSync(out,{recursive:true});
let levels={},cur=null,seg=[];
function flush(){ if(!cur||!seg.length)return; const w=Math.max(...seg.map(s=>s.length));
  const lines=seg.map(s=>s.replace(/ /g,".").padEnd(w,"."));
  if(lines.length>6) throw new Error("segment >6 rows in level "+cur.n);
  for(let r=0;r<6;r++){ const li=lines.length-1-r; cur.rows[r]+= li>=0?lines[li]:".".repeat(w);} seg=[]; }
for(const l of src){
  if(l.startsWith("= ")){flush(); cur={n:+l.slice(2),rows:["","","","","",""]}; levels[cur.n]=cur; continue;}
  if(l.startsWith("! ")){const p=l.slice(2).split(" "); cur.u=p[0]; cur.m=p.slice(1).join(" "); continue;}
  if(l.startsWith("~")){flush(); const n=+l.slice(1); for(let r=0;r<6;r++)cur.rows[r]+=".".repeat(n); continue;}
  if(l.trim()===""){flush(); continue;}
  seg.push(l);
}
flush();
for(const k in levels){ const rows=levels[k].rows.map(r=>r.replace(/\.+$/,""));
  const len=Math.max(...levels[k].rows.map(r=>r.length));
  // last row keeps full length so the level end is fixed
  rows[0]=levels[k].rows[0];
  const s="-- Geometry Dash level "+k+": rows bottom (ground) to top, tiles see GDASH/phys.lua\n-- u = seconds per music unit, m = looping tune: note+octave+length, R<n> = rest\nreturn {\n"+rows.map(r=>JSON.stringify(r)).join(",\n")+(levels[k].m?",\nu = "+levels[k].u+",\nm = "+JSON.stringify(levels[k].m):"")+"\n}\n";
  fs.writeFileSync(out+"/L"+k+".lua",s); console.log("L"+k, "cols",len, "bytes",s.length);
  for(let r=5;r>=0;r--) console.log("  "+levels[k].rows[r]);
}
