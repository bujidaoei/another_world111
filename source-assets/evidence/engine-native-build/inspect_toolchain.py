"""Record versions of build tools; do not execute Godot or GDB."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf')
evidence = Path(__file__).resolve().parent
commands = {
    'python': [str(root / 'build-venv/Scripts/python.exe'), '--version'],
    'scons': [str(root / 'build-venv/Scripts/scons.exe'), '--version'],
    'gcc': [str(root / 'toolchain/mingw64/bin/gcc.exe'), '-v'],
    'g++': [str(root / 'toolchain/mingw64/bin/g++.exe'), '-v'],
    'ld': [str(root / 'toolchain/mingw64/bin/ld.exe'), '--version'],
    'objcopy': [str(root / 'toolchain/mingw64/bin/objcopy.exe'), '--version'],
    'windres': [str(root / 'toolchain/mingw64/bin/windres.exe'), '--version'],
}
records = []
for name, command in commands.items():
    result = subprocess.run(command, capture_output=True, timeout=30, check=False)
    (evidence / f'{name}-version.stdout.log').write_bytes(result.stdout)
    (evidence / f'{name}-version.stderr.log').write_bytes(result.stderr)
    path = Path(command[0])
    with path.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    records.append({'tool': name, 'command': command, 'exit_code': result.returncode, 'bytes': path.stat().st_size, 'sha256': sha, 'stdout': result.stdout.decode('utf-8', 'replace'), 'stderr': result.stderr.decode('utf-8', 'replace')})
    if result.returncode != 0:
        raise RuntimeError(f'{name} version failed')
gcc = next(r for r in records if r['tool'] == 'gcc')
if 'Thread model: posix' not in gcc['stderr'] or 'Target: x86_64-w64-mingw32' not in gcc['stderr']:
    raise RuntimeError('GCC target/thread model does not match supported Windows diagnosis')
gdb = root / 'toolchain/mingw64/bin/gdb.exe'
with gdb.open('rb') as stream:
    gdb_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
records.append({'tool': 'gdb', 'path': str(gdb), 'bytes': gdb.stat().st_size, 'sha256': gdb_sha, 'executed': False, 'publisher_version': '17.2', 'version_evidence': 'Pinned publisher release and fixed archive manifest; GDB itself not run per root instruction'})
(evidence / 'tool-versions.json').write_text(json.dumps({'global_environment_changed': False, 'Godot_or_GDB_executed': False, 'tools': records}, indent=2), encoding='utf-8')
print(json.dumps({'tools_checked': len(commands), 'gcc_target': 'x86_64-w64-mingw32', 'gcc_threads': 'posix', 'gdb_executed': False}))
