#!/usr/bin/env python3
"""Read acknowledgement without a broadcast, using the production local IPC reader."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile


def receive(peer):
    def exact(size):
        result = b''
        while len(result) < size:
            chunk = peer.recv(size - len(result))
            if not chunk:
                raise EOFError('reader disconnected before read confirmation')
            result += chunk
        return result
    return json.loads(exact(struct.unpack('<I', exact(4))[0]))


def send(peer, value):
    data = json.dumps(value).encode()
    peer.sendall(struct.pack('<I', len(data)) + data)


for initial in (True, None):
    with tempfile.TemporaryDirectory(prefix='retto-external-read-') as directory:
        ipc = Path(directory) / 'ipc'
        ipc.mkdir(mode=0o700)
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(ipc / 'ipc.sock'))
        os.chmod(ipc / 'ipc.sock', 0o600)
        server.listen(1)
        server.settimeout(8)
        expected = 'true,false' if initial else 'unknown,false'
        process = subprocess.Popen([str(Path(sys.argv[1]).resolve()), '--self-test-codex-input',
            '--live-codex-thread', 'fixture', '--live-codex-watch-reads',
            '--live-codex-read-expect', expected], env={**os.environ, 'CODEX_HOME': directory},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        peer = None
        try:
            peer, _ = server.accept()
            peer.settimeout(5)
            init = receive(peer)
            send(peer, {'type': 'response', 'method': 'initialize', 'requestId': init['requestId'],
                        'resultType': 'success', 'result': {'clientId': 'read-observer'}})
            assert receive(peer)['params']['following']

            def snapshot(revision, unread):
                state = {'id': 'fixture', 'threadRuntimeStatus': {'type': 'idle', 'activeFlags': []}, 'requests': []}
                if unread is not None:
                    state['hasUnreadTurn'] = unread
                return {'type': 'broadcast', 'method': 'thread-stream-state-changed', 'version': 11,
                        'sourceClientId': 'owner', 'targetClientIds': ['read-observer'],
                        'params': {'hostId': 'local', 'conversationId': 'fixture',
                                   'change': {'type': 'snapshot', 'revision': revision, 'conversationState': state}}}

            send(peer, snapshot(1, initial))
            # The user reads in Codex. Its owner updates state but sends no patch.
            follow = receive(peer)
            assert follow['method'] == 'thread-stream-following-changed' and follow['params']['following']
            send(peer, snapshot(2, False))
            # Delayed snapshots cannot restore unread after the newer read revision.
            send(peer, snapshot(1, True))
            out, err = process.communicate(timeout=8)
            assert process.returncode == 0, out + err
            assert 'Live Codex unread transitions: ' + expected in out, out
            # After a confirmed read, even the still-enabled read watch sends no further request.
            peer.settimeout(0.1)
            try:
                extra = peer.recv(1)
                assert extra == b'', 'confirmed read kept polling'
            except socket.timeout:
                pass
            print('PASS:', expected, 'without a native read broadcast; stale replay rejected; polling stopped')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            if peer:
                peer.close()
            server.close()
