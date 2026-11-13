// Slack 알림 — 별도 서버 없이 Slack 공식 Socket Mode 로 DM · 내 멘션 · 고른 채널의 새 메시지를 받는다.
//
// 맥 앱 macos/Sources/SlackIntegration.swift 를 옮긴 것이다. 규칙(필터 · 묶음 · 읽음 위치 · 수정·삭제 반영 ·
// 링크)은 같고, 저장만 다르다 — 맥은 키체인, Windows 판은 Electron safeStorage(DPAPI)로 암호화한 파일.
// 메시지는 실행 중 메모리에만 두고 디스크에 쓰지 않는다. 설명은 docs/Slack-연결.md.

const TS = /^[0-9]{1,12}\.[0-9]{1,6}$/;
const AUTH_ERRORS = new Set(['invalid_auth', 'token_revoked', 'token_expired', 'account_inactive', 'not_authed', 'missing_scope', 'not_allowed_token_type', 'not_allowed']);

/// Slack ts 는 소수점 아래 6자리까지 메시지를 구분한다. 반올림으로 다음 메시지를 읽음 처리하지 않게 정수로 비교한다.
function slackTimestamp(value) {
  if (typeof value !== 'string' || !TS.test(value)) return null;
  const [seconds, fraction] = value.split('.');
  return BigInt(seconds) * 1000000n + BigInt(fraction.padEnd(6, '0'));
}

class SlackFailure extends Error {
  constructor(kind, code, seconds) { super(kind); this.kind = kind; this.code = code; this.seconds = seconds; }
  get description() {
    switch (this.kind) {
      case 'storage': return '토큰 저장소에 접근하지 못했습니다. Windows 에 로그인한 상태에서 다시 시도해 주세요.';
      case 'invalidTokens': return '같은 Slack 앱에서 발급한 사용자 토큰(xoxp-)과 앱 토큰(xapp-)을 입력해 주세요.';
      case 'rateLimit': return 'Slack 요청 한도에 도달했습니다. 잠시 후 자동으로 다시 연결합니다.';
      case 'api':
        if (['invalid_auth', 'token_revoked', 'token_expired', 'account_inactive', 'not_authed'].includes(this.code)) return 'Slack 인증이 만료되었거나 해제되었습니다. 새 토큰으로 연결해 주세요.';
        if (['missing_scope', 'not_allowed_token_type'].includes(this.code)) return 'Slack 권한이 부족합니다. 연결 안내의 사용자 권한과 앱 토큰을 확인해 주세요.';
        if (this.code === 'not_allowed') return 'Slack에서 연결을 허용하지 않았습니다. Socket Mode 설정과 관리자 승인을 확인해 주세요.';
        return 'Slack 요청을 처리하지 못했습니다. 연결 안내와 앱 설정을 확인해 주세요.';
      default: return 'Slack 응답을 확인하지 못했습니다. 연결 상태를 확인해 주세요.';
    }
  }
  /// 다시 시도할 간격(초). null 이면 사람이 고칠 때까지 다시 시도하지 않는다.
  get retryDelay() {
    if (this.kind === 'api' && AUTH_ERRORS.has(this.code)) return null;
    if (this.kind === 'invalidTokens' || this.kind === 'storage') return null;
    if (this.kind === 'rateLimit') return Math.max(1, this.seconds);
    return 5;
  }
}

// ── 읽음 대상과 조회 순서 ────────────────────────────────────────────────────
function readTargetKey(target) { return `${target.team}|${target.channel}|${target.thread || ''}`; }
function readTargetMethod(target) { return target.thread ? 'conversations.replies' : 'conversations.info'; }
function readTargetParameters(target) {
  return target.thread ? { channel: target.channel, ts: target.thread, limit: '1' } : { channel: target.channel };
}
function readMarker(target, response) {
  if (target.thread) {
    const message = (Array.isArray(response?.messages) ? response.messages : []).find((m) => m.ts === target.thread);
    return message?.last_read;
  }
  const conversation = response?.channel;
  return conversation && conversation.id === target.channel ? conversation.last_read : undefined;
}

/// 같은 대상은 15초 뒤에 다시 본다. 전체 HTTP 조회는 메서드마다 2초 간격, 429 는 Retry-After 를 따른다.
class ReadSchedule {
  constructor() { this.nextChecks = new Map(); this.lastPrioritizedAt = new Map(); this.methodRetryAt = new Map(); }
  next(targets, now) {
    const keys = new Map(targets.map((t) => [readTargetKey(t), t]));
    for (const key of [...this.nextChecks.keys()]) if (!keys.has(key)) this.nextChecks.delete(key);
    for (const key of [...this.lastPrioritizedAt.keys()]) if (!keys.has(key)) this.lastPrioritizedAt.delete(key);
    const eligible = [...keys.entries()].filter(([key, t]) => (this.nextChecks.get(key) ?? 0) <= now && (this.methodRetryAt.get(readTargetMethod(t)) ?? 0) <= now);
    eligible.sort(([a, ta], [b, tb]) => {
      const left = this.nextChecks.get(a) ?? 0, right = this.nextChecks.get(b) ?? 0;
      if (left !== right) return left - right;
      return `${ta.channel}:${ta.thread || ''}` < `${tb.channel}:${tb.thread || ''}` ? -1 : 1;
    });
    if (!eligible.length) return null;
    const [key, target] = eligible[0];
    this.nextChecks.set(key, now + 15);
    this.methodRetryAt.set(readTargetMethod(target), now + 2);
    return target;
  }
  prioritize(targets, now) {
    for (const target of targets) {
      const key = readTargetKey(target);
      if (now - (this.lastPrioritizedAt.get(key) ?? -Infinity) >= 5) { this.lastPrioritizedAt.set(key, now); this.nextChecks.set(key, -1); }
    }
  }
  retry(target, delay, now, rateLimited) {
    const key = readTargetKey(target);
    this.nextChecks.set(key, Math.max(this.nextChecks.get(key) ?? 0, now + delay));
    const method = readTargetMethod(target);
    if (rateLimited) this.methodRetryAt.set(method, Math.max(this.methodRetryAt.get(method) ?? 0, now + delay));
  }
}

// ── 메시지 하나 ────────────────────────────────────────────────────────────
function noticeId(n) { return `slack:${n.team}:${n.channel}:${n.timestamp}`; }
function noticeReadTarget(n) { return { team: n.team, channel: n.channel, thread: n.threadTimestamp === n.timestamp ? null : (n.threadTimestamp || null) }; }
function noticeGroupId(n) { return `slack-group:${n.team}:${n.channel}:${n.user}:${noticeReadTarget(n).thread || 'channel'}`; }

function authorizedEvent(payload, userID, teamID) {
  if (payload?.type !== 'event_callback' || payload.team_id !== teamID) return null;
  const authorizations = Array.isArray(payload.authorizations) ? payload.authorizations : [];
  if (!authorizations.some((a) => a.user_id === userID && a.is_bot === false)) return null;
  const event = payload.event;
  return event && event.type === 'message' ? event : null;
}

function parseNotice(payload, userID, teamID) {
  const event = authorizedEvent(payload, userID, teamID);
  if (!event || event.hidden === true) return null;
  if (event.subtype != null && !['file_share', 'bot_message', 'thread_broadcast', 'me_message'].includes(event.subtype)) return null;
  if (typeof event.channel !== 'string' || typeof event.ts !== 'string' || !TS.test(event.ts) || typeof event.text !== 'string') return null;
  const user = event.user || event.bot_id || '';
  if (!user || user === userID) return null;
  return {
    team: teamID, channel: event.channel, timestamp: event.ts, user, text: event.text,
    isDM: ['im', 'mpim'].includes(event.channel_type), isMention: event.text.includes(`<@${userID}>`),
    senderName: event.username || null, isGroupDM: event.channel_type === 'mpim',
    threadTimestamp: event.thread_ts || null, revisionTimestamp: event.edited?.ts || null
  };
}

function matches(notice, preferences) {
  return (notice.isDM && preferences.directMessages) || (notice.isMention && preferences.mentions) || preferences.channelIDs.includes(notice.channel);
}

/// slack://channel 링크. Slack 데스크톱 앱에 바로 넘긴다(브라우저를 거치지 않는다).
function nativeMessageURL(notice) {
  if (!/^[TE][A-Z0-9]+$/.test(notice.team) || !/^[CDG][A-Z0-9]+$/.test(notice.channel) || !TS.test(notice.timestamp)) return null;
  const query = new URLSearchParams({ team: notice.team, id: notice.channel, message: notice.timestamp });
  if (notice.threadTimestamp && TS.test(notice.threadTimestamp)) query.set('thread_ts', notice.threadTimestamp);
  return `slack://channel?${query.toString()}`;
}

/// 화면이 쓰는 세션 모양으로 바꾼다(SlackNotice.payload).
function noticePayload(notice, { preferences, channels, userNames = {}, sessionID = null, messageCount = 1 }) {
  const channelName = channels.find((c) => c.id === notice.channel)?.name;
  const sender = userNames[notice.user] || notice.senderName || notice.user;
  let title = notice.isGroupDM ? '그룹 DM' : (notice.isDM ? `DM · ${sender}` : `#${channelName || notice.channel}`);
  if (sessionID && (!notice.isDM || notice.isGroupDM)) title += ` · ${sender}`;
  if (messageCount > 1) title += ` +${messageCount}`;
  let content = notice.text;
  for (const [id, name] of Object.entries(userNames)) content = content.replaceAll(`<@${id}>`, `@${name}`);
  content = content.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
  const hidden = messageCount > 1 ? `Slack에 새 메시지 ${messageCount}개가 도착했어요` : 'Slack에 새 메시지가 도착했어요';
  const body = preferences.preview ? `@${sender} ${[...content].slice(0, 3000).join('')}` : hidden;
  const id = sessionID || noticeId(notice);
  return {
    id, sessionId: id, state: 'waving', source: 'slack', projectName: 'Slack', sessionTitle: title,
    lastAssistantMessage: body, updatedAtMs: Number(notice.timestamp) * 1000, needsAttention: true, attention: true, isClosed: false
  };
}

/// 표시만 묶는다. 같은 워크스페이스 · 대화 · 스레드 · 보낸 사람(SlackNoticeGroup).
function groupNotices(notices) {
  const groups = new Map();
  for (const notice of notices) {
    const key = noticeGroupId(notice);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(notice);
  }
  const compare = (a, b) => { const x = slackTimestamp(a) ?? 0n, y = slackTimestamp(b) ?? 0n; return x < y ? -1 : x > y ? 1 : 0; };
  return [...groups.values()].map((messages) => {
    messages.sort((a, b) => compare(a.timestamp, b.timestamp));
    const latest = messages[messages.length - 1];
    return { id: noticeGroupId(latest), messages, first: messages[0], latest };
  }).sort((a, b) => { const c = compare(b.latest.timestamp, a.latest.timestamp); return c !== 0 ? c : (a.id < b.id ? -1 : 1); });
}

/// 받은 메시지 목록. 재전송 중복 · 읽음 위치 · 수정·삭제를 다룬다(SlackInbox).
class Inbox {
  constructor() { this.notices = []; this.seen = new Set(); this.seenOrder = []; this.readMarkers = new Map(); }
  remember(id) {
    if (this.seen.has(id)) return false;
    this.seen.add(id); this.seenOrder.push(id);
    if (this.seenOrder.length > 2000) this.seen.delete(this.seenOrder.shift());
    return true;
  }
  accept(notice, preferences) {
    if (!this.remember(noticeId(notice)) || !matches(notice, preferences)) return false;
    const marker = this.readMarkers.get(readTargetKey(noticeReadTarget(notice)));
    const ts = slackTimestamp(notice.timestamp);
    if (marker != null && ts != null && ts <= marker) return false;
    this.notices.push(notice);
    this.notices.sort((a, b) => Number(a.timestamp) - Number(b.timestamp));
    if (this.notices.length > 100) this.notices.splice(0, this.notices.length - 100);
    return true;
  }
  filter(preferences) { this.notices = this.notices.filter((n) => matches(n, preferences)); }
  dismiss(ids) { const before = this.notices.length; this.notices = this.notices.filter((n) => !ids.has(noticeId(n))); return before !== this.notices.length; }
  dismissNotifications(ids) {
    const all = new Set(ids);
    for (const group of groupNotices(this.notices)) if (ids.has(group.id)) for (const m of group.messages) all.add(noticeId(m));
    return this.dismiss(all);
  }
  applyMessageChange(payload, userID, teamID, preferences) {
    const event = authorizedEvent(payload, userID, teamID);
    if (!event || typeof event.channel !== 'string') return false;
    if (event.subtype === 'message_deleted' && slackTimestamp(event.deleted_ts) != null) {
      const id = `slack:${teamID}:${event.channel}:${event.deleted_ts}`;
      // 삭제가 먼저 도착해도 뒤늦게 받은 원문을 다시 표시하지 않는다.
      this.remember(id);
      return this.dismiss(new Set([id]));
    }
    const message = event.message;
    if (event.subtype !== 'message_changed' || !message || slackTimestamp(message.ts) == null || typeof message.text !== 'string') return false;
    const index = this.notices.findIndex((n) => n.team === teamID && n.channel === event.channel && n.timestamp === message.ts);
    if (index < 0) return false;
    const previous = this.notices[index];
    const revision = event.event_ts || message.edited?.ts || event.ts;
    const version = slackTimestamp(revision);
    if (version == null || version <= (slackTimestamp(previous.revisionTimestamp || previous.timestamp) ?? 0n)) return false;
    if (message.user && message.user !== previous.user) return false;
    const updated = { ...previous, text: message.text, isMention: message.text.includes(`<@${userID}>`), revisionTimestamp: revision };
    if (matches(updated, preferences)) this.notices[index] = updated; else this.notices.splice(index, 1);
    return true;
  }
  applyReadMarker(value, target) {
    const marker = slackTimestamp(value);
    if (marker == null) return false;
    const key = readTargetKey(target);
    const previous = this.readMarkers.get(key);
    if (previous != null && marker <= previous) return false;
    if (this.readMarkers.size >= 2000 && !this.readMarkers.has(key)) this.readMarkers.clear();
    this.readMarkers.set(key, marker);
    const before = this.notices.length;
    this.notices = this.notices.filter((n) => {
      if (readTargetKey(noticeReadTarget(n)) !== key) return true;
      const ts = slackTimestamp(n.timestamp);
      return !(ts != null && ts <= marker);
    });
    return before !== this.notices.length;
  }
}

const DEFAULT_PREFERENCES = { directMessages: true, mentions: true, preview: true, channelIDs: [] };

/// 연결과 수신. 상태 변경은 한 곳(이 객체)에서만 하고, 재연결 전의 비동기 결과는 generation 으로 버린다.
class SlackIntegration {
  /// store: { read(): {userToken, appToken}|null, write(credentials), delete() } — 맥 SlackKeychain 자리.
  constructor({ store, preferences, onChange, fetchImpl = globalThis.fetch, WebSocketImpl = globalThis.WebSocket, now = () => performance.now() / 1000,
    requestTimeoutMs = 25000, heartbeatMs = 20000, readIntervalMs = 2000 } = {}) {
    this.requestTimeoutMs = requestTimeoutMs;
    this.heartbeatMs = heartbeatMs;
    this.readIntervalMs = readIntervalMs;
    this.store = store;
    this.fetch = fetchImpl;
    this.WebSocket = WebSocketImpl;
    this.now = now;
    this.onChange = onChange || (() => {});
    this.preferences = { ...DEFAULT_PREFERENCES, ...(preferences || {}) };
    this.status = '연결되지 않음';
    this.connectionState = 'disabled';
    this.channels = [];
    this.inbox = new Inbox();
    this.userID = ''; this.teamID = ''; this.workspaceName = '';
    this.userNames = {};
    this.metadataPending = new Set(); this.metadataRetryAt = new Map();
    this.credentials = null;
    this.generation = 0;
    this.socket = null;
    this.readTimer = null;
    this.readSchedule = new ReadSchedule();
    this.readSyncIssues = new Map();
  }

  get notices() { return this.inbox.notices; }
  get groups() { return groupNotices(this.inbox.notices); }
  get hasCredentials() { return this.credentials != null; }
  get readSyncIssue() { return [...this.readSyncIssues.values()].sort()[0] || null; }
  get connectionIssue() {
    if (this.connectionState === 'failed') return 'Slack 연결 확인 필요';
    if (this.connectionState === 'reconnecting') return 'Slack 다시 연결 중';
    return this.readSyncIssue;
  }
  payloads() {
    return this.groups.map((group) => noticePayload(group.latest, {
      preferences: this.preferences, channels: this.channels, userNames: this.userNames, sessionID: group.id, messageCount: group.messages.length
    }));
  }
  setPreferences(next) {
    this.preferences = { ...this.preferences, ...next };
    this.inbox.filter(this.preferences);
    this.onChange();
  }
  dismissNotices(ids) {
    if (!this.inbox.dismissNotifications(ids)) return false;
    const live = new Set(this.notices.map((n) => readTargetKey(noticeReadTarget(n))));
    for (const key of [...this.readSyncIssues.keys()]) if (!live.has(key)) this.readSyncIssues.delete(key);
    this.onChange();
    return true;
  }
  groupFor(id) { return this.groups.find((group) => group.id === id); }

  restore() {
    let saved = null;
    try { saved = this.store.read(); } catch {
      this.connectionState = 'failed'; this.status = new SlackFailure('storage').description; this.onChange(); return;
    }
    this.credentials = saved;
    if (saved) this.start(); else { this.connectionState = 'disabled'; this.status = '연결되지 않음'; this.onChange(); }
  }

  connect(userToken, appToken) {
    const user = String(userToken || '').trim();
    const appTok = String(appToken || '').trim();
    const value = { userToken: user || this.credentials?.userToken || '', appToken: appTok || this.credentials?.appToken || '' };
    if (!value.userToken.startsWith('xoxp-') || !value.appToken.startsWith('xapp-') || /\s/.test(value.userToken + value.appToken)) {
      throw new SlackFailure('invalidTokens');
    }
    try { this.store.write(value); } catch { throw new SlackFailure('storage'); }
    this.stop();
    this.credentials = value;
    this.inbox = new Inbox(); this.channels = []; this.userNames = {};
    this.start();
  }

  disconnect() {
    try { this.store.delete(); } catch { throw new SlackFailure('storage'); }
    this.stop();
    this.credentials = null;
    this.inbox = new Inbox(); this.channels = []; this.userNames = {}; this.userID = ''; this.teamID = '';
    this.connectionState = 'disabled';
    this.status = '연결 해제됨 · 이 PC 에 저장한 토큰을 삭제했습니다';
    this.onChange();
  }

  stop() {
    this.generation += 1;
    this.metadataPending.clear(); this.metadataRetryAt.clear();
    clearTimeout(this.readTimer); this.readTimer = null;
    this.readSchedule = new ReadSchedule(); this.readSyncIssues.clear();
    try { this.socket?.close(); } catch {}
    this.socket = null;
  }

  start() {
    this.stop();
    if (!this.credentials) return;
    const current = this.generation;
    this.connectionState = 'connecting';
    this.status = 'Slack 연결 중…';
    this.onChange();
    this.run(current, 1);
  }

  async run(current, delay) {
    const credentials = this.credentials;
    try {
      const auth = await this.call('auth.test', credentials.userToken);
      if (this.generation !== current) return;
      if (!auth.user_id || !auth.team_id) throw new SlackFailure('response');
      this.userID = auth.user_id; this.teamID = auth.team_id; this.workspaceName = auth.team || '';
      // 소켓을 다시 잇는 동안에도 읽음 조회(HTTP)는 계속한다. 맥처럼 한 번 끝난 뒤 2초를 쉬고 다음을 본다 —
      // 느린 요청이 끝나기 전에 다음 조회가 겹쳐 돌지 않게.
      if (!this.readTimer) {
        const tick = async () => {
          if (this.generation !== current) return;
          await this.refreshReadState(current).catch(() => {});
          if (this.generation === current) this.readTimer = setTimeout(tick, this.readIntervalMs);
        };
        this.readTimer = setTimeout(tick, this.readIntervalMs);
      }
      const connection = await this.call('apps.connections.open', credentials.appToken);
      if (this.generation !== current) return;
      let url;
      try { url = new URL(connection.url); } catch { throw new SlackFailure('response'); }
      if (url.protocol !== 'wss:' || !(url.hostname === 'wss.slack.com' || url.hostname.endsWith('.slack.com'))) throw new SlackFailure('response');
      await new Promise((resolve, reject) => {
        const ws = new this.WebSocket(url.href);
        this.socket = ws;
        // 맥처럼 20초마다 ping 을 보내 반쯤 끊긴 연결(닫힘 신호 없이 멈춘 소켓)을 알아챈다. 답이 없으면 끊고 다시 잇는다.
        // ping 을 보낼 수 있는 소켓(ws 패키지)일 때만 — 표준 WebSocket 에는 ping 이 없다.
        let heartbeat = null;
        if (typeof ws.ping === 'function') {
          let alive = true;
          ws.on('pong', () => { alive = true; });
          heartbeat = setInterval(() => {
            if (this.generation !== current) { clearInterval(heartbeat); return; }
            if (!alive) { clearInterval(heartbeat); try { ws.terminate(); } catch {} return; }
            alive = false;
            try { ws.ping(); } catch { clearInterval(heartbeat); try { ws.terminate(); } catch {} }
          }, this.heartbeatMs);
        }
        const finish = (error) => { clearInterval(heartbeat); reject(error); };
        ws.addEventListener('message', (event) => {
          if (this.generation !== current) return;
          let object;
          try { object = JSON.parse(typeof event.data === 'string' ? event.data : Buffer.from(event.data).toString('utf8')); } catch { return; }
          if (object.envelope_id) { try { ws.send(JSON.stringify({ envelope_id: object.envelope_id })); } catch {} }
          if (object.type === 'hello') {
            delay = 1;
            this.connectionState = 'connected';
            this.status = `연결됨 · ${auth.team || 'Slack'} · 새 메시지 수신 대기`;
            this.onChange();
            this.refreshChannels(current);
          } else if (object.type === 'disconnect') {
            try { ws.close(); } catch {}
          } else if (object.type === 'events_api' && object.payload) {
            this.accept(object.payload);
          }
        });
        ws.addEventListener('close', () => finish(new SlackFailure('response')));
        ws.addEventListener('error', () => finish(new SlackFailure('response')));
      });
    } catch (error) {
      if (this.generation !== current) return;
      try { this.socket?.close(); } catch {}
      this.socket = null;
      const failure = error instanceof SlackFailure ? error : null;
      this.connectionState = failure && failure.retryDelay == null ? 'failed' : 'reconnecting';
      this.status = failure && failure.kind !== 'response' ? failure.description : 'Slack 연결이 끊겼습니다. 자동으로 다시 연결합니다.';
      this.onChange();
      if (failure && failure.retryDelay == null) return;
      const wait = Math.max(delay, failure?.retryDelay ?? 5);
      setTimeout(() => { if (this.generation === current) this.run(current, Math.min(delay * 2, 60)); }, Math.min(wait, 3600) * 1000);
    }
  }

  accept(payload) {
    if (this.inbox.applyMessageChange(payload, this.userID, this.teamID, this.preferences)) { this.onChange(); return; }
    const notice = parseNotice(payload, this.userID, this.teamID);
    if (!notice || !this.inbox.accept(notice, this.preferences)) return;
    this.onChange();
    this.resolveMetadata(notice, this.generation);
  }

  prioritizeReadSync(ids) {
    const targets = this.notices.filter((n) => ids.has(noticeId(n)) && n.team === this.teamID).map(noticeReadTarget);
    this.readSchedule.prioritize(targets, this.now());
  }

  async refreshReadState(current) {
    if (!this.credentials || !this.userID || this.generation !== current) return;
    const previousIssue = this.readSyncIssue;
    const targets = [...new Map(this.notices.filter((n) => n.team === this.teamID).map((n) => {
      const t = noticeReadTarget(n); return [readTargetKey(t), t];
    })).values()];
    const live = new Set(targets.map(readTargetKey));
    for (const key of [...this.readSyncIssues.keys()]) if (!live.has(key)) this.readSyncIssues.delete(key);
    const target = this.readSchedule.next(targets, this.now());
    if (!target) { if (previousIssue !== this.readSyncIssue) this.onChange(); return; }
    let changed = false;
    try {
      const result = await this.call(readTargetMethod(target), this.credentials.userToken, readTargetParameters(target));
      if (this.generation !== current) return;
      const marker = readMarker(target, result);
      if (marker && slackTimestamp(marker) != null) {
        changed = this.inbox.applyReadMarker(marker, target);
        this.readSyncIssues.delete(readTargetKey(target));
      } else {
        this.readSyncIssues.set(readTargetKey(target), 'Slack에서 읽음 위치를 제공하지 않아 일부 알림을 유지합니다.');
      }
    } catch (error) {
      if (this.generation !== current) return;
      const failure = error instanceof SlackFailure ? error : null;
      this.readSchedule.retry(target, Math.max(15, failure?.retryDelay ?? 300), this.now(), failure?.kind === 'rateLimit');
      this.readSyncIssues.set(readTargetKey(target), failure?.kind === 'api' && failure.code === 'missing_scope'
        ? 'Slack 읽음 동기화 권한이 부족합니다. 연결 안내의 im:read·mpim:read 등을 추가하고 Slack 앱을 다시 설치해 주세요.'
        : 'Slack 읽음 상태를 확인하지 못했습니다. 알림을 유지하며 다시 확인합니다.');
    }
    if (changed || previousIssue !== this.readSyncIssue) this.onChange();
  }

  async resolveMetadata(notice, current) {
    if (!this.credentials) return;
    const ids = new Set([notice.user]);
    for (const match of [...notice.text.matchAll(/<@([A-Z0-9]+)>/g)].slice(0, 10)) ids.add(match[1]);
    const requests = [];
    for (const id of ids) if (!this.userNames[id] && !id.startsWith('B')) requests.push([`user:${id}`, 'users.info', { user: id }]);
    if (!notice.isDM && !this.channels.some((c) => c.id === notice.channel)) requests.push([`channel:${notice.channel}`, 'conversations.info', { channel: notice.channel }]);
    for (const [key, method, parameters] of requests) {
      if (this.generation !== current) return;
      if (this.metadataPending.has(key) || (this.metadataRetryAt.get(key) ?? 0) > Date.now()) continue;
      this.metadataPending.add(key);
      try {
        const result = await this.call(method, this.credentials.userToken, parameters);
        if (this.generation !== current) return;
        if (method === 'users.info' && result.user?.id) {
          const profile = result.user.profile || {};
          const name = [profile.display_name, profile.real_name, result.user.name].find((v) => typeof v === 'string' && v.trim());
          if (name) { if (Object.keys(this.userNames).length >= 1000) this.userNames = {}; this.userNames[result.user.id] = name; }
        } else if (result.channel?.id && result.channel?.name && !this.channels.some((c) => c.id === result.channel.id)) {
          this.channels.push({ id: result.channel.id, name: result.channel.name });
        }
        this.metadataPending.delete(key);
        this.onChange();
      } catch (error) {
        if (this.generation !== current) return;
        this.metadataPending.delete(key);
        const wait = error instanceof SlackFailure ? (error.retryDelay ?? 300) : 300;
        this.metadataRetryAt.set(key, Date.now() + Math.max(60, wait) * 1000);
      }
    }
  }

  async refreshChannels(current = this.generation) {
    if (!this.credentials || !this.userID) return;
    try {
      let cursor = '';
      const result = [];
      do {
        const page = await this.call('users.conversations', this.credentials.userToken,
          { types: 'public_channel,private_channel', exclude_archived: 'true', limit: '200', cursor });
        if (this.generation !== current) return;
        for (const item of page.channels || []) if (item.id && item.name) result.push({ id: item.id, name: item.name });
        cursor = page.response_metadata?.next_cursor || '';
      } while (cursor);
      this.channels = result.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
      this.onChange();
    } catch {
      if (this.generation !== current) return;
      this.status = '채널 목록을 불러오지 못했습니다. DM·멘션 수신은 유지됩니다. 권한을 확인하고 목록을 새로고침해 주세요.';
      this.onChange();
    }
  }

  messageURL(group) {
    if (!group || group.first.team !== this.teamID) return null;
    return nativeMessageURL(group.first);
  }

  async call(method, token, parameters = {}) {
    const body = Object.keys(parameters).sort().map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(parameters[k])}`).join('&');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.requestTimeoutMs);
    let response;
    try {
      response = await this.fetch(`https://slack.com/api/${method}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
        signal: controller.signal
      });
    } catch { clearTimeout(timeout); throw new SlackFailure('response'); }
    if (response.status === 429) { clearTimeout(timeout); throw new SlackFailure('rateLimit', null, Number(response.headers.get('Retry-After') || 30) || 30); }
    // 25초 제한은 본문을 다 받을 때까지 걸어 둔다(맥 URLRequest.timeoutInterval 과 같다).
    let object;
    try { object = await response.json(); } catch { throw new SlackFailure('response'); } finally { clearTimeout(timeout); }
    if (response.status !== 200 || !object || typeof object !== 'object') throw new SlackFailure('response');
    if (object.ok !== true) throw new SlackFailure('api', object.error || 'unknown');
    return object;
  }
}

/// safeStorage 로 암호화해 파일에 둔다. Windows 는 DPAPI(그 Windows 사용자만 풀 수 있다).
function fileStore({ fs, filePath, safeStorage }) {
  return {
    read() {
      let data;
      try { data = fs.readFileSync(filePath); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
      if (!safeStorage.isEncryptionAvailable()) throw new Error('encryption unavailable');
      const value = JSON.parse(safeStorage.decryptString(data));
      return value && value.userToken && value.appToken ? value : null;
    },
    write(value) {
      if (!safeStorage.isEncryptionAvailable()) throw new Error('encryption unavailable');
      fs.mkdirSync(require('node:path').dirname(filePath), { recursive: true });
      fs.writeFileSync(filePath, safeStorage.encryptString(JSON.stringify(value)), { mode: 0o600 });
    },
    delete() { fs.rmSync(filePath, { force: true }); }
  };
}

module.exports = {
  DEFAULT_PREFERENCES,
  Inbox,
  ReadSchedule,
  SlackFailure,
  SlackIntegration,
  fileStore,
  groupNotices,
  matches,
  nativeMessageURL,
  noticeId,
  noticePayload,
  noticeReadTarget,
  parseNotice,
  readMarker,
  slackTimestamp
};
