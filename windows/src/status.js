// 훅 기록 · Codex 롤아웃 · Orca 를 합쳐 화면에 쓸 세션 목록을 만든다.
//
// 맥 앱 AppDelegate.swift applySessions 의 앞부분(훅 → 롤아웃 → Orca 겹치기)을 옮긴 것이다.
// 화면에 무엇을 고를지는 core.chooseView 가 정한다.

const codex = require('./codex');
const orca = require('./orca');

const DISCOVERY_EVERY_MS = 3000;

class StatusAssembler {
  constructor({ codexHome, onChange } = {}) {
    this.discovery = new codex.RolloutDiscovery(codexHome);
    this.threadIndex = new orca.ThreadIndex();
    this.chatReader = new orca.ChatStatusReader({ onChange });
    this.rollouts = [];
    this.discoveredAt = 0;
  }

  /// 훅 세션(core.readRegistry 결과)을 받아 합친 목록을 돌려준다.
  sessions(hookSessions, nowMs = Date.now()) {
    let threads = {};
    try { threads = this.threadIndex.refresh(nowMs); } catch {}
    if (nowMs - this.discoveredAt >= DISCOVERY_EVERY_MS) {
      const extraTitles = Object.fromEntries(Object.entries(threads).filter(([, t]) => t.title).map(([id, t]) => [id, t.title]));
      try { this.rollouts = this.discovery.recentTasks({ nowMs, extraTitles }); } catch { this.rollouts = []; }
      this.discoveredAt = nowMs;
    }
    return assemble({
      hookSessions,
      rollouts: this.rollouts,
      threads,
      originator: (file) => this.discovery.originator(file),
      indexTitle: (id) => this.discovery.titleFor(id),
      transcript: (file) => this.discovery.statuses.status(file),
      chatStatus: (id) => this.chatReader.status(id)
    });
  }

  /// 턴 도중·대기 중이거나 막 끝난 Orca 의 Codex 채팅만 Orca 에 묻는다.
  track(sessions, transcriptModifiedAt, nowMs = Date.now()) {
    this.chatReader.track(sessions
      .filter((s) => !s.isClosed && s.orcaHosted === true
        && orca.needsWatching(s.state, Math.max(s.updatedAtMs || 0, transcriptModifiedAt(s) || 0), nowMs))
      .map((s) => s.rawSessionId)
      .filter(Boolean));
  }

  stop() { this.chatReader.stop(); }
}

/// 실제로 합치는 규칙. 파일·Orca 를 읽는 부분은 함수로 받아 테스트에서 바꿔 끼운다.
function assemble({ hookSessions, rollouts, threads, originator, indexTitle, transcript, chatStatus }) {
  const merged = new Map();
  for (const session of hookSessions) {
    if (!isVisibleTask(session)) continue;
    merged.set(session.id, session);
  }
  // 이미 훅으로 받은 task 는 더 정밀한 상태가 있으므로 그대로 둔다. 훅에 없는 task 만 롤아웃에서 넣는다.
  for (const task of rollouts) {
    if (merged.has(task.id) || !isVisibleTask(task)) continue;
    const thread = threads[task.rawSessionId];
    merged.set(task.id, thread && task.originator === 'orca_desktop' ? orca.linkTask(task, thread) : task);
  }
  return [...merged.values()].map((session) => {
    if (session.source !== 'codex' && session.client !== 'codex') return session;
    let out = session;
    // Orca 는 자기가 띄운 Codex 의 훅을 끈다. 훅이 Orca 식별자를 적지 못하므로 롤아웃 첫 줄로 알아본다.
    if (!orca.isOrcaSession(out) && out.transcriptPath && originator(out.transcriptPath) === 'orca_desktop') {
      out = orca.linkTask(out, threads[out.rawSessionId] || { orcaSessionId: '' });
    }
    const status = out.transcriptPath ? transcript(out.transcriptPath) : null;
    if (status) out = codex.reconcileTask(out, indexTitle(out.rawSessionId), status);
    // 롤아웃만으로 본 질문 대기는 맥 앱처럼 확인된 것으로 보지 않는다(NativeTaskStatus.swift unconfirmedInputTask).
    if (out.state === 'waiting' && out.stateSource === 'rollout') out = { ...out, state: 'idle', needsAttention: false, stateSource: 'unavailable' };
    // 훅 없는 Orca 채팅만 Orca 상태를 겹친다. 훅이 도는 Orca 터미널의 Codex 는 훅이 대기를 알려 준다.
    if (out.orcaHosted === true) {
      const turnStartedAtMs = status ? Math.max(status.latestPromptAtMs || 0, ...Object.values(status.composerTurns || {})) : 0;
      out = orca.applyChatStatus(chatStatus(out.rawSessionId), out, turnStartedAtMs);
    }
    return out;
  });
}

/// 내부 Codex 세션과 제목 없는 task 는 보이지 않는다(StatePayload.isRettoVisibleTask).
function isVisibleTask(session) {
  if (session.source !== 'codex' && session.client !== 'codex') return true;
  if (!String(session.sessionTitle || '').trim()) return false;
  return !codex.isSubagentTranscript(session.transcriptPath || '');
}

module.exports = { StatusAssembler, assemble, isVisibleTask };
