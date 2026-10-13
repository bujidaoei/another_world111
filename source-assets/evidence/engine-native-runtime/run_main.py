"""Run the existing real-input Main probe in an isolated diagnostic project."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time
import uuid

base = Path(__file__).resolve().parent
project = base / 'project'
native = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf')
engine = native / 'src/bin/godot.windows.editor.x86_64.exe'
mode = sys.argv[1] if len(sys.argv) > 1 else 'baseline'
if mode == 'official':
    engine = Path('D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe')
run_id = uuid.uuid4().hex
run = base / 'runs' / mode / run_id
run.mkdir(parents=True)
qa = project / 'tests/runtime/qa_character_session.tscn'
qa_text = '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://presentation/main.tscn" id="1_main"]\n\n[node name="CharacterPlaytest" instance=ExtResource("1_main")]\nsave_directory = "user://tests/engine_native_runtime/' + run_id + '"\n'
qa.write_text(qa_text, encoding='utf-8')
probe = (base.parent / 'standalone_character_probe.gd').read_text(encoding='utf-8')
probe = probe.replace('res://../artifacts/003-standalone-character-input', 'res://../artifacts/' + run_id + '/character-input')
probe = probe.replace('game._request_quit()', 'print("NATIVE_PILOT_OBSERVED ", JSON.stringify(driver.get("_pilot").get("results")))\n\t\tgame._request_quit()')
(project / 'native_main_probe.gd').write_text(probe, encoding='utf-8')
manifest = json.loads((base / 'source-input-manifest.json').read_text(encoding='utf-8'))['files']
def compare():
    return [f['path'] for f in manifest if f['path'] != 'tests/runtime/qa_character_session.tscn' and hashlib.sha256((project / f['path']).read_bytes()).hexdigest() != f['sha256']]
if compare():
    raise RuntimeError('Unexpected input changes before run')
env = os.environ.copy()
env['PATH'] = str(native / 'toolchain/mingw64/bin') + os.pathsep + env.get('PATH', '')
argv = [str(engine), '--path', str(project), '--script', 'res://native_main_probe.gd']
if mode == 'gdb':
    argv = [str(native / 'toolchain/mingw64/bin/gdb.exe'), '-nx', '-batch', '-x', str(base / 'capture_owner.gdb'), '--args'] + argv
clock = time.monotonic()
record = {'mode': mode, 'run_id': run_id, 'utc_started': datetime.now(timezone.utc).isoformat(), 'argv': argv, 'cwd': str(run), 'production_code_and_original_assets_changed': False, 'copy_source_count': len(manifest), 'pre_input_changed': compare(), 'adaptations': ['isolated QA save directory', 'standalone probe report destination'], 'probe_sha256': hashlib.sha256((project / 'native_main_probe.gd').read_bytes()).hexdigest(), 'qa_sha256': hashlib.sha256(qa.read_bytes()).hexdigest()}
record['engine_sha256'] = hashlib.sha256(engine.read_bytes()).hexdigest()
with (run / 'stdout.log').open('wb') as out, (run / 'stderr.log').open('wb') as err:
    proc = subprocess.Popen(argv, cwd=run, env=env, stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW)
    record['pid'] = proc.pid
    (run / 'started.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    (base / 'current-main-process.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    code = proc.wait()
report = base / 'artifacts' / run_id / 'character-input.json'
if report.exists():
    (run / 'character-input.json').write_bytes(report.read_bytes())
stdout = (run / 'stdout.log').read_text(encoding='utf-8', errors='replace')
stderr = (run / 'stderr.log').read_text(encoding='utf-8', errors='replace')
summary = {'mode': mode, 'run_id': run_id, 'exit_code': code, 'elapsed_seconds': time.monotonic() - clock, 'post_input_changed': compare(), 'report_exists': report.exists(), 'stdout_bytes': (run / 'stdout.log').stat().st_size, 'stderr_bytes': (run / 'stderr.log').stat().st_size, 'cpp759_occurrences': (stdout + stderr).count('particles_storage.cpp:759'), 'native_owner_null_traps': stdout.count('AW_NATIVE_PARTICLES_OWNER_NULL'), 'finish_lines': [line for line in stdout.splitlines() if 'CHARACTER_PROBE_FINISH' in line]}
(run / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps({'run': str(run), 'summary': summary}), flush=True)
raise SystemExit(code)
