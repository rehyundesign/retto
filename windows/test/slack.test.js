// Slack 규칙이 맥 앱(SlackIntegration.swift)과 같은지 본다. 맥 SlackSelfTest.swift 와 같은 사례를 쓴다.
// 실제 토큰 · 네트워크 없이 돈다. 연결 흐름은 가짜 fetch · WebSocket 으로 본다.

const test = require('node:test');
const assert = require('node:assert/strict');
const slack = require('../src/slack');

const event = ({ text = 'hello', user = 'U_OTHER', type = 'im', subtype, ts = '1800000000.123456', thread, channel = 'D123' } = {}) => ({
  type: 'event_callback', team_id: 'T123',
  event: { type: 'message', channel, channel_type: type, user, ts, text, ...(subtype ? { subtype } : {}), ...(thread ? { thread_ts: thread } : {}) },
  authorizations: [{ user_id: 'U_ME', is_bot: false, team_id: 'T123' }]
});
const parse = (value) => slack.parseNotice(value, 'U_ME', 'T123');
const prefs = (extra = {}) => ({ ...slack.DEFAULT_PREFERENCES, channelIDs: [], ...extra });

test('알릴 것 — DM · 내 멘션 · 고른 채널, 자기 메시지 · 시스템 이벤트 · 다른 워크스페이스는 뺀다', () => {
  const dm = parse(event());
  assert.ok(slack.matches(dm, prefs()));
  assert.ok(!slack.matches(dm, prefs({ directMessages: false })));
  const mention = parse(event({ text: 'hello <@U_ME>', type: 'channel' }));
  assert.ok(slack.matches(mention, prefs({ directMessages: false })));
  assert.ok(!slack.matches(parse(event({ text: 'hello <@U_ME_OTHER>', type: 'channel' })), prefs({ directMessages: false })), '정확한 사용자 ID');
  assert.ok(!slack.matches(mention, prefs({ directMessages: false, mentions: false })));
  assert.ok(slack.matches(mention, prefs({ directMessages: false, mentions: false, channelIDs: ['D123'] })), '고른 채널');
  assert.equal(parse(event({ user: 'U_ME' })), null, '자기 메시지');
  assert.equal(parse(event({ subtype: 'message_changed' })), null);
  assert.equal(parse(event({ subtype: 'message_deleted' })), null);
  assert.equal(parse(event({ subtype: 'channel_join' })), null);
  assert.ok(parse(event({ subtype: 'file_share' })));
  assert.ok(parse(event({ subtype: 'thread_broadcast' })));
  assert.ok(parse(event({ subtype: 'me_message' })));
  assert.equal(parse(event({ type: 'mpim' })).isGroupDM, true);
  assert.equal(slack.parseNotice(event(), 'U_ME', 'T999'), null, '다른 워크스페이스');
  const otherAuth = event(); otherAuth.authorizations = [{ user_id: 'U_ELSE', is_bot: false }];
  assert.equal(parse(otherAuth), null);
  const noAuth = event(); delete noAuth.authorizations;
  assert.equal(parse(noAuth), null);
  assert.equal(parse(event({ ts: 'nan' })), null);
});

test('화면 모양 · 미리보기 · Slack 앱 링크', () => {
  const dm = parse(event());
  const payload = slack.noticePayload(dm, { preferences: prefs(), channels: [] });
  assert.equal(payload.source, 'slack');
  assert.equal(payload.state, 'waving');
  assert.equal(payload.needsAttention, true);
  assert.equal(payload.lastAssistantMessage, '@U_OTHER hello');
  assert.equal(slack.noticePayload(dm, { preferences: prefs({ preview: false }), channels: [] }).lastAssistantMessage, 'Slack에 새 메시지가 도착했어요');
  const url = new URL(slack.nativeMessageURL(dm));
  assert.equal(url.protocol, 'slack:');
  assert.equal(url.host, 'channel');
  assert.equal(url.searchParams.get('team'), 'T123');
  assert.equal(url.searchParams.get('id'), 'D123');
  assert.equal(url.searchParams.get('message'), '1800000000.123456');
  const reply = parse(event({ thread: '1799999999.000001' }));
  assert.equal(new URL(slack.nativeMessageURL(reply)).searchParams.get('thread_ts'), '1799999999.000001');
  assert.equal(slack.nativeMessageURL({ ...dm, team: 'T123&id=OTHER' }), null);
  assert.ok(slack.nativeMessageURL({ ...dm, channel: 'C123' }).startsWith('slack://'));
});

test('실패 — 인증 오류는 다시 시도하지 않고, 한도는 Retry-After, 토큰을 메시지에 싣지 않는다', () => {
  assert.equal(new slack.SlackFailure('api', 'token_revoked').retryDelay, null);
  assert.equal(new slack.SlackFailure('rateLimit', null, 120).retryDelay, 120);
  assert.ok(!new slack.SlackFailure('api', 'xoxp-secret').description.includes('secret'));
});

test('받은 목록 — 중복 · 100개 · 범위를 끄면 빠지고 다시 켜도 안 돌아온다', () => {
  const dm = parse(event());
  const inbox = new slack.Inbox();
  assert.ok(inbox.accept(dm, prefs()));
  assert.ok(!inbox.accept(dm, prefs()));
  for (let i = 1; i <= 110; i += 1) inbox.accept({ ...dm, timestamp: `1800000001.${i}` }, prefs());
  assert.equal(inbox.notices.length, 100);
  assert.ok(!inbox.notices.some((n) => slack.noticeId(n) === slack.noticeId(dm)));
  const off = prefs({ directMessages: false, mentions: false });
  inbox.filter(off);
  assert.equal(inbox.notices.length, 0);
  const suppressed = new slack.Inbox();
  assert.ok(!suppressed.accept(dm, off));
  assert.ok(!suppressed.accept(dm, prefs()), '재전송이 꺼져 있던 이벤트를 되살리지 않는다');
});

test('읽음 위치 — 읽은 데까지만 지운다. 다음 마이크로초 · 다른 대화 · 스레드는 남긴다', () => {
  const dm = parse(event());
  const next = { ...dm, timestamp: '1800000000.123457' };
  const other = { ...dm, channel: 'D999' };
  const reply = { ...dm, timestamp: '1800000000.123458', threadTimestamp: '1799999999.000001' };
  const inbox = new slack.Inbox();
  for (const n of [dm, next, other, reply]) inbox.accept(n, prefs());
  assert.ok(!inbox.applyReadMarker('bad', slack.noticeReadTarget(dm)));
  assert.ok(inbox.applyReadMarker('1800000000.123456', slack.noticeReadTarget(dm)));
  assert.deepEqual(inbox.notices.map((n) => n.timestamp + n.channel).sort(), ['1800000000.123456D999', '1800000000.123457D123', '1800000000.123458D123'].sort());
  assert.ok(!inbox.applyReadMarker('1800000000.000001', slack.noticeReadTarget(dm)), '읽음 위치는 뒤로 가지 않는다');
  assert.ok(inbox.applyReadMarker('1800000000.123458', slack.noticeReadTarget(reply)), '스레드 읽음은 그 답글만');
  assert.ok(!inbox.accept({ ...dm, timestamp: '1800000000.100000' }, prefs()), '읽은 뒤 늦게 온 이전 메시지');
  assert.ok(slack.slackTimestamp('1800000000.123457') > slack.slackTimestamp('1800000000.123456'));
});

test('묶음 — 같은 사람 · 같은 대화는 하나로, +N, 연 묶음만 지운다', () => {
  const dm = parse(event());
  const second = { ...dm, timestamp: '1800000000.223456', text: 'second' };
  const third = { ...dm, timestamp: '1800000000.323456', text: 'third' };
  const inbox = new slack.Inbox();
  for (const n of [dm, second, third]) inbox.accept(n, prefs());
  const groups = slack.groupNotices(inbox.notices);
  assert.equal(groups.length, 1);
  const payload = slack.noticePayload(groups[0].latest, { preferences: prefs(), channels: [], sessionID: groups[0].id, messageCount: 3 });
  assert.ok(payload.sessionTitle.endsWith('+3'));
  assert.equal(payload.lastAssistantMessage, '@U_OTHER third');
  assert.equal(slack.nativeMessageURL(groups[0].first), slack.nativeMessageURL(dm), '누르면 첫 미확인 메시지');
  inbox.accept({ ...dm, timestamp: '1800000000.423456' }, prefs());
  inbox.dismiss(new Set(groups[0].messages.map(slack.noticeId)));
  assert.equal(inbox.notices.length, 1, '여는 동안 새로 온 메시지는 남긴다');
});

test('수정 · 삭제 반영', () => {
  const inbox = new slack.Inbox();
  const dm = parse(event({ text: 'hello <@U_ME>' }));
  inbox.accept(dm, prefs());
  const change = (text, rev) => ({ ...event(), event: { type: 'message', subtype: 'message_changed', channel: 'D123', event_ts: rev,
    message: { ts: dm.timestamp, text, user: 'U_OTHER' } } });
  assert.ok(inbox.applyMessageChange(change('edited', '1800000005.000000'), 'U_ME', 'T123', prefs()));
  assert.equal(inbox.notices[0].text, 'edited');
  assert.ok(!inbox.applyMessageChange(change('older', '1800000004.000000'), 'U_ME', 'T123', prefs()), '오래된 수정은 덮어쓰지 않는다');
  const del = { ...event(), event: { type: 'message', subtype: 'message_deleted', channel: 'D123', deleted_ts: dm.timestamp } };
  assert.ok(inbox.applyMessageChange(del, 'U_ME', 'T123', prefs()));
  assert.equal(inbox.notices.length, 0);
  assert.ok(!inbox.accept(dm, prefs()), '삭제 뒤 늦게 온 원문을 다시 표시하지 않는다');
});

test('조회 순서 — 같은 대상 15초, 메서드 2초, 429 는 Retry-After', () => {
  const schedule = new slack.ReadSchedule();
  const a = { team: 'T', channel: 'D1', thread: null };
  const b = { team: 'T', channel: 'D2', thread: null };
  assert.equal(schedule.next([a, b], 0).channel, 'D1');
  assert.equal(schedule.next([a, b], 1), null, '메서드 2초 간격');
  assert.equal(schedule.next([a, b], 2).channel, 'D2');
  assert.equal(schedule.next([a, b], 4), null, '같은 대상은 15초 뒤');
  schedule.prioritize([a], 5);
  assert.equal(schedule.next([a, b], 5).channel, 'D1', '앞당김');
  schedule.retry(b, 60, 10, true);
  assert.equal(schedule.next([b], 30), null);
});

test('연결 흐름 — auth.test → apps.connections.open → hello → 이벤트 수신 · ack · 읽음 조회', async () => {
  const sent = [];
  const calls = [];
  let socket;
  class FakeSocket {
    constructor(url) { this.url = url; this.listeners = {}; socket = this; setImmediate(() => this.emit('message', { data: JSON.stringify({ type: 'hello' }) })); }
    addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
    emit(name, value) { for (const fn of this.listeners[name] || []) fn(value); }
    send(value) { sent.push(JSON.parse(value)); }
    close() { this.emit('close', {}); }
  }
  const responses = {
    'auth.test': { ok: true, user_id: 'U_ME', team_id: 'T123', team: '테스트' },
    'apps.connections.open': { ok: true, url: 'wss://wss-primary.slack.com/link?ticket=x' },
    'users.conversations': { ok: true, channels: [{ id: 'C1', name: 'general' }] },
    'users.info': { ok: true, user: { id: 'U_OTHER', name: 'other', profile: { display_name: '동료' } } },
    'conversations.info': { ok: true, channel: { id: 'D123', last_read: '1800000000.123456' } }
  };
  const fetchImpl = async (url, options) => {
    const method = url.split('/').pop();
    calls.push({ method, auth: options.headers.Authorization });
    return { status: 200, headers: { get: () => null }, json: async () => responses[method] };
  };
  let saved = null;
  const store = { read: () => saved, write: (v) => { saved = v; }, delete: () => { saved = null; } };
  let changes = 0;
  const integration = new slack.SlackIntegration({ store, fetchImpl, WebSocketImpl: FakeSocket, onChange: () => { changes += 1; } });
  assert.throws(() => integration.connect('bad', 'xapp-1'), (e) => e.kind === 'invalidTokens');
  integration.connect('xoxp-user', 'xapp-app');
  assert.deepEqual(saved, { userToken: 'xoxp-user', appToken: 'xapp-app' });
  await new Promise((r) => setTimeout(r, 30));
  assert.equal(integration.connectionState, 'connected');
  assert.equal(calls.find((c) => c.method === 'apps.connections.open').auth, 'Bearer xapp-app', '소켓 열기는 앱 토큰');
  assert.equal(calls.find((c) => c.method === 'auth.test').auth, 'Bearer xoxp-user');
  socket.emit('message', { data: JSON.stringify({ type: 'events_api', envelope_id: 'env-1', payload: event() }) });
  assert.deepEqual(sent, [{ envelope_id: 'env-1' }], '받은 이벤트에 ack');
  assert.equal(integration.payloads().length, 1);
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(integration.payloads()[0].sessionTitle, 'DM · 동료', '보낸 사람 이름을 찾아 쓴다');
  assert.deepEqual(integration.channels, [{ id: 'C1', name: 'general' }]);
  await integration.refreshReadState(integration.generation);
  assert.equal(integration.payloads().length, 0, 'Slack 에서 읽은 위치까지 지운다');
  integration.connect('', 'xapp-new');
  assert.deepEqual(saved, { userToken: 'xoxp-user', appToken: 'xapp-new' }, '비워 둔 토큰은 그대로 둔다');
  integration.disconnect();
  assert.equal(saved, null);
  assert.equal(integration.connectionState, 'disabled');
  assert.ok(changes > 0);
  integration.stop();
});
