import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';

const T={bg:'#1a1b26',fg:'#c0caf5',mu:'#565f89',ac:'#7aa2f7',gr:'#9ece6a',rd:'#f7768e',or:'#ff9e64',bd:'#292e42',sb:'#16171f'};
const term=new Terminal({cursorBlink:true,cursorStyle:'bar',fontSize:16,fontFamily:'ui-monospace,"Cascadia Code","Source Code Pro",Consolas,monospace',lineHeight:1,scrollback:10000,allowProposedApi:true,theme:{background:T.bg,foreground:T.fg,cursor:T.fg,selectionBackground:'#33467c',black:T.bg,red:T.rd,green:T.gr,yellow:T.or,blue:T.ac,magenta:T.rd,cyan:T.gr,white:T.fg,brightBlack:T.mu,brightRed:'#ff9e9e',brightGreen:'#b9f27c',brightYellow:'#ffc777',brightBlue:'#7dcfff',brightMagenta:'#c099ff',brightCyan:'#86e1fc',brightWhite:'#ffffff'}});
const fit=new FitAddon();term.loadAddon(fit);term.loadAddon(new WebLinksAddon());
term.open(document.getElementById('terminal'));
term.attachCustomKeyEventHandler(e=>{if(e.type==='keydown'&&e.key==='Tab'){e.preventDefault();sidebarOpen=!sidebarOpen;draw();return false;}return true;});

const CSI='\x1b[',c256=(r,g,b)=>CSI+'38;2;'+r+';'+g+';'+b+'m',cbg=(r,g,b)=>CSI+'48;2;'+r+';'+g+';'+b+'m';
const R=CSI+'0m',B=CSI+'1m';
const co=s=>{const m=s.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);if(!m)return CSI+'39m';return c256(parseInt(m[1],16),parseInt(m[2],16),parseInt(m[3],16));};
const bo=s=>{const m=s.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);if(!m)return CSI+'49m';return cbg(parseInt(m[1],16),parseInt(m[2],16),parseInt(m[3],16));};
const S=(c,f,b)=>(b?bo(b):'')+(f?co(f):'')+c+R;

let channels=[],sidebarOpen=true,statusData=null,sidebarData=null,log=[],cmdBuffer='';
const SW=30;

function draw(){
  const c=term.cols,r=term.rows;
  if(c<20||r<6)return;
  const mw=c-(sidebarOpen?SW+1:0),sh=r-3;

  const out=[];

  // Header
  let h='';
  if(channels.length>0)h=channels.map(ch=>S('@'+ch.channel_url,T.ac)).join(' ')+' ';
  out.push(S((h+S('pito',T.mu)).padEnd(c),T.fg,T.sb));

  // Main + sidebar rows
  const vis=log.slice(Math.max(0,log.length-sh));
  for(let i=0;i<sh;i++){
    let l=i<vis.length?S(vis[i],T.fg):'';
    l=l.padEnd(mw);
    if(sidebarOpen&&c>SW+1){
      l+=S(' ',null,T.bd)+sbLine(i);
    }
    out.push(l);
  }

  // Input
  out.push(S(('> '+cmdBuffer).padEnd(c),T.fg,T.sb));

  // Status
  const sk=statusData&&statusData.sidekiq?statusData.sidekiq:{enqueued:0,retry:0,dead:0,scheduled:0};
  const conn=statusData&&statusData.connected!==false;
  let sl='';
  sl+=(conn?S('●',T.gr):S('●',T.rd))+' ';
  sl+=S('connected  sidekiq ',T.mu);
  sl+=S('b'+sk.enqueued,T.gr)+' '+S('e'+sk.retry,T.or)+' '+S('r'+sk.dead,T.rd)+' '+S('d'+sk.scheduled,T.mu);
  const time=new Date().toLocaleTimeString();
  sl+=S(time.padStart(c-sl.replace(/\x1b\[[0-9;]*m/g,'').length-time.length),T.mu);
  out.push(S(sl,T.fg,T.sb));

  term.write(CSI+'H'+out.join('\r\n')+CSI+'0J');
}

function sbLine(i){
  const sw=SW;
  if(i===0)return S('channels'.padEnd(sw),T.ac)+B;
  if(i===1){
    if(sidebarData&&sidebarData.channels&&sidebarData.channels.length>0){
      const t=sidebarData.channels.length;
      const s=sidebarData.channels.filter(x=>x.star).length;
      return S(('  '+t+' total  '+s+' starred').padEnd(sw),T.mu);
    }else if(channels.length>0){
      return S(('  @'+channels[0].channel_url).padEnd(sw),T.mu);
    }
    return S('  (none)'.padEnd(sw),T.mu);
  }
  if(i>=2&&i<7&&sidebarData&&sidebarData.channels&&i-2<sidebarData.channels.length){
    const ch=sidebarData.channels[i-2];
    return S(('  @'+ch.channel_url+' '+gr(ch.video_count||0)+'v').padEnd(sw),T.mu);
  }
  if(i===8)return S('videos'.padEnd(sw),T.ac)+B;
  if(i>=9&&i<14&&sidebarData&&sidebarData.recent_videos&&i-9<sidebarData.recent_videos.length){
    const v=sidebarData.recent_videos[i-9];
    return S(('  '+(v.youtube_video_id||'').substring(0,10)+' '+gr(v.views||0)).padEnd(sw),T.mu);
  }
  if(i===15)return S('games'.padEnd(sw),T.ac)+B;
  if(i>=16&&i<21&&sidebarData&&sidebarData.upcoming_games&&i-16<sidebarData.upcoming_games.length){
    const g=sidebarData.upcoming_games[i-16];
    return S(('  '+(g.title||g)+' '+mu(g.release_date||'')).padEnd(sw),T.mu);
  }
  return ' '.repeat(sw);
}
function gr(n){return S(String(n||0),T.gr);}
function mu(s){return S(s||'',T.mu);}

// ── Command ──────────────────────
term.onData(d=>{
  const k=d.charCodeAt(0);
  if(k===13){log.push(S('> '+cmdBuffer,T.ac));if(cmdBuffer.trim())exec(cmdBuffer.trim());cmdBuffer='';draw();}
  else if(k===127){cmdBuffer=cmdBuffer.slice(0,-1);draw();}
  else if(d>=' '&&d<='~'){cmdBuffer+=d;draw();}
});
function exec(c){
  if(c.startsWith('/'))apiCmd(c.slice(1));
  else if(c==='help')log.push(S('  /help /status /channels /videos /auth /reindex /games /config',T.mu));
  else if(c==='clear')log.length=0;
  else log.push(S('  unknown: '+c,T.mu));
  draw();
}
async function apiCmd(cmd){
  const[a,...args]=cmd.split(/\s+/);
  switch(a){
    case'help':log.push(S('commands:',T.fg)+B);['status','channels','videos','auth','reindex','games','config'].forEach(x=>log.push('  '+S('/'+x,T.ac)));log.push('  Tab '+S('toggle sidebar',T.mu));break;
    case'status':try{const r=await f('/dashboard.json'),d=await r.json();log.push(S('dashboard:',T.fg)+B);log.push('  channels '+S(d.channel_count,T.gr));log.push('  videos   '+S(d.video_count,T.gr));log.push('  footage  '+S(d.footage_count,T.gr));}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    case'channels':try{const r=await f('/channels.json'),d=await r.json();channels=d;log.push(S('channels ('+d.length+'):',T.fg)+B);d.forEach(c=>log.push('  '+(c.star?S('★',T.ac):' ')+' '+S(c.channel_url,T.ac)));}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    case'videos':try{const r=await f('/videos.json'),d=await r.json();log.push(S('videos ('+d.length+'):',T.fg)+B);d.slice(0,30).forEach(v=>log.push('  '+v.youtube_video_id+' '+S('·',T.mu)+' '+S(v.views,T.gr)+' views'));}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    case'auth':if(!args[0]||args[0].length!==6){log.push(S('  usage: /auth <6-digit-code>',T.mu));break;}try{const r=await f('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-CSRF-Token':csrf()},body:'code='+args[0],redirect:'manual'});log.push((r.ok||r.status===302)?S('  authenticated',T.gr):S('  login failed',T.rd));}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    case'reindex':if(!args[0]||!['meilisearch','voyage'].includes(args[0])){log.push(S('  usage: /reindex meilisearch|voyage',T.mu));break;}try{const r=await f('/commands/execute',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()},body:JSON.stringify({command:'reindex '+args[0]})}),d=await r.json();log.push(d.error?S('  '+d.error,T.rd):S('  '+d.output,T.gr));}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    case'games':try{const r=await f('/commands/execute',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()},body:JSON.stringify({command:'games'})}),d=await r.json();if(d.error)log.push(S('  '+d.error,T.rd));else{log.push(S('games:',T.fg)+B);d.output.split('\n').forEach(l=>log.push('  '+l));}}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    case'config':try{const r=await f('/commands/execute',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()},body:JSON.stringify({command:'config'})}),d=await r.json();log.push(d.error?S('  '+d.error,T.rd):S('  '+d.output,T.gr));}catch(e){log.push(S('  error: '+e.message,T.rd));}break;
    default:log.push(S('  unknown: /'+a,T.mu));
  }
  draw();
}
async function f(url,opts){return fetch(url,opts);}
function csrf(){const m=document.querySelector('meta[name="csrf-token"]');return m?m.getAttribute('content'):'';}

async function ps(){try{const r=await f('/status.json');statusData=await r.json();}catch(e){statusData={connected:false};}draw();}
async function psb(){try{const r=await f('/sidebar.json');sidebarData=await r.json();}catch(e){sidebarData=null;}draw();}

function boot(){
  fit.fit();
  if(term.cols<20||term.rows<6){setTimeout(boot,200);return;}
  log.push('');log.push(S('pito',T.fg)+B+'  '+S('YouTube channel management',T.mu));
  log.push(S('  type /help for commands, /auth <code> to login',T.mu));
  log.push(S('  Tab toggles sidebar',T.mu));log.push('');
  ps();psb();draw();setInterval(ps,5000);setInterval(psb,30000);
}
window.addEventListener('resize',()=>{fit.fit();draw();});
setTimeout(boot,200);
