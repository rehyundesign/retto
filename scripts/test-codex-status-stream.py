#!/usr/bin/env python3
"""Exercise the Swift reader with an isolated local IPC peer; no Codex data is read."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time


def send(peer, message, split=False):
    body = json.dumps(message).encode()
    frame = struct.pack('<I', len(body)) + body
    if split:
        peer.sendall(frame[:2])
        time.sleep(0.02)
        peer.sendall(frame[2:11])
        time.sleep(0.02)
        peer.sendall(frame[11:])
    else:
        peer.sendall(frame)


def receive(peer):
    def read(size):
        data = b''
        while len(data) < size:
            chunk = peer.recv(size - len(data))
            if not chunk:
                raise EOFError('reader disconnected')
            data += chunk
        return data
    return json.loads(read(struct.unpack('<I', read(4))[0]))


def snapshot(revision, pending=False):
    requests = [{'id': 'approval', 'method': 'mcpServer/elicitation/request'}] if pending else []
    return event({'type': 'snapshot', 'revision': revision,
                  'conversationState': {'id': 'fixture', 'threadRuntimeStatus': {'type': 'active', 'activeFlags': []},
                                        'requests': requests, 'title': 'synthetic fixture'}})


def event(change):
    return {'type': 'broadcast', 'method': 'thread-stream-state-changed', 'version': 11,
            'sourceClientId': 'fixture-owner', 'params': {'hostId': 'local', 'conversationId': 'fixture', 'change': change}}


with tempfile.TemporaryDirectory(prefix='retto-codex-stream-') as directory:
    ipc = Path(directory) / 'ipc'
    ipc.mkdir(mode=0o700)
    address = str(ipc / 'ipc.sock')
    server = socket.socket(socket.AF_UNIX)
    server.bind(address)
    os.chmod(address, 0o600)
    server.listen(1)
    server.settimeout(10)
    expected = 'running,waiting,running,unavailable,waiting,unavailable,waiting,unavailable'
    process = subprocess.Popen([str(Path(sys.argv[1]).resolve()), '--self-test-codex-input',
                                '--live-codex-thread', 'fixture', '--live-codex-expect', expected, '--live-codex-confirm-hook'],
                               env={**os.environ, 'CODEX_HOME': directory}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        peer, _ = server.accept()
        peer.settimeout(6)
        initialize = receive(peer)
        assert initialize['method'] == 'initialize'
        send(peer, {'type': 'response', 'method': 'initialize', 'requestId': initialize['requestId'],
                    'resultType': 'success', 'result': {'clientId': 'fixture-reader'}}, split=True)
        follow = receive(peer)
        assert follow['method'] == 'thread-stream-following-changed' and follow['params']['following']
        send(peer, snapshot(1), split=True)
        # A newly auto-approved hook must request exactly one fresh snapshot,
        # even though the active runtime and requests have not changed.
        confirmation = receive(peer)
        assert confirmation['method'] == 'thread-stream-following-changed' and confirmation['params']['following']
        send(peer, snapshot(1))
        peer.settimeout(0.3)
        try:
            receive(peer)
        except socket.timeout:
            pass
        else:
            raise AssertionError('same hook requested more than one confirmation snapshot')
        finally:
            peer.settimeout(6)
        send(peer, snapshot(2, pending=True))
        time.sleep(0.2)
        send(peer, event({'type': 'patches', 'baseRevision': 2, 'revision': 3,
                         'patches': [{'op': 'add', 'path': ['requests', 0, 'completed'], 'value': True}]}))
        time.sleep(0.2)
        # Duplicate old patch must not clear state or force a resubscription.
        send(peer, event({'type': 'patches', 'baseRevision': 1, 'revision': 2, 'patches': []}))
        time.sleep(0.1)
        for base, revision in [(40, 41), (50, 51)]:
            send(peer, event({'type': 'patches', 'baseRevision': base, 'revision': revision, 'patches': []}))
            follow = receive(peer)
            assert follow['method'] == 'thread-stream-following-changed' and follow['params']['following']
            time.sleep(0.2)
            send(peer, snapshot(revision + 1, pending=True))
            time.sleep(0.2)
        # Owner loss must discard waiting instead of retaining a phantom blue badge.
        send(peer, {'type': 'broadcast', 'method': 'client-status-changed', 'params': {'clientId': 'fixture-owner', 'status': 'disconnected'}})
        out, err = process.communicate(timeout=10)
        print(out.strip())
        if process.returncode:
            print(err, file=sys.stderr)
            raise SystemExit(process.returncode)
        print('IPC transport: fragmented frames, duplicate patches, repeated resync, owner disconnect, fresh hook confirmation passed')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        server.close()

# A resolved approval may not deliver its resolution patch. The running app must
# recheck cached waiting even when the hook has no tool ID or is already running.
with tempfile.TemporaryDirectory(prefix='retto-codex-pending-') as directory:
    ipc = Path(directory) / 'ipc'
    ipc.mkdir(mode=0o700)
    address = str(ipc / 'ipc.sock')
    server = socket.socket(socket.AF_UNIX)
    server.bind(address)
    os.chmod(address, 0o600)
    server.listen(1)
    server.settimeout(10)
    process = subprocess.Popen([str(Path(sys.argv[1]).resolve()), '--self-test-codex-input',
                                '--live-codex-thread', 'fixture', '--live-codex-expect', 'waiting,running',
                                '--live-codex-recheck-pending'], env={**os.environ, 'CODEX_HOME': directory},
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        peer, _ = server.accept()
        peer.settimeout(6)
        initialize = receive(peer)
        send(peer, {'type': 'response', 'method': 'initialize', 'requestId': initialize['requestId'],
                    'resultType': 'success', 'result': {'clientId': 'fixture-reader'}})
        follow = receive(peer)
        assert follow['method'] == 'thread-stream-following-changed' and follow['params']['following']
        send(peer, snapshot(1, pending=True))
        # Still genuinely waiting at the first refresh: blue must remain.
        refresh = receive(peer)
        assert refresh['method'] == 'thread-stream-following-changed' and refresh['params']['following']
        send(peer, snapshot(2, pending=True))
        peer.settimeout(0.2)
        try:
            receive(peer)
        except socket.timeout:
            pass
        else:
            raise AssertionError('fresh waiting snapshot caused an immediate refresh loop')
        finally:
            peer.settimeout(6)
        # The approval resolves without a patch. A later refresh must recover it.
        refresh = receive(peer)
        assert refresh['method'] == 'thread-stream-following-changed' and refresh['params']['following']
        send(peer, snapshot(3))
        out, err = process.communicate(timeout=10)
        print(out.strip())
        if process.returncode:
            print(err, file=sys.stderr)
            raise SystemExit(process.returncode)
        print('Pending recheck: genuine waiting preserved; missing resolution patch recovered; no refresh loop')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        server.close()
