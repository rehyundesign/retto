const fs = require('fs'), path = require('path'), crypto = require('crypto'), vm = require('vm');
const sharp = require('/Users/luxia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const dir = __dirname, root = path.dirname(dir);
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
(async () => {
  const jobs = JSON.parse(fs.readFileSync(path.join(dir, 'jobs-head-only.json')));
  const originalJobs = JSON.parse(fs.readFileSync(path.join(dir, 'jobs.json')));
  const hashes = jobs.map(job => {
    if (!fs.existsSync(job.dest)) throw new Error('Missing gaze direction ' + job.direction);
    return sha(job.dest);
  });
  if (new Set(hashes).size !== 16) throw new Error('Repeated gaze source');
  const records = [];
  for (const job of jobs) {
    const n = String(job.direction).padStart(2, '0');
    const meta = await sharp(job.dest).metadata();
    if (!meta.hasAlpha) throw new Error('Missing alpha ' + n);
    await sharp(job.dest).resize(448, 640, {fit:'fill'}).png().toFile(path.join(dir, n + '.png'));
    records.push({direction:job.direction, label:job.label, row:job.row, column:job.column,
      file:'gaze-v25/' + n + '.png', source:'gaze-v25/' + n + '-source.png',
      sourceSha256:hashes[job.direction], nativeDegrees:job.direction * 22.5,
      generationReferences:[0,4,12].includes(job.direction)?originalJobs[job.direction].refs:job.refs});
  }
  for (const [theme, background] of [['dark','#181827'],['white','#fffdf8']]) {
    const tiles = await Promise.all(records.map(async record => ({
      input:await sharp(path.join(root,record.file)).resize(224,320).png().toBuffer(),
      left:record.direction%4*224, top:Math.floor(record.direction/4)*320
    })));
    await sharp({create:{width:896,height:1280,channels:4,background}}).composite(tiles).png().toFile(path.join(dir,'review-' + theme + '.png'));
  }
  const locks = JSON.parse(fs.readFileSync(path.join(dir,'existing-source-lock.json')));
  for (const record of locks) {
    if (sha(path.join(root,record.file)) !== record.sha256) throw new Error('Existing state changed: ' + record.file);
  }
  fs.writeFileSync(path.join(root,'state-integrated-v25-gaze-data.js'),'window.JeanneGaze25=' + JSON.stringify(records) + ';\n');
  const stateContext = {window:{}};
  vm.runInNewContext(fs.readFileSync(path.join(root,'state-integrated-v24-data.js'),'utf8'), stateContext);
  const stateRows = stateContext.window.JeanneIntegrated19.map(row => {
    const clean = {};
    for (const key of ['id','state','label','files','cycle','times','kind','status','note','animations']) {
      if (row[key] !== undefined) clean[key] = row[key];
    }
    if (row.id.startsWith('drag-')) clean.status = 'v24 일단 사용 승인 · 품질 개선 여지 있음';
    return clean;
  });
  fs.writeFileSync(path.join(root,'state-integrated-v25-data.js'),'window.JeanneIntegrated19=' + JSON.stringify(stateRows) + ';\n');
  let html = fs.readFileSync(path.join(root,'state-integrated-v24.html'),'utf8');
  html = html.replace(/state-integrated-v24-data\.js\?v=\d+/, 'state-integrated-v25-data.js?v=' + Date.now())
    .replace('이번 수정 4개 상태 · 좌우 보행은 각각 8개 원본 자세','16방향 시선 추가 · 좌우 보행은 각각 8개 원본 자세');
  html = html.replace('<h1>잔느 레토 · 보행과 인사 수정</h1>', '<h1>잔느 레토 · 모션과 16방향 시선</h1>')
    .replace('좌우 이동은 선택하신 원본 8개 보행 자세, 완료 인사는 같은 앞발의 올림·내림을 다시 생성했습니다. 점프는 승인한 동작을 참고하면서 주변 이펙트를 줄였습니다.',
      'v24의 10개 상태 모션에 마우스를 따라보는 16방향 시선을 추가했습니다. 좌우 드래그는 일단 사용하기로 한 v24 그림을 유지합니다.')
    .replace("rows.findIndex(r=>r.id==='drag-right')", "rows.findIndex(r=>r.id==='idle')")
    .replace('<div id="states" class="grid"></div>',
      '<section class="hero" style="margin-top:24px"><div id="gaze-area" style="width:380px;height:400px;max-width:100%;display:grid;place-items:center;border:1px dashed #ae879a55;border-radius:12px;touch-action:none"><img id="gaze-image" width="224" height="320" alt="마우스를 따라보는 잔느 레토"></div><div class="details"><h2>마우스 따라보기 · 16방향</h2><p>왼쪽 영역 안에서 커서를 움직이거나 방향을 선택해 보세요.</p><p id="gaze-current">불러오는 중</p><button id="gaze-auto">방향 순서대로 보기</button><div id="gaze-buttons" class="frames"></div><p>시선 그림은 정지 이미지입니다. 같은 방향을 유지하면 이미지에 포함된 이펙트도 멈춥니다.</p></div></section><div id="states" class="grid"></div>');
  html += '\n<script src="state-integrated-v25-gaze-data.js?v=' + Date.now() + '"></script><script src="gaze-v25/preview.js?v=' + Date.now() + '"></script>\n';
  // Keep script elements inside the document rather than after its closing tag.
  html = html.replace('</html>', '');
  html += '</html>\n';
  for (const script of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) new vm.Script(script[1]);
  new vm.Script(fs.readFileSync(path.join(dir,'preview.js'),'utf8'));
  fs.writeFileSync(path.join(root,'state-integrated-v25.html'), html);
  fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify({
    distinctGazeDrawings:16, records, preservedStateDrawings:locks.length,
    declaredGroups:'Stationary seated idle body, genuine head/neck yaw and pitch per direction.',
    integration:'Complete independent drawings, no head/body compositing. Original head crops are reference-only.',
    originalAbsoluteRegistration:'not certified', nativePlayback:'not checked',
    dragAcceptance:'Provisional use of v24; not full quality approval.'
  }, null, 2));
  console.log('16 independent gaze drawings, all144 previous state images preserved, v25 HTML syntax checked.');
})();
