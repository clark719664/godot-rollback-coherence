"""Real issue534 fixture, two Godot processes and delayed loopback UDP datagrams.

No packages, administrator privileges, firewall or system network changes needed.
"""
import argparse
import heapq
import json
import pathlib
import shutil
import socket
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Relay(threading.Thread):
    def __init__(self, server_port, proxy_port, delay_ms):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('127.0.0.1', proxy_port))
        self.sock.settimeout(.002)
        self.server = ('127.0.0.1', server_port)
        self.client = None
        self.delay_ms = delay_ms
        self.stop_event = threading.Event()
        self.packets = []
        self.count = 0
        self.delivered = 0
        self.delays = []

    def run(self):
        while not self.stop_event.is_set():
            try:
                data, source = self.sock.recvfrom(65535)
                if source == self.server:
                    destination = self.client
                else:
                    self.client = source
                    destination = self.server
                if destination:
                    # Fixed deterministic jitter [-20,+20]ms around 100ms one way.
                    jitter = ((self.count * 17) % 41) - 20 if self.delay_ms else 0
                    delay = (self.delay_ms + jitter) / 1000
                    self.count += 1
                    heapq.heappush(self.packets, (time.monotonic() + delay,
                                                 self.count, data, destination, delay))
            except socket.timeout:
                pass
            except ConnectionResetError:
                # Windows reports UDP ICMP port-unreachable when one peer exits.
                continue
            now = time.monotonic()
            while self.packets and self.packets[0][0] <= now:
                due, _, data, destination, delay = heapq.heappop(self.packets)
                self.sock.sendto(data, destination)
                self.delivered += 1
                self.delays.append(delay + now - due)
        self.sock.close()


def replace(text, old, new):
    if old not in text:
        raise RuntimeError('Fixture patch anchor missing: ' + old[:80])
    return text.replace(old, new)


def prepare(fixture, addon, destination, fixed, fault=False, automated=True):
    shutil.copytree(fixture, destination, ignore=shutil.ignore_patterns('.godot', 'addons'), dirs_exist_ok=True)
    shutil.copytree(fixture / 'addons' / 'delta-rollback', destination / 'addons' / 'delta-rollback', dirs_exist_ok=True)
    shutil.copytree(addon, destination / 'addons' / 'godot-rapier2d', dirs_exist_ok=True)
    shutil.copy2(ROOT / 'full_fixture' / 'TestRig.gd', destination / 'TestRig.gd')
    project = (destination / 'project.godot').read_text()
    project = replace(project, 'run/main_scene="uid://eaqjrw68n7hm"', 'run/main_scene="res://bomb-game-2d/BombGame.tscn"')
    project = replace(project, 'SyncManager="*uid://xohxvtt4jjfo"', 'SyncManager="*res://addons/delta-rollback/SyncManager.gd"')
    autoload = 'SyncReplay="*res://addons/delta-rollback/SyncReplay.gd"'
    if automated:
        autoload += '\nTestRig="*res://TestRig.gd"'
    project = replace(project, 'SyncReplay="*uid://dyeao8mh1nxea"', autoload)
    (destination / 'project.godot').write_text(project)
    player_path = destination / 'bomb-game-2d' / 'Player.gd'
    player = player_path.read_text()
    if automated:
        player = replace(player, 'func _get_local_input() -> Dictionary:', 'func _get_local_input() -> Dictionary:\n\treturn TestRig.scripted_input(self)\n\nfunc _unused_manual_input() -> Dictionary:')
    player_path.write_text(player)
    game_path = destination / 'bomb-game-2d' / 'BombGame.gd'
    if automated:
        game_path.write_text(replace(game_path.read_text(), 'network_rng.randomize()', 'network_rng.set_seed(12345)'))
    bomb_path = destination / 'bomb-game-2d' / 'Bomb.gd'
    bomb = bomb_path.read_text()
    if automated:
        bomb = replace(bomb, '\treturn bodies', '\tTestRig.observe_blast(position, radius, bodies)\n\treturn bodies')
    bomb_path.write_text(bomb)
    if not fixed:
        driver_path = destination / 'PhysicsDriver.gd'
        driver_path.write_text(replace(driver_path.read_text(),
            '\tRapierPhysicsServer2D.space_flush_queries(space)\n\nfunc _save_state',
            '\tRapierPhysicsServer2D.space_flush_queries(space)\n\tTestRig.verify_observed_blasts()\n\nfunc _save_state'))
    if fixed:
        shutil.copy2(ROOT / 'full_fixture' / 'CanonicalState.gd', destination / 'CanonicalState.gd')
        sync_path = destination / 'addons' / 'delta-rollback' / 'SyncManager.gd'
        sync_path.write_text(replace(sync_path.read_text(),
            'var serialized_hash: = sync_booster.hash_special_dict(input)',
            'var serialized_hash: = sync_booster.hash_special_dict(preload("res://CanonicalState.gd").ordered(input))'))
        shutil.copy2(ROOT / 'full_fixture' / 'PhysicsDriver.gd', destination / 'PhysicsDriver.gd')
        if fault:
            driver_path = destination / 'PhysicsDriver.gd'
            driver_path.write_text(replace(driver_path.read_text(),
                'func _network_postprocess(_input: Dictionary) -> void:',
                'func _network_postprocess(_input: Dictionary) -> void:\n\t_apply_blasts() # Deliberate query-before-step regression control.'))
        bomb_path = destination / 'bomb-game-2d' / 'Bomb.gd'
        bomb = bomb_path.read_text()
        bomb = replace(bomb, '\tfor rid in get_bodies_in_area(position, 100, SyncManager.bodies.keys()):\n\t\tSyncManager.bodies[rid].hurt(10)', '\tget_parent().get_node("PhysicsDriver").queue_blast(global_position, 100.0, 10)')
        bomb_path.write_text(bomb)


def run_case(args, label, fixed, delay):
    destination = args.run / label
    prepare(args.fixture, args.addon, destination, fixed, label == 'fault')
    with (destination / 'import.log').open('w') as log:
        subprocess.run([str(args.godot), '--headless', '--path', str(destination), '--editor', '--import', '--quit'], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
    relay = Relay(args.port, args.port + 1, delay)
    relay.start()
    processes, logs = [], []
    try:
        for role, port in [('server', args.port), ('client', args.port + 1)]:
            log = (destination / (role + '.log')).open('w')
            logs.append(log)
            cmd = [str(args.godot), '--headless', '--path', str(destination), '--', 'role=' + role,
                   'port=' + str(port), 'result=' + str(destination / (role + '.json'))]
            processes.append(subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT))
            if role == 'server':
                time.sleep(.8)
        exits = [process.wait(timeout=45) for process in processes]
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
        for log in logs:
            log.close()
        relay.stop_event.set()
        relay.join()
    peers = [json.loads((destination / (role + '.json')).read_text()) for role in ('server', 'client')]
    errors = [peer['error'] for peer in peers if peer['error']]
    for role in ('server', 'client'):
        for line in (destination / (role + '.log')).read_text().splitlines():
            if line.startswith(('ERROR:', 'SCRIPT ERROR:')):
                errors.append(role + ': ' + line)
    divergent = [tick for tick in peers[0]['samples'] if peers[0]['samples'][tick] != peers[1]['samples'].get(tick)]
    summary = {'case': label, 'fixed': fixed, 'delay_ms': delay, 'exits': exits, 'errors': errors,
               'divergent_completed_ticks': divergent, 'final_players': [p['players'] for p in peers],
               'rollbacks': [p['rollbacks'] for p in peers], 'mismatches': [p['state_mismatches'] for p in peers],
               'successful_restores': [p.get('successful_restores', 0) for p in peers],
               'restore_checks': [p.get('restore_checks', 0) for p in peers],
               'observed_rewinds': [p.get('observed_rewinds', 0) for p in peers],
               'animated_hitboxes': [p['animated_hitbox'] for p in peers],
               'query_checks': [p['query_checks'] for p in peers],
               'query_mismatches': [p['query_mismatches'] for p in peers],
               'observed_spawns': [p['observed_spawns'] for p in peers],
               'datagrams_delivered': relay.delivered,
               'injected_one_way_ms': [delay - 20, delay + 20] if delay else [0, 0],
               'measured_one_way_ms_min': min(relay.delays, default=0) * 1000,
               'measured_one_way_ms_max': max(relay.delays, default=0) * 1000}
    (destination / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps({k: v for k, v in summary.items() if k not in ('observed_spawns', 'divergent_completed_ticks')}))
    print('DIVERGENT_COMPLETED_TICKS=', len(divergent))
    return summary, peers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=pathlib.Path, required=True)
    parser.add_argument('--addon', type=pathlib.Path, required=True)
    parser.add_argument('--fixture', type=pathlib.Path, required=True)
    parser.add_argument('--run', type=pathlib.Path, required=True)
    parser.add_argument('--port', type=int, default=25341)
    parser.add_argument('--case', choices=['baseline', 'fixed', 'reference', 'fault', 'all'], default='all')
    parser.add_argument('--prepare-game', action='store_true', help='Create a patched game with the original manual menu and controls, without automation.')
    args = parser.parse_args()
    for name in ('godot', 'addon', 'fixture', 'run'):
        setattr(args, name, getattr(args, name).resolve())
    args.run.mkdir(parents=True, exist_ok=True)
    if args.prepare_game:
        prepare(args.fixture, args.addon, args.run, True, automated=False)
        # TestRig contains autoload references, so omit the unused test-only script.
        (args.run / 'TestRig.gd').unlink(missing_ok=True)
        with (args.run / 'import.log').open('w') as log:
            subprocess.run([str(args.godot), '--headless', '--path', str(args.run), '--editor', '--import', '--quit'], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
        print('Patched manual game ready: ' + str(args.run))
        return
    results = {}
    for label, fixed, delay in [('baseline', False, 100), ('reference', True, 0), ('fixed', True, 100), ('fault', True, 100)]:
        if args.case not in (label, 'all'):
            continue
        summary, peers = run_case(args, label, fixed, delay)
        results[label] = (summary, peers)
        if summary['errors'] or summary['exits'] != [0, 0]:
            raise RuntimeError('Fixture failed to complete: ' + label)
    if args.case == 'all':
        assert any(results['baseline'][0]['query_mismatches']), 'Original scheduling unexpectedly passed collision oracle'
        assert any(results['fault'][0]['query_mismatches']), 'Query-before-step negative control was not detected'
        for case in ('reference', 'fixed'):
            summary, peers = results[case]
            assert not summary['divergent_completed_ticks'], case + ' peers diverged'
            assert not any(summary['query_mismatches']), case + ' violated collision oracle'
            assert not any(summary['mismatches']), case + ' native state hashes diverged'
            assert all(summary['animated_hitboxes'])
            for peer in peers:
                spawns = peer['samples']['240']['/root/SyncManager/SpawnManager']
                assert spawns['counter'] == {'Bomb': 16, 'Explosion': 16}, 'Missing logical spawn'
                assert set(spawns['spawn_records']) == set(spawns['waiting_before_remove']), 'Some spawned objects never despawned'
            assert all(any(name.startswith('Bomb') for name in names) and any(name.startswith('Explosion') for name in names) for names in summary['observed_spawns'])
        assert all(results['fixed'][0]['rollbacks']), 'Delayed peers performed no rollback'
        assert all(results['fixed'][0]['successful_restores']), 'No successful native restore'
        assert all(results['fixed'][0]['restore_checks']), 'Native restored transforms/velocities were not checked'
        assert all(results['fixed'][0]['observed_rewinds']), 'No physical hitbox rewind was observed'
        assert results['fixed'][1][0]['samples'] == results['reference'][1][0]['samples'], 'Delayed completed states differ from zero-delay reference'
        print('PASS: original and query-before-step fault violate collision oracle; patched peers match each other and zero-delay reference at all 240 completed ticks.')


if __name__ == '__main__':
    main()
