"""Inspect completed PE/DWARF artifacts with Binutils; never launch Godot or GDB."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
import zlib

root = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf')
source = root / 'src'
evidence = Path(__file__).resolve().parent
build = json.loads((evidence / 'build-result.json').read_text(encoding='utf-8'))
if build['exit_code'] != 0:
    raise RuntimeError('Cannot claim completed artifacts from failed build')
binaries = list((source / 'bin').glob('godot.windows.editor.x86_64*.exe'))
if len(binaries) != 1:
    raise RuntimeError(f'Expected one console editor binary, got {binaries}')
binary = binaries[0]
symbols = Path(str(binary) + '.debugsymbols')
if not symbols.is_file():
    raise RuntimeError('Matching own .debugsymbols file missing')
def invoke(name, command):
    with (evidence / f'{name}.stdout.log').open('wb') as out, (evidence / f'{name}.stderr.log').open('wb') as err:
        result = subprocess.run(command, stdout=out, stderr=err, check=False, timeout=300)
    if result.returncode:
        raise RuntimeError(f'Binutils {name} failed: {result.returncode}')
    return (evidence / f'{name}.stdout.log')
binutils = root / 'toolchain/mingw64/bin'
invoke('binary-sections', [str(binutils / 'objdump.exe'), '-h', str(binary)])
invoke('symbol-sections', [str(binutils / 'objdump.exe'), '-h', str(symbols)])
debuglink_output = invoke('gnu-debuglink', [str(binutils / 'objdump.exe'), '-s', '-j', '.gnu_debuglink', str(binary)])
dump = bytearray()
for line in debuglink_output.read_text(encoding='utf-8', errors='replace').splitlines():
    match = re.match(r'^\s+[0-9a-fA-F]+\s+((?:[0-9a-fA-F]{8}\s+){1,4})', line)
    if match:
        dump.extend(bytes.fromhex(''.join(match.group(1).split())))
filename_end = dump.index(0)
linked_name = dump[:filename_end].decode('utf-8')
crc_offset = (filename_end + 1 + 3) & ~3
embedded_crc = int.from_bytes(dump[crc_offset:crc_offset + 4], 'little')
actual_crc = 0
with symbols.open('rb') as stream:
    while data := stream.read(1_048_576):
        actual_crc = zlib.crc32(data, actual_crc)
if linked_name != symbols.name or embedded_crc != actual_crc:
    raise RuntimeError('GNU debuglink filename/CRC does not match own symbol artifact')
symbol_sections = (evidence / 'symbol-sections.stdout.log').read_text(encoding='utf-8', errors='replace')
for section in ('.debug_info', '.debug_abbrev', '.debug_line'):
    if section not in symbol_sections:
        raise RuntimeError(f'Expected DWARF section missing: {section}')
nm_output = evidence / 'defined-symbols.stdout.log'
if '--reuse-nm' not in sys.argv[1:]:
    nm_output = invoke('defined-symbols', [str(binutils / 'nm.exe'), '--defined-only', '--demangle', str(symbols)])
elif not nm_output.is_file() or nm_output.stat().st_size == 0:
    raise RuntimeError('Previously completed raw nm output missing')
targets = ('ParticlesStorage::particles_get_instance_buffer_motion_vectors_offsets',
           'RenderForwardMobile::geometry_instance_create', 'RenderForwardMobile::geometry_instance_free',
           'RenderForwardMobile::_geometry_instance_update')
matches = []
with nm_output.open('r', encoding='utf-8', errors='replace') as stream:
    for line in stream:
        if any(target + '(' in line for target in targets):
            parts = line.strip().split(maxsplit=2)
            if len(parts) == 3 and parts[1] in ('t', 'T'):
                matches.append({'address': parts[0], 'type': parts[1], 'symbol': parts[2]})
for target in targets:
    if not any(target in item['symbol'] for item in matches):
        raise RuntimeError(f'Native target symbol missing: {target}')
output = invoke('addr2line-batch', [str(binutils / 'addr2line.exe'), '--exe', str(symbols), '--functions', '--demangle', *(item['address'] for item in matches)])
lines = output.read_text(encoding='utf-8', errors='replace').splitlines()
if len(lines) != 2 * len(matches):
    raise RuntimeError('Actual batch addr2line output cannot be paired to native targets')
for index, item in enumerate(matches):
    item['source_location'] = '\n'.join(lines[2 * index:2 * index + 2])
manifest = json.loads((evidence / 'source-files.json').read_text(encoding='utf-8'))
changed = []
for item in manifest['files']:
    path = source / item['path']
    disk = Path('\\\\?\\' + str(path))
    with disk.open('rb') as stream:
        actual_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual_sha != item['sha256']:
        changed.append(item['path'])
artifacts = []
for path in (binary, symbols):
    with path.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    artifacts.append({'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha})
report = {'build_exit_code': build['exit_code'], 'build_elapsed_seconds': build['elapsed_seconds'],
          'artifacts': artifacts, 'debuglink': {'filename': linked_name, 'embedded_crc32': embedded_crc, 'actual_crc32': actual_crc, 'match': True},
          'native_target_symbols': matches, 'original_source_files_checked': len(manifest['files']), 'original_source_changed': changed,
          'GPU_Main_or_GDB_executed': False, 'debugger_breakpoint_resolution_or_full_Main_reproduction': 'not executed; root later coordinates'}
(evidence / 'artifact-inspection.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
if changed:
    raise RuntimeError('Original archived source was changed by build; inspect actual changes before treating fixed source as retained')
