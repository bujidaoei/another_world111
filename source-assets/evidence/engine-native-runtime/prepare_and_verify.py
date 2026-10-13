"""Create a hash-checked Main diagnostic copy, then verify this build's own GDB symbols."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import time

base = Path(__file__).resolve().parent
workspace = base.parent.parent
native = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf')
engine = native / 'src/bin/godot.windows.editor.x86_64.exe'
gdb = native / 'toolchain/mingw64/bin/gdb.exe'
project = base / 'project'
if project.exists():
    raise RuntimeError('Diagnostic project already exists; do not overwrite evidence')
project.mkdir(parents=True)
files = []
for src in sorted((workspace / 'game').rglob('*')):
    rel = src.relative_to(workspace / 'game')
    if '.godot' in rel.parts or not src.is_file():
        continue
    dst = project / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    sha = hashlib.sha256(src.read_bytes()).hexdigest()
    if hashlib.sha256(dst.read_bytes()).hexdigest() != sha:
        raise RuntimeError(f'Copy mismatch: {rel}')
    files.append({'path': rel.as_posix(), 'sha256': sha, 'bytes': src.stat().st_size})
(base / 'source-input-manifest.json').write_text(json.dumps({'files': files}, indent=2), encoding='utf-8')
qa = project / 'tests/runtime/qa_character_session.tscn'
original = qa.read_text(encoding='utf-8')
adapted = original.replace('user://tests/character_playtest/20261013_003_b', 'user://tests/engine_native_runtime/20261013_003_native')
if original == adapted:
    raise RuntimeError('Expected isolated QA save path not found')
qa.write_text(adapted, encoding='utf-8')
probe = (workspace / 'artifacts/standalone_character_probe.gd').read_text(encoding='utf-8')
probe = probe.replace('res://../artifacts/003-standalone-character-input', 'res://../artifacts/native-character-input')
(project / 'native_main_probe.gd').write_text(probe, encoding='utf-8')
(base / 'copy-adaptations.json').write_text(json.dumps({'qa_original': original, 'qa_adapted': adapted, 'probe_source_sha256': hashlib.sha256((workspace / 'artifacts/standalone_character_probe.gd').read_bytes()).hexdigest(), 'production_files_changed': False, 'modifications': ['QA save path', 'standalone probe report path only']}, indent=2), encoding='utf-8')
env = os.environ.copy()
env['PATH'] = str(native / 'toolchain/mingw64/bin') + os.pathsep + env.get('PATH', '')
commands = {
    'gdb-version': [str(gdb), '--version'],
    'symbols': [str(gdb), '-nx', '-batch', '-ex', 'set pagination off', '-ex', 'set print pretty on', '-ex', 'info address RendererRD::ParticlesStorage::particles_get_instance_buffer_motion_vectors_offsets', '-ex', 'info line servers/rendering/renderer_rd/storage_rd/particles_storage.cpp:759', '-ex', 'info line servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp:2653', '-ex', 'info line servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp:3173', '-ex', 'break servers/rendering/renderer_rd/storage_rd/particles_storage.cpp:759 if particles == 0', '-ex', 'info breakpoints', '-ex', 'show debug-file-directory', '-ex', 'info files', str(engine)],
    'import': [str(engine), '--headless', '--path', str(project), '--editor', '--import'],
    'check': [str(engine), '--headless', '--path', str(project), '--script', 'res://native_main_probe.gd', '--check-only'],
}
results = []
for label, argv in commands.items():
    clock = time.monotonic()
    with (base / f'{label}.stdout.log').open('wb') as out, (base / f'{label}.stderr.log').open('wb') as err:
        process = subprocess.Popen(argv, cwd=base, env=env, stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW)
        (base / 'current-process.json').write_text(json.dumps({'stage': label, 'pid': process.pid, 'argv': argv, 'started': datetime.now(timezone.utc).isoformat()}, indent=2), encoding='utf-8')
        code = process.wait()
    results.append({'stage': label, 'exit_code': code, 'elapsed_seconds': time.monotonic() - clock, 'argv': argv})
    (base / 'verification-result.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(json.dumps(results[-1]), flush=True)
    if code != 0:
        raise SystemExit(code)

