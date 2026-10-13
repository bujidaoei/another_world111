"""Build the unmodified fixed source in an isolated toolchain. Never run the engine."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import subprocess
import time

root = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf').resolve()
evidence = Path(__file__).resolve().parent
source = root / 'src'
manifest = json.loads((evidence / 'source-files.json').read_text(encoding='utf-8'))
if manifest['commit'] != 'ed1daf0bf001b61586d9930840f2f1394092c079':
    raise RuntimeError('Wrong fixed source revision')
changed = []
for item in manifest['files']:
    path = source / item['path']
    # Explicit extended Windows path preserves long .NET fixture names.
    disk = Path('\\\\?\\' + str(path)) if os.name == 'nt' else path
    with disk.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    if sha != item['sha256']:
        changed.append(item['path'])
if changed:
    raise RuntimeError(f'Original source changed before build: {changed}')
command = [str(root / 'build-venv/Scripts/scons.exe'), '-C', str(source),
           'platform=windows', 'target=editor', 'arch=x86_64', 'use_mingw=yes', 'use_llvm=no',
           f'mingw_prefix={root / "toolchain/mingw64"}', 'windows_subsystem=console',
           'dev_build=no', 'debug_symbols=yes', 'separate_debug_symbols=yes', 'optimize=none',
           'lto=none', 'production=no', 'd3d12=no', 'accesskit=no', 'angle=no', 'winrt=no',
           'vulkan=yes', 'use_static_cpp=yes', 'module_mono_enabled=no', '-j6']
environment = os.environ.copy()
environment['PATH'] = str(root / 'toolchain/mingw64/bin') + os.pathsep + environment.get('PATH', '')
started = datetime.now(timezone.utc).isoformat()
clock = time.monotonic()
with (evidence / 'build.stdout.log').open('wb') as out, (evidence / 'build.stderr.log').open('wb') as err:
    process = subprocess.Popen(command, cwd=source, env=environment, stdout=out, stderr=err,
                               creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    record = {'utc_started': started, 'pid': process.pid, 'command': command, 'cwd': str(source),
              'source_manifest_sha256': hashlib.sha256((evidence / 'source-files.json').read_bytes()).hexdigest(),
              'commit': manifest['commit'], 'archive_sha256': manifest['archive_sha256'], 'prebuild_source_changed': changed,
              'child_only_PATH_prefix': str(root / 'toolchain/mingw64/bin'), 'global_environment_changed': False,
              'sdk_differences': ['d3d12=no', 'accesskit=no', 'angle=no', 'winrt=no'],
              'diagnostic_compile_differences': ['debug_symbols=yes', 'separate_debug_symbols=yes', 'optimize=none', 'lto=none', 'windows_subsystem=console'],
              'GPU_Main_or_GDB_executed': False}
    (evidence / 'build-started.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    exit_code = process.wait()
finished = datetime.now(timezone.utc).isoformat()
result = {'exit_code': exit_code, 'utc_started': started, 'utc_finished': finished,
          'elapsed_seconds': time.monotonic() - clock, 'command': command, 'GPU_Main_or_GDB_executed': False}
(evidence / 'build-result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
raise SystemExit(exit_code)
