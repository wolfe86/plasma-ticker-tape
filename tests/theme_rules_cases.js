// The theme rules of 2026-10-26 -- pattern matching, the runner test and the
// record-based heat -- on made-up sessions. Prints "ok"/"FAIL" per case and
// exits non-zero on a failure. Run by test_theme_rules.py; needs Node.js.
const fs = require("fs"), path = require("path"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "..", "package", "contents", "ui", "themes.js"), "utf8")
    .replace(/^\s*\.pragma library\s*$/m, "")
const c = {};vm.createContext(c);vm.runInContext(src+";this.T={tune,status,readDay,isRunner,emptyDay,themeMatches,starterThemes,annotate}",c);const T=c.T
const t=T.tune({}); let fails=0
const ok=(name,v)=>{ if(!v){fails++;console.log("FAIL",name)} else console.log("ok  ",name) }
const th=id=>T.starterThemes.find(x=>x.id===id)
// matching
ok("AI by headline", T.themeMatches(th("ai"),{headline:"Acme signs GPU deal with NVIDIA"}))
ok("AI not by unrelated", !T.themeMatches(th("ai"),{headline:"Acme reports Q3"}))
ok("nonews needs news===false", T.themeMatches(th("nonews"),{news:false}) && !T.themeMatches(th("nonews"),{news:null}) && !T.themeMatches(th("nonews"),{news:true}))
ok("foreign low float", T.themeMatches(th("foreignlf"),{country:"China",float:3e6}) && !T.themeMatches(th("foreignlf"),{country:"USA",float:3e6}) && !T.themeMatches(th("foreignlf"),{country:"China",float:30e6}) && !T.themeMatches(th("foreignlf"),{country:"",float:3e6}))
ok("oil by industry", T.themeMatches(th("oil"),{industry:"Oil & Gas E&P",headline:""}))
ok("defense by industry or words", T.themeMatches(th("defense"),{industry:"Aerospace & Defense"}) && T.themeMatches(th("defense"),{headline:"wins drone contract",industry:"Software"}))
// runner rule
ok("30% with news runs", T.isRunner({peak:35,news:true,rvol:6},t))
ok("35% no news does not", !T.isRunner({peak:35,news:false,rvol:6},t))
ok("65% no news runs", T.isRunner({peak:65,news:false,rvol:6},t))
ok("thin volume does not", !T.isRunner({peak:80,news:true,rvol:2},t))
ok("unknown rvol passes", T.isRunner({peak:40,news:null,rvol:NaN},t))
// record
const day=(d,ran)=>{const m={};for(let i=0;i<ran;i++)m["S"+i]={peak:50,news:true,rvol:9};const r=ran?T.readDay(m,t):T.emptyDay(d);r.d=d;r.led=false;return r}
const ds=["2026-10-19","2026-10-20","2026-10-21","2026-10-22","2026-10-23"]
const st=(pattern)=>{const h=pattern.map((n,i)=>day(ds[i]||("2026-11-0"+i),n));return T.status(h.slice(0,-1),h[h.length-1],t,{live:false}).status}
ok("1 of 5 building", st([0,0,0,0,1])==="building")
ok("2 of 5 building", st([0,1,0,0,1])==="building")
ok("3 of 5 hot", st([1,0,1,0,1])==="hot")
ok("0 of 5 quiet", st([0,0,0,0,0])==="quiet")
// stays hot: hot then quiet days with 1 runner in 5
const long=[1,1,1,0,0,0,0,1,0,0,0,0,0]; const h=long.map((n,i)=>{const r=day("2026-10-"+String(10+i).padStart(2,"0"),n);return r})
T.annotate(h,t); ok("stays hot while 1 in 5", h[7].hot && h[10].hot)
ok("drops after none in 5", !h[12].hot)
const bh=long.map((n,i)=>day("2026-10-"+String(1+i).padStart(2,"0"),n)).concat([day("2026-10-28",0)])
ok("burnt after 14 days", T.status(bh.slice(0,-1),bh[bh.length-1],t,{}).status==="burnt")
// broad pattern with high usual rate does not go hot from scratch
const broad=[];for(let i=0;i<20;i++)broad.push(day("2026-09-"+String(1+i).padStart(2,"0"),i%2))
const tail=[day("2026-10-01",1),day("2026-10-02",0),day("2026-10-03",1),day("2026-10-04",1),day("2026-10-05",0)]
broad.forEach(d=>d.hot=false); const all=broad.concat(tail); tail.slice(0,-1).forEach(d=>d.hot=false); 
const s1=T.status(all.slice(0,-1),all[all.length-1],t,{}); ok("broad usual rate blocks hot ("+s1.status+")", s1.status!=="hot"); const nar=Array.from({length:20},(_,i)=>{const d=day("2026-09-"+String(1+i).padStart(2,"0"),0);d.hot=false;return d}).concat(tail.map(d=>Object.assign({},d,{hot:undefined}))); nar.slice(20,24).forEach(d=>d.hot=false); ok("rare theme with 3 of 5 goes hot", T.status(nar.slice(0,-1),nar[nar.length-1],t,{}).status==="hot")
console.log(fails?fails+" failed":"all passed")
process.exit(fails ? 1 : 0)
