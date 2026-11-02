#!/usr/bin/env python3
"""Fault injection against the production reader; synthetic local IPC only."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import random
import select
import socket
import struct
import subprocess
import tempfile
import time


def read(peer, size):
    result = bytearray()
    while len(result) < size:
        chunk = peer.recv(size - len(result))
        if not chunk:
            raise EOFError('reader disconnected')
        result.extend(chunk)
    return bytes(result)


def receive(peer):
    return json.loads(read(peer, struct.unpack('<I', read(peer, 4))[0]))


def send(peer, message, rng=None):
    data = json.dumps(message, separators=(',', ':')).encode() if isinstance(message, dict) else message
    data = struct.pack('<I', len(data)) + data
    if rng is None:
        peer.sendall(data)
    else:
        cursor = 0
        while cursor < len(data):
            length = rng.randint(1, 97)
            peer.sendall(data[cursor:cursor + length])
            cursor += length


def runtime(state):
    return {'type': {'running': 'active', 'waiting': 'active', 'idle': 'idle', 'failed': 'systemError'}[state],
            'activeFlags': ['waitingOnApproval'] if state == 'waiting' else []}


def snapshot(revision, state, target='reader-1', owner='owner', thread='fixture', padding=0, reordered=False):
    value = {'id': thread, 'threadRuntimeStatus': runtime(state), 'requests': [], 'resumeState': 'resumed'}
    if padding:
        value['ignoredBody'] = 'x' * padding
    change = {'type': 'snapshot', 'revision': revision, 'conversationState': value}
    params = ({'change': change, 'conversationId': thread, 'hostId': 'local'} if reordered else
              {'hostId': 'local', 'conversationId': thread, 'change': change})
    message = {'params': params, 'version': 11, 'sourceClientId': owner,
               'method': 'thread-stream-state-changed', 'type': 'broadcast'}
    if target is not None:
        message['targetClientIds'] = [target]
    return message


def patch(base, revision, state, target='reader-1', owner='owner'):
    result = snapshot(revision, state, target, owner)
    result['params']['change'] = {'type': 'patches', 'baseRevision': base, 'revision': revision,
                                 'patches': [{'op': 'replace', 'path': ['threadRuntimeStatus'], 'value': runtime(state)}]}
    return result


@contextmanager
def fixture(binary, expected, flags=()):
    with tempfile.TemporaryDirectory(prefix='retto-status-fault-') as directory:
        ipc = Path(directory) / 'ipc'
        ipc.mkdir(mode=0o700)
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(ipc / 'ipc.sock'))
        os.chmod(ipc / 'ipc.sock', 0o600)
        server.listen(8)
        server.settimeout(8)
        process = subprocess.Popen([str(binary), '--self-test-codex-input', '--live-codex-thread', 'fixture',
                                    '--live-codex-expect', ','.join(expected), *flags],
                                   env={**os.environ, 'CODEX_HOME': directory},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        peers = []

        def accept(client='reader-1', threads=1):
            peer, _ = server.accept()
            peers.append(peer)
            peer.settimeout(5)
            first = receive(peer)
            assert first['type'] == 'request' and first['method'] == 'initialize', 'new epoch sent before initialize'
            send(peer, {'type': 'response', 'method': 'initialize', 'requestId': first['requestId'],
                        'resultType': 'success', 'result': {'clientId': client}})
            for _ in range(threads):
                following = receive(peer)
                assert following['method'] == 'thread-stream-following-changed' and following['params']['following']
                assert following['sourceClientId'] == client, 'old observer ID reused after restart'
                accept.followed.setdefault(client, []).append(following['params']['conversationId'])
            return peer

        accept.server = server
        accept.followed = {}

        try:
            yield accept, process
            out, err = process.communicate(timeout=12)
            if process.returncode:
                raise AssertionError(out + '\n' + err)
        finally:
            for peer in peers:
                peer.close()
            server.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    checks = []

    with fixture(args.binary, ['running'], ['--live-codex-small-frames']) as (accept, _):
        peer = accept()
        send(peer, snapshot(0, 'waiting', target=None, padding=9000, reordered=True))
        send(peer, snapshot(1, 'waiting', target=None))
        send(peer, patch(1, 2, 'waiting'))
        send(peer, snapshot(3, 'waiting', target='prior-reader'))
        time.sleep(0.2)
        send(peer, snapshot(4, 'running'))
    checks.append('first targeted snapshot barrier rejects unsolicited waiting and pre-barrier patches')

    for restart in [False, True]:
        flags = ['--live-codex-reliability'] + (['--live-codex-stop-restart'] if restart else [])
        with fixture(args.binary, ['waiting', 'unavailable', 'running'], flags) as (accept, _):
            first = accept()
            send(first, snapshot(1, 'waiting'))
            if not restart:
                time.sleep(0.15)
                first.shutdown(socket.SHUT_RDWR)
                first.close()
            second = accept('reader-2')
            time.sleep(0.2)
            send(second, snapshot(1, 'running', target='reader-2'))
        checks.append('stop/restart clears old identity before initialization' if restart else 'EOF drops waiting and reconnects into fresh state')

    with fixture(args.binary, ['waiting', 'unavailable', 'running'], ['--live-codex-reliability']) as (accept, _):
        old = accept()
        send(old, snapshot(1, 'waiting'))
        fresh = accept('reader-2')  # Original socket stays open but never confirms requests.
        send(old, snapshot(1, 'waiting'))  # Delayed old-channel state cannot restore blue.
        send(fresh, snapshot(1, 'waiting', target='reader-1'))
        time.sleep(0.15)
        send(fresh, snapshot(2, 'running', target='reader-2'))
    checks.append('silent confirmation expires per thread; stale old-channel waiting cannot reenter')

    with fixture(args.binary, ['running', 'unavailable', 'waiting', 'running'], ['--live-codex-reliability']) as (accept, _):
        original = accept()
        send(original, snapshot(100, 'running', owner='owner-a'))
        time.sleep(0.1)
        send(original, snapshot(1, 'waiting', owner='owner-b'))
        fresh = accept('reader-2')
        send(original, snapshot(101, 'waiting', owner='owner-a'))
        send(fresh, snapshot(1, 'waiting', target='reader-1', owner='owner-a'))
        time.sleep(0.1)
        send(fresh, snapshot(1, 'waiting', target='reader-2', owner='owner-a'))
        time.sleep(0.1)
        send(original, snapshot(500, 'waiting', owner='owner-b'))
        send(fresh, snapshot(2, 'running', target='reader-2', owner='owner-a'))
    checks.append('owner change uses fresh targeted epoch; old observer packets remain fenced')

    with fixture(args.binary, ['running', 'unavailable', 'running'],
                 ['--live-codex-reliability', '--live-codex-untrack-retrack']) as (accept, _):
        original = accept()
        send(original, snapshot(100, 'running'))
        fresh = accept('reader-2')
        send(original, snapshot(101, 'waiting'))
        send(fresh, snapshot(1, 'running', target='reader-2'))
    checks.append('untrack and retrack use a new observer instead of reusing an old subscription marker')

    with fixture(args.binary, ['running', 'unavailable', 'waiting', 'unavailable', 'running'],
                 ['--live-codex-reliability', '--live-codex-untrack-on-wait']) as (accept, _):
        original = accept()
        send(original, snapshot(100, 'running', owner='owner-a'))
        time.sleep(0.1)
        send(original, snapshot(1, 'waiting', owner='owner-b'))
        child = accept('reader-2')
        send(child, snapshot(1, 'waiting', target='reader-2', owner='owner-b'))
        replacement = accept('reader-3')
        # The old child must close while the main process remains alive.
        child.settimeout(2)
        while True:
            try:
                receive(child)
            except EOFError:
                break
        send(replacement, snapshot(1, 'running', target='reader-3', owner='owner-b'))
    checks.append('dedicated recovery observer is explicitly closed before replacement')

    with fixture(args.binary, ['running', 'unavailable', 'running', 'waiting'],
                 ['--live-codex-reliability', '--live-codex-small-frames']) as (accept, _):
        original = accept()
        send(original, snapshot(100, 'running', owner='owner-a'))
        time.sleep(0.1)
        send(original, snapshot(1, 'waiting', owner='owner-b', padding=9000, reordered=True))
        fresh = accept('reader-2')
        send(fresh, snapshot(1, 'running', target='reader-2', owner='owner-a'))
        time.sleep(0.15)
        send(original, snapshot(120, 'waiting', owner='owner-a', padding=9000, reordered=True))
        send(fresh, snapshot(2, 'waiting', target='reader-2', owner='owner-a'))
    checks.append('oversized foreign owner validates separately; old-channel giants cannot quarantine a healthy fresh observer')

    rng = random.Random(764)
    with fixture(args.binary, ['waiting', 'running'], ['--live-codex-small-frames']) as (accept, _):
        peer = accept()
        send(peer, snapshot(10, 'waiting'))
        messages = [snapshot(11, 'running', target='another-reader', padding=9000, reordered=True),
                    snapshot(11, 'running', thread='untracked', padding=9000, reordered=True),
                    snapshot(9, 'running', padding=9000, reordered=True)]
        wrong_host = snapshot(11, 'running', padding=9000, reordered=True)
        wrong_host['params']['hostId'] = 'remote'
        messages.append(wrong_host)
        wrong_type = snapshot(11, 'running', padding=9000, reordered=True)
        wrong_type['type'] = 'request'
        messages.append(wrong_type)
        for message in messages:
            send(peer, message, rng)
        send(peer, b'{"ignored":"' + b'x' * 9000 + b'"}')
        time.sleep(0.2)
        send(peer, snapshot(11, 'running'))
    checks.append('foreign, untracked, retired revisions and unidentifiable oversized frames preserve healthy waiting')

    with fixture(args.binary, ['waiting', 'unavailable'], ['--live-codex-small-frames']) as (accept, _):
        peer = accept()
        send(peer, snapshot(1, 'waiting'))
        send(peer, snapshot(2, 'running', padding=9000, reordered=True), rng)
    checks.append('own oversized snapshot is attributed after trailing metadata and becomes unknown')

    with fixture(args.binary, ['waiting', 'running']) as (accept, _):
        peer = accept()
        send(peer, snapshot(1, 'waiting'))
        time.sleep(0.1)
        send(peer, b'{malformed complete frame')
        time.sleep(0.1)
        send(peer, snapshot(2, 'running'))
    checks.append('one malformed length-delimited payload does not disconnect healthy conversations')

    dormant = [f'dormant-{i}' for i in range(12)]
    with fixture(args.binary, ['running', 'waiting'],
                 ['--live-codex-reliability', '--live-codex-extra-threads', ','.join(dormant)]) as (accept, _):
        peer = accept(threads=len(dormant) + 1)
        send(peer, snapshot(1, 'running'))
        end = time.monotonic() + 3
        follows = 0
        while time.monotonic() < end:
            ready, _, _ = select.select([peer, accept.server], [], [], 0.1)
            assert accept.server not in ready, 'ownerless history spawned a dedicated recovery connection'
            if peer in ready:
                message = receive(peer)
                follows += message.get('method') == 'thread-stream-following-changed'
        assert follows <= 6 * (len(dormant) + 1), 'ownerless history created a follow-request flood'
        send(peer, snapshot(2, 'waiting'))
    checks.append('12 ownerless history sessions remain parked without recovery socket or follow floods')

    silent = [f'silent-{i}' for i in range(10)]
    with fixture(args.binary, ['running', 'waiting'],
                 ['--live-codex-reliability', '--live-codex-extra-threads', ','.join(silent)]) as (accept, _):
        primary = accept(threads=len(silent) + 1)
        send(primary, snapshot(1, 'running'))
        for thread in silent:
            send(primary, snapshot(1, 'waiting', owner='secondary-owner', thread=thread))
        children = []
        created = 0
        peak = 0
        end = time.monotonic() + 3
        while time.monotonic() < end:
            ready, _, _ = select.select([primary, accept.server, *children], [], [], 0.05)
            for peer in [p for p in ready if p is not accept.server]:
                try:
                    receive(peer)
                except EOFError:
                    assert peer is not primary, 'silent child reset the healthy main connection'
                    children.remove(peer)
            if accept.server in ready:
                created += 1
                child = accept(f'recovery-{created}')
                children.append(child)
                peak = max(peak, len(children))
                assert peak <= 4, 'recovery peers exceeded active plus closing bound'
                assert created <= len(silent) + 4, 'silent sessions continuously recreated observers'
        send(primary, snapshot(2, 'waiting'))
    checks.append(f'10 silent confirmed sessions preserve the healthy task and bound recovery peers (peak={peak}, initializations={created})')

    history = [f'validated-history-{i}' for i in range(16)]
    with fixture(args.binary, ['running', 'unavailable', 'waiting', 'running'],
                 ['--live-codex-extra-threads', ','.join(history),
                  '--live-codex-activity-thread', history[0]]) as (accept, _):
        primary = accept(threads=len(history) + 1)
        send(primary, snapshot(100, 'running', owner='owner-a'))
        for index, thread in enumerate(history):
            send(primary, snapshot(1, 'idle', owner='owner-a', thread=thread))
            send(primary, snapshot(2, 'idle', owner='owner-b', thread=thread))
            client = f'history-reader-{index}'
            child = accept(client)
            send(child, snapshot(2, 'idle', target=client, owner='owner-b', thread=thread))
            time.sleep(0.03)
        # All 16 healthy dedicated readers remain tracked. A current task must
        # reclaim an inactive slot rather than wait forever at the total cap.
        send(primary, snapshot(1, 'waiting', owner='owner-b'))
        current = accept('current-reader')
        send(primary, snapshot(101, 'waiting', owner='owner-a'))
        send(current, snapshot(1, 'waiting', target='current-reader', owner='owner-b'))
        resumed = accept('resumed-history-reader')
        assert accept.followed['resumed-history-reader'] == [history[0]], 'new activity failed to wake the evicted history task'
        send(resumed, snapshot(3, 'running', target='resumed-history-reader', owner='owner-b', thread=history[0]))
        send(current, snapshot(2, 'running', target='current-reader', owner='owner-b'))
    checks.append('17th recovering conversation reclaims an inactive slot; new per-thread activity wakes evicted history through a fresh observer')

    active = ['active-history-0', 'active-history-1']
    with fixture(args.binary, ['running', 'unavailable', 'waiting'],
                 ['--live-codex-fair-recovery', '--live-codex-extra-threads', ','.join(active)]) as (accept, process):
        primary = accept(threads=3)
        send(primary, snapshot(100, 'running', owner='owner-a'))
        children = []
        for index, thread in enumerate(active):
            send(primary, snapshot(1, 'running', owner='owner-a', thread=thread))
            send(primary, snapshot(2, 'running', owner='owner-b', thread=thread))
            client = f'active-reader-{index}'
            child = accept(client)
            children.append(child)
            send(child, snapshot(2, 'running', target=client, owner='owner-b', thread=thread))
            time.sleep(0.03)
        send(primary, snapshot(1, 'waiting', owner='owner-b'))
        current = accept('fair-current-reader')
        closed = False
        deadline = time.monotonic() + 2
        while not closed and time.monotonic() < deadline:
            ready, _, _ = select.select(children, [], [], 0.1)
            for child in ready:
                try:
                    receive(child)
                except EOFError:
                    closed = True
                    break
        assert closed and process.poll() is None, 'full active recovery pool did not explicitly release a reader'
        send(primary, snapshot(101, 'waiting', owner='owner-a'))
        send(current, snapshot(1, 'waiting', target='fair-current-reader', owner='owner-b'))
    checks.append('all-active recovery saturation gives a queued task a fresh observer through bounded fair slot rotation')

    for changed_owner, giant, future_schema in [(False, False, False), (True, False, False),
                                               (False, True, False), (False, False, True), (False, True, True),
                                               (False, True, 'string-revision'), (False, True, 'future-change')]:
        flags = ['--live-codex-small-frames'] if giant else []
        with fixture(args.binary, ['waiting', 'unavailable', 'running'], flags) as (accept, _):
            primary = accept()
            send(primary, snapshot(10, 'waiting'))
            time.sleep(0.1)
            unsupported = snapshot(11, 'running', owner='new-owner' if changed_owner else 'owner',
                                   padding=9000 if giant else 0, reordered=giant)
            unsupported['version'] = 12
            if future_schema == 'string-revision':
                unsupported['params']['change']['revision'] = '11'
            elif future_schema == 'future-change':
                unsupported['params']['change'] = ['future-shape']
                unsupported['params']['futurePayload'] = 'x' * 9000
            elif future_schema:
                unsupported['params']['change'].pop('revision')
                unsupported['params']['change']['type'] = 'future-state'
            send(primary, unsupported)
            fresh = accept('protocol-reader')
            send(primary, snapshot(10, 'waiting'))
            send(primary, snapshot(1000, 'waiting'))
            send(fresh, snapshot(12, 'waiting', target='reader-1'))
            time.sleep(0.1)
            send(fresh, snapshot(12, 'running', target='protocol-reader'))
        checks.append(f'unsupported protocol quarantines old observer and recovers through a fresh supported snapshot (newOwner={changed_owner}, giant={giant}, futureSchema={future_schema})')

    with fixture(args.binary, ['waiting', 'unavailable', 'running'], ['--live-codex-reliability']) as (accept, _):
        primary = accept()
        send(primary, snapshot(10, 'waiting'))
        time.sleep(0.1)
        unsupported = snapshot(11, 'running')
        unsupported['version'] = 12
        send(primary, unsupported)
        created = 0
        end = time.monotonic() + 1.5
        while time.monotonic() < end:
            ready, _, _ = select.select([accept.server], [], [], 0.05)
            if ready:
                created += 1
                assert created <= 2, 'unsupported protocol bypassed the bounded recovery failure budget'
                client = f'incompatible-reader-{created}'
                child = accept(client)
                message = snapshot(1, 'waiting', target=client, owner=f'changed-owner-{created}')
                message['version'] = 12
                send(child, message)
            send(primary, unsupported)
        assert created == 2, 'protocol recovery attempts were not charged consistently'
        assert not select.select([accept.server], [], [], 0.15)[0], 'unsupported traffic restarted a parked task'
        send(primary, snapshot(12, 'running'))
        fresh = accept('supported-again')
        send(fresh, snapshot(12, 'running', target='supported-again'))
    checks.append('permanently unsupported protocol parks after bounded failures; unsupported traffic cannot wake it, and supported state recovers freshly')

    cycling = ['waiting'] + ['unavailable', 'waiting'] * 7 + ['unavailable', 'running']
    with fixture(args.binary, cycling, ['--live-codex-cycle-observers']) as (accept, _):
        for index in range(9):
            client = f'epoch-reader-{index}'
            peer = accept(client)
            send(peer, snapshot(1, 'running' if index == 8 else 'waiting', target=client))
            time.sleep(0.03)
    checks.append('observer history budget rolls over repeatedly without rejecting fresh IDs or restoring old waiting')

    expected = ['running']
    plan = []
    revision = 1
    previous = 'running'
    for step in range(500):
        revision += 1
        state = rng.choice(['running', 'waiting', 'idle', 'failed'])
        message = snapshot(revision, state) if step % 31 == 0 else patch(revision - 1, revision, state)
        plan.append(message)
        if previous != state:
            expected.append(state)
            previous = state
        if step % 7 == 0:
            plan.append(snapshot(max(0, revision - 3), 'waiting'))
    with fixture(args.binary, expected) as (accept, _):
        peer = accept()
        send(peer, snapshot(1, 'running'))
        for message in plan:
            send(peer, message, rng)
    checks.append('500 deterministic state transitions with fragmented frames and delayed stale snapshots')

    for check in checks:
        print('PASS:', check)
    print('Status reliability fault scenarios:', len(checks), 'passed')


if __name__ == '__main__':
    main()
