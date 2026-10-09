import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';

const directory = resolve(process.argv[2] ?? '../docs/live-validation/fal-animations/pet');
const sequences = [];
for (const kind of ['playful', 'run', 'sleep']) {
  let assetDirectory = kind, manifest;
  try { manifest = JSON.parse(await readFile(join(directory, kind, 'animation.json'), 'utf8')); }
  catch (error) {
    if (kind !== 'playful' || error.code !== 'ENOENT') throw error;
    assetDirectory = 'lick'; // Keep older local captures previewable.
    manifest = JSON.parse(await readFile(join(directory, assetDirectory, 'animation.json'), 'utf8'));
  }
  sequences.push({ kind, assetDirectory, fps: manifest.fps, frames: manifest.frames, duration: manifest.duration });
}
await writeFile(join(directory, 'preview.html'), `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>My Fur Baby · Animation preview</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f8f3ef;color:#342b3c;font:16px system-ui,sans-serif;padding:40px 24px}main{max-width:1120px;margin:auto}h1{font-size:36px;letter-spacing:-1px;margin:0 0 12px}p{line-height:1.55;color:#6b6071}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px;margin:28px 0}.card{background:white;border-radius:24px;padding:18px;box-shadow:0 8px 24px #342b3c08}h2{margin:0;font-size:21px}.meta{font-size:13px;margin:8px 0 14px}canvas{display:block;width:100%;height:auto;border-radius:16px;background-color:#ede6f2;background-image:linear-gradient(45deg,#fff8 25%,transparent 25%),linear-gradient(-45deg,#fff8 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#fff8 75%),linear-gradient(-45deg,transparent 75%,#fff8 75%);background-size:32px 32px;background-position:0 0,0 16px,16px -16px,-16px 0}button{border:0;background:#d6527b;color:white;padding:12px 20px;border-radius:30px;font:600 15px system-ui;cursor:pointer}button:disabled{opacity:.5}button:focus-visible,input:focus-visible,a:focus-visible{outline:3px solid #6333a4;outline-offset:4px}input{width:100%;accent-color:#d6527b}.controls{display:flex;align-items:center;gap:18px;flex-wrap:wrap}.frame{font-variant-numeric:tabular-nums;font-size:13px;color:#6b6071}a{color:#8b396b}.original{width:92px;height:92px;object-fit:contain;background:white;border-radius:16px}.source{display:flex;align-items:center;gap:18px}@media(max-width:750px){.grid{grid-template-columns:1fr}body{padding:24px 16px}h1{font-size:28px}}
</style>
<main><h1>A little life, one continuous motion.</h1><p>Three animations from the same saved pet. Every frame keeps the complete transparent 512 × 512 canvas.</p><div class="source"><img class="original" src="original.png" alt="Original purple pet with pink collar"><span>Original cutout preserved<br><small>PixVerse V6 → VEED → RGBA PNG frames</small></span></div><div class="grid" id="grid"></div><div class="controls"><button id="play" disabled>Loading frames…</button><label><input type="checkbox" id="loop" checked> Loop playback</label></div><p>These are full sequences at 15 FPS. The current Home Screen widget uses four sampled poses per mood. Loop seams still need review.</p><p id="status" role="status">Loading animation frames…</p></main>
<script>
const sequences=${JSON.stringify(sequences)};
const names={playful:'Playful',run:'Running',sleep:'Sleeping'};
let playing=false, looping=true, origin=performance.now(), stopped=0;
const players=sequences.map(s=>{
 const card=document.createElement('section');card.className='card';
 card.innerHTML='<h2>'+names[s.kind]+'</h2><p class="meta">'+s.duration+' seconds · '+s.frames.length+' frames · '+s.fps+' FPS</p><canvas width="512" height="512" aria-label="'+names[s.kind]+' animation"></canvas><p class="frame"></p><label>Inspect frame<input aria-label="'+names[s.kind]+' frame" type="range" min="0" max="'+(s.frames.length-1)+'" value="0"></label><a href="'+s.assetDirectory+'/animation.json">Frame metadata</a>';
 document.getElementById('grid').append(card);
 const p={...s,canvas:card.querySelector('canvas'),label:card.querySelector('.frame'),range:card.querySelector('input'),images:[]};
 p.range.oninput=()=>{playing=false;document.getElementById('play').textContent='Play from start';draw(p,+p.range.value)};
 return p;
});
function draw(p,i){if(!p.images[i])return;const c=p.canvas.getContext('2d');c.clearRect(0,0,512,512);c.drawImage(p.images[i],0,0,512,512);p.label.textContent='Frame '+String(i+1).padStart(2,'0')+' / '+p.frames.length;p.range.value=i;}
function tick(now){if(playing){const elapsed=(now-origin)/1000;for(const p of players){const i=looping?Math.floor(elapsed*p.fps)%p.frames.length:Math.min(p.frames.length-1,Math.floor(elapsed*p.fps));if(p.range.value!=i)draw(p,i)}if(!looping&&elapsed>=Math.max(...players.map(p=>p.duration))){playing=false;document.getElementById('play').textContent='Play from start';}}requestAnimationFrame(tick);}
const button=document.getElementById('play');button.onclick=()=>{if(playing){stopped=performance.now()-origin;playing=false;button.textContent='Play from start'}else{origin=performance.now();playing=true;button.textContent='Pause'}};
document.getElementById('loop').onchange=e=>looping=e.target.checked;
Promise.all(players.map(async p=>{p.images=await Promise.all(p.frames.map(file=>new Promise((ok,no)=>{const image=new Image();image.onload=()=>ok(image);image.onerror=no;image.src=p.assetDirectory+'/'+file})));draw(p,0)})).then(()=>{button.disabled=false;button.textContent='Pause';origin=performance.now();playing=true;document.getElementById('status').textContent='165 transparent frames loaded. Pause or scrub to inspect alignment.';requestAnimationFrame(tick)}).catch(()=>document.getElementById('status').textContent='Some frames could not load. Serve this folder locally and reload.');
</script></html>`);
console.log('Saved preview.html. Serve the pet directory locally to review playback.');
