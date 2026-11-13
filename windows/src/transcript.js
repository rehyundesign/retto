// 말풍선에 쓸 문장과 세션 이름을 트랜스크립트에서 직접 읽는다.
//
// 맥 앱 Sessions.swift 의 TranscriptReader · assistantText 와 PetView.swift 의 bodyText · detailText 를 옮긴 것이다.
// 훅은 도구를 부를 때만 돌아서, 도구 없이 긴 글을 쓰는 동안에는 말풍선이 멈춰 있었다. 화면에 고른 세션의 파일만,
// 끝 512KB 만 읽고, 크기·수정 시각이 그대로면 다시 읽지 않는다. 읽은 뒤 접근 시각을 되돌린다 — 레토가 읽은
// 흔적이 「사람이 열어 읽음」으로 잡히지 않게.

const fs = require('node:fs');

const SPAN = 512 * 1024;

/// Claude 와 Codex 는 같은 말을 다른 모양으로 적는다. 훅의 assistantTextIn 과 같은 규칙이다.
function assistantText(record) {
  let message = null;
  if (record?.type === 'assistant') message = record.message;
  else if (record?.type === 'response_item' && record.payload?.type === 'message' && record.payload.role === 'assistant') message = record.payload;
  const content = Array.isArray(message?.content) ? message.content : [];
  return content.filter((part) => part?.type === 'text' || part?.type === 'output_text')
    .map((part) => part.text).filter((text) => typeof text === 'string').join(' ').trim();
}

/// 끝에서부터 훑어 가장 최근 문장과 이름(사용자가 붙인 이름 → Claude 가 붙인 이름)을 찾는다.
function parseTail(chunk) {
  let message = '';
  let customTitle = null;
  let aiTitle = '';
  const lines = chunk.split('\n');
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i];
    if (!message && line.includes('"assistant"')) {
      try { const text = assistantText(JSON.parse(line)); if (text) message = [...text].slice(0, 400).join(''); } catch {}
    }
    if ((customTitle == null || !aiTitle) && line.includes('-title')) {
      try {
        const record = JSON.parse(line);
        // 사용자가 이름을 지우면 빈 custom-title 이 적힌다. 그것도 최신 뜻으로 받는다.
        if (customTitle == null && record.type === 'custom-title') customTitle = typeof record.customTitle === 'string' ? record.customTitle : '';
        if (!aiTitle && record.type === 'ai-title') aiTitle = typeof record.aiTitle === 'string' ? record.aiTitle : '';
      } catch {}
    }
    if (message && customTitle != null && aiTitle) break;
  }
  const title = customTitle ? customTitle : aiTitle;
  return { message, title: [...title].slice(0, 80).join('') };
}

class TranscriptReader {
  constructor() { this.cache = { path: '', size: 0, mtimeMs: 0, message: '', title: '' }; }
  read(filePath) {
    if (!filePath) return { message: '', title: '' };
    let stat;
    try { stat = fs.statSync(filePath); } catch { return { message: '', title: '' }; }
    const c = this.cache;
    if (c.path === filePath && c.size === stat.size && c.mtimeMs === stat.mtimeMs) return { message: c.message, title: c.title };
    let chunk = '';
    try {
      const fd = fs.openSync(filePath, 'r');
      try {
        const start = stat.size > SPAN ? stat.size - SPAN : 0;
        const buffer = Buffer.alloc(stat.size - start);
        fs.readSync(fd, buffer, 0, buffer.length, start);
        chunk = buffer.toString('utf8');
      } finally { fs.closeSync(fd); }
      try { fs.utimesSync(filePath, stat.atime, stat.mtime); } catch {}
    } catch { return { message: '', title: '' }; }
    const parsed = parseTail(chunk);
    this.cache = { path: filePath, size: stat.size, mtimeMs: stat.mtimeMs, ...parsed };
    return parsed;
  }
}

/// 말풍선 본문. 마크다운 기호를 빼고, 날것 링크는 도메인만 남긴다(PetView.bodyText).
function bodyText(liveMessage, lastAssistantMessage) {
  const raw = liveMessage || lastAssistantMessage || '';
  if (!raw) return '';
  let text = raw;
  for (const token of ['**', '```', '`', '##', '#', '|', '>', '- ', '* ']) text = text.split(token).join(' ');
  return text.split(/\s+/).filter(Boolean).map((word) => {
    if (!/^https?:\/\//.test(word)) return word;
    try { return new URL(word).host || word; } catch { return word; }
  }).join(' ').trim();
}

/// 이름표 옆 글자(PetView.detailText). 작업 중이면 도구 이름, 실패면 오류를 붙인다.
function detailText(session, state, kicker) {
  if (session.source === 'slack') return state === 'idle' ? 'Slack' : 'SLACK · 새 메시지';
  if ((state === 'review' || state === 'running') && session.toolName) return `${kicker} · ${String(session.toolName).toUpperCase()}`;
  if (state === 'failed' && session.error) return `${kicker} · ${String(session.error).slice(0, 24).toUpperCase()}`;
  return kicker;
}

module.exports = { TranscriptReader, assistantText, bodyText, detailText, parseTail };
