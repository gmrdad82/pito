import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';

// ── Tokyo Night palette ──────────────────────────────────────────
const T = {
  bg:      '#1a1b26', fg:      '#c0caf5', muted:   '#565f89',
  accent:  '#7aa2f7', green:   '#9ece6a', red:     '#f7768e',
  orange:  '#ff9e64', yellow:  '#e0af68', purple:  '#bb9af7',
  border:  '#292e42', cyan:     '#1abc9c',
  sbarBg:  '#16171f',
};

// ── Terminal ─────────────────────────────────────────────────────
const term = new Terminal({
  cursorBlink: true, cursorStyle: 'bar', fontSize: 14,
  fontFamily: 'ui-monospace, "Cascadia Code", "Source Code Pro", Consolas, monospace',
  lineHeight: 1.0, scrollback: 10000, allowProposedApi: true,
  theme: {
    background: T.bg, foreground: T.fg, cursor: T.fg, selectionBackground: '#33467c',
    black: T.bg, red: T.red, green: T.green, yellow: T.yellow,
    blue: T.accent, magenta: T.purple, cyan: T.cyan, white: T.fg,
    brightBlack: T.muted, brightRed: '#ff9e9e', brightGreen: '#b9f27c',
    brightYellow: '#ffc777', brightBlue: '#7dcfff', brightMagenta: '#c099ff',
    brightCyan: '#86e1fc', brightWhite: '#ffffff',
  },
});

const fit = new FitAddon();
term.loadAddon(fit);
term.loadAddon(new WebLinksAddon());
term.open(document.getElementById('terminal'));

// ── ANSI helpers ─────────────────────────────────────────────────
const CSI = '\x1b[';
const cu  = (r,c) => CSI + r + ';' + c + 'H';
const clr = () => CSI + '2K';
const sgr = (n) => CSI + n + 'm';
const c256 = (r,g,b) => CSI + '38;2;' + r + ';' + g + ';' + b + 'm';
const bg256 = (r,g,b) => CSI + '48;2;' + r + ';' + g + ';' + b + 'm';

function rgb(s) { const m = s.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i); return m ? [parseInt(m[1],16),parseInt(m[2],16),parseInt(m[3],16)] : [192,202,245]; }
function c(s) { const [r,g,b] = rgb(s); return c256(r,g,b); }
function bg(s) { const [r,g,b] = rgb(s); return bg256(r,g,b); }
const R = sgr(0);
const B = sgr(1), D = sgr(2);
const M = c(T.muted), A = c(T.accent), G = c(T.green), RD = c(T.red), O = c(T.orange), F = c(T.fg);

function muted(s) { return M + s + R; }
function accent(s) { return A + s + R; }
function green(s) { return G + s + R; }
function red(s) { return RD + s + R; }
function orange(s) { return O + s + R; }
function bold(s) { return B + s + R; }
function w(s) { term.write(s); }

// ── State ────────────────────────────────────────────────────────
let channels = [];
let sidebarOpen = true;
const mainLines = [];

// ── Layout ───────────────────────────────────────────────────────
let cols, rows;
function resize() { cols = term.cols; rows = term.rows; }
const HEADER_H = 1, STATUS_H = 1, INPUT_H = 1;
const SIDEBAR_W = 36;

function mainH() { return rows - HEADER_H - INPUT_H - STATUS_H; }

function drawFrame() {
  resize();
  const sh = mainH();

  // Header
  w(clr() + cu(1,1) + bg(T.sbarBg) + F);
  const chanStr = channels.length > 0
    ? channels.map(ch => accent('@'+ch.channel_url)).join(' ') + ' '
    : muted('no channels connected');
  const hPad = Math.max(0, cols - chanStr.length - muted('pito').length - 2);
  w(chanStr + ' '.repeat(hPad) + muted('pito') + R);

  // Main area
  const visible = mainLines.slice(Math.max(0, mainLines.length - sh));
  for (let i = 0; i < sh; i++) {
    w(cu(HEADER_H + 1 + i, 1) + clr());
    if (i < visible.length) w(F + visible[i] + R);
  }

  // Sidebar divider
  if (sidebarOpen && cols > SIDEBAR_W) {
    const divider = cols - SIDEBAR_W - 1;
    for (let i = 0; i < sh; i++) w(cu(HEADER_H + 1 + i, divider + 1) + bg(T.border) + ' ' + R);
    let sr = HEADER_H + 1;
    w(cu(sr++, cols - SIDEBAR_W) + A + B + 'channels' + R);
    if (channels.length > 0) channels.slice(0,6).forEach(ch => { w(cu(sr++, cols - SIDEBAR_W) + M + '  @'+ch.channel_url + R); });
    else w(cu(sr++, cols - SIDEBAR_W) + M + '  (none)' + R);
    sr++;
    w(cu(sr++, cols - SIDEBAR_W) + A + B + 'videos' + R);
    w(cu(sr++, cols - SIDEBAR_W) + M + '  (use /videos)' + R);
    sr++;
    w(cu(sr++, cols - SIDEBAR_W) + A + B + 'games' + R);
    w(cu(sr++, cols - SIDEBAR_W) + M + '  (use /games)' + R);
  }

  // Input line
  const ir = rows - STATUS_H - 1;
  w(clr() + cu(ir, 1) + bg(T.sbarBg) + F + accent('> ') + cmdBuffer + R);

  // Status bar
  w(clr() + cu(rows, 1) + bg(T.sbarBg) + F + green('●') + ' ' + muted('connected') + '  ' + muted('sidekiq') + ' ' + green('b0') + ' ' + orange('e0') + ' ' + red('r0') + ' ' + muted('d0') + ' '.repeat(Math.max(0, cols - 50)) + muted(new Date().toLocaleTimeString()) + R);
}

// ── Command ──────────────────────────────────────────────────────
let cmdBuffer = '';
const cmdHistory = [];

term.onData(data => {
  const code = data.charCodeAt(0);
  if (code === 13) {
    mainLines.push(accent('> ') + cmdBuffer);
    if (cmdBuffer.trim()) { cmdHistory.push(cmdBuffer); exec(cmdBuffer.trim()); }
    cmdBuffer = ''; drawFrame();
  } else if (code === 127) { cmdBuffer = cmdBuffer.slice(0, -1); drawFrame(); }
  else if (code === 9) { sidebarOpen = !sidebarOpen; drawFrame(); }
  else if (data >= ' ' && data <= '~') { cmdBuffer += data; drawFrame(); }
});

async function exec(cmd) {
  if (cmd.startsWith('/')) await apiCmd(cmd.slice(1));
  else if (cmd === 'help') mainLines.push(muted('  /help /status /channels /videos /auth /reindex /games /config'));
  else if (cmd === 'clear') mainLines.length = 0;
  else mainLines.push(muted('  unknown: ' + cmd + ' — try /help'));
  drawFrame();
}

async function apiCmd(cmd) {
  const [action, ...args] = cmd.split(/\s+/);
  switch (action) {
    case 'help':
      mainLines.push(bold('commands:'));
      mainLines.push('  ' + accent('/status') + '     ' + muted('dashboard'));
      mainLines.push('  ' + accent('/channels') + '   ' + muted('list channels'));
      mainLines.push('  ' + accent('/videos') + '     ' + muted('recent videos'));
      mainLines.push('  ' + accent('/auth') + '       ' + muted('login (6-digit TOTP)'));
      mainLines.push('  ' + accent('/reindex') + '    ' + muted('meilisearch|voyage'));
      mainLines.push('  ' + accent('/games') + '      ' + muted('upcoming releases'));
      mainLines.push('  ' + accent('/config') + '     ' + muted('show settings'));
      mainLines.push('  Tab              ' + muted('toggle sidebar'));
      break;
    case 'status':
      try { const r = await fetch('/dashboard.json'); const d = await r.json();
        mainLines.push(bold('dashboard:'));
        mainLines.push('  channels  ' + green(d.channel_count));
        mainLines.push('  videos    ' + green(d.video_count));
        mainLines.push('  footage   ' + green(d.footage_count));
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    case 'channels':
      try { const r = await fetch('/channels.json'); const d = await r.json();
        channels = d;
        mainLines.push(bold('channels ('+d.length+'):'));
        d.forEach(c => mainLines.push('  ' + (c.star ? accent('★') : ' ') + ' ' + accent(c.channel_url)));
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    case 'videos':
      try { const r = await fetch('/videos.json'); const d = await r.json();
        mainLines.push(bold('videos ('+d.length+'):'));
        d.slice(0,30).forEach(v => mainLines.push('  ' + v.youtube_video_id + ' ' + muted('·') + ' ' + green(v.views) + ' views'));
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    case 'auth':
      if (!args[0] || args[0].length !== 6) { mainLines.push(muted('  usage: /auth <6-digit-code>')); break; }
      try { const r = await fetch('/login', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded','X-CSRF-Token':csrf()}, body:'code='+args[0], redirect:'manual' });
        mainLines.push((r.ok||r.status===302) ? green('  authenticated') : red('  login failed'));
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    case 'reindex':
      if (!args[0] || !['meilisearch','voyage'].includes(args[0])) { mainLines.push(muted('  usage: /reindex meilisearch|voyage')); break; }
      try { const r = await fetch('/commands/execute', { method:'POST', headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()}, body:JSON.stringify({command:'reindex '+args[0]}) });
        const d = await r.json();
        mainLines.push(d.error ? red('  '+d.error) : green('  '+d.output));
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    case 'games':
      try { const r = await fetch('/commands/execute', { method:'POST', headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()}, body:JSON.stringify({command:'games'}) });
        const d = await r.json();
        if (d.error) { mainLines.push(red('  '+d.error)); }
        else { mainLines.push(bold('upcoming games:')); d.output.split('\n').forEach(l => mainLines.push('  '+l)); }
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    case 'config':
      try { const r = await fetch('/commands/execute', { method:'POST', headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()}, body:JSON.stringify({command:'config'}) });
        const d = await r.json();
        if (d.error) { mainLines.push(red('  '+d.error)); }
        else { mainLines.push(bold('config:')); d.output.split('\n').forEach(l => mainLines.push('  '+l)); }
      } catch(e) { mainLines.push(red('  error: '+e.message)); }
      break;
    default:
      mainLines.push(muted('  unknown: /'+action+' — try /help'));
  }
  drawFrame();
}

function csrf() { const m = document.querySelector('meta[name="csrf-token"]'); return m ? m.getAttribute('content') : ''; }

// ── Boot ─────────────────────────────────────────────────────────
function boot() {
  fit.fit(); resize();
  mainLines.push(''); mainLines.push(bold('pito') + '  ' + muted('YouTube channel management'));
  mainLines.push(muted('  type /help for commands, /auth <code> to login'));
  mainLines.push(muted('  Tab toggles sidebar')); mainLines.push('');
  drawFrame();
}
window.addEventListener('resize', () => { fit.fit(); resize(); drawFrame(); });
setTimeout(boot, 100);
