"""Verified, scoped extraction for this diagnostic build; no installs or execution."""
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import hashlib
import json
import shutil
import stat
import sys
import tarfile
import zipfile
import zlib

TOOL_ROOT = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf').resolve()
EVIDENCE = Path(__file__).resolve().parent
ARCHIVE = Path('D:/bugu_projects/another_world/artifacts/godot-ed1daf0bf001b61586d9930840f2f1394092c079.tar.gz')
COMMIT = 'ed1daf0bf001b61586d9930840f2f1394092c079'
FILES = {
    'source': (ARCHIVE, 'e607e9985e1c201bc9cdc1aec8a120f0c3f53b9603f1f828e2b748534a2471ef'),
    'winlibs': (TOOL_ROOT / 'downloads/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip', 'c1f52294597c0b73786b2a78eb5d176d89226d2f21875eab75e783a8b1cefcc4'),
    'scons': (TOOL_ROOT / 'downloads/scons-4.11.1-py3-none-any.whl', '454cef364348053422696e3d2ecb4fa593c96a624f955842eaaea64f95c8d11d'),
}
verified = {}
for role, (path, expected) in FILES.items():
    with path.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != expected:
        raise RuntimeError(f'{role} SHA256 mismatch')
    verified[role] = {'path': str(path), 'bytes': path.stat().st_size, 'sha256': actual}
(EVIDENCE / 'verified-downloads.json').write_text(json.dumps(verified, indent=2), encoding='utf-8')

reserved = {'CON', 'PRN', 'AUX', 'NUL', *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}
def destination_for(target: Path, relative: str) -> Path:
    pure = PurePosixPath(relative.replace('\\', '/'))
    if pure.is_absolute() or not pure.parts or '..' in pure.parts:
        raise RuntimeError(f'Unsafe archive path: {relative}')
    for component in pure.parts:
        if ':' in component or '\x00' in component or component.endswith(('.', ' ')) or component.split('.')[0].upper() in reserved:
            raise RuntimeError(f'Unsafe Windows archive component: {relative}')
    destination = target.joinpath(*pure.parts).resolve()
    if not destination.is_relative_to(target.resolve()) or not destination.is_relative_to(TOOL_ROOT):
        raise RuntimeError(f'Archive escaped dedicated target: {relative}')
    return destination

def extended(path: Path) -> Path:
    # Do not modify global Windows long-path registry/settings.
    return Path('\\\\?\\' + str(path)) if sys.platform == 'win32' else path

toolchain = TOOL_ROOT / 'toolchain'
source = TOOL_ROOT / 'src'
resume_toolchain = '--resume-toolchain' in sys.argv[1:]
toolchain.mkdir(exist_ok=resume_toolchain)
source.mkdir(exist_ok=False)
package_files = []
with zipfile.ZipFile(FILES['winlibs'][0]) as package:
    for member in package.infolist():
        if stat.S_ISLNK(member.external_attr >> 16):
            raise RuntimeError('ZIP symbolic link is not allowed')
        destination = destination_for(toolchain, member.filename)
        if member.is_dir():
            extended(destination).mkdir(parents=True, exist_ok=True)
            continue
        if resume_toolchain:
            if destination.stat().st_size != member.file_size:
                raise RuntimeError(f'Existing verified toolchain size changed: {member.filename}')
            crc = 0
            with destination.open('rb') as disk:
                while data := disk.read(1_048_576):
                    crc = zlib.crc32(data, crc)
            if crc != member.CRC:
                raise RuntimeError(f'Existing verified toolchain CRC changed: {member.filename}')
        else:
            extended(destination.parent).mkdir(parents=True, exist_ok=True)
            with package.open(member) as src, extended(destination).open('xb') as dst:
                shutil.copyfileobj(src, dst, 1_048_576)
        with destination.open('rb') as disk:
            disk_sha = hashlib.file_digest(disk, 'sha256').hexdigest()
        package_files.append({'path': member.filename, 'bytes': member.file_size, 'sha256': disk_sha})

source_files = []
prefix = f'godot-{COMMIT}/'
with tarfile.open(ARCHIVE, 'r:gz') as bundle:
    for member in bundle:
        if member.isdir() and member.name == f'godot-{COMMIT}':
            continue
        if not member.name.startswith(prefix):
            raise RuntimeError(f'Unexpected fixed source root: {member.name}')
        destination = destination_for(source, member.name[len(prefix):])
        if member.isdir():
            extended(destination).mkdir(parents=True, exist_ok=True)
            continue
        if not member.isfile() or not member.name.startswith(prefix):
            raise RuntimeError(f'Unsupported fixed source member: {member.name}')
        extended(destination.parent).mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256()
        with bundle.extractfile(member) as src, extended(destination).open('xb') as dst:
            while data := src.read(1_048_576):
                dst.write(data)
                digest.update(data)
        source_files.append({'path': member.name[len(prefix):], 'bytes': member.size, 'sha256': digest.hexdigest()})

licenses = []
for path in toolchain.rglob('*'):
    if path.is_file() and (any(part.lower() in ('license', 'licenses', 'licences') for part in path.parts) or path.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'COPYRIGHT'))):
        with path.open('rb') as src:
            digest = hashlib.file_digest(src, 'sha256').hexdigest()
        licenses.append({'path': str(path.relative_to(toolchain)), 'bytes': path.stat().st_size, 'sha256': digest})
with zipfile.ZipFile(FILES['scons'][0]) as wheel:
    wheel_licenses = [{'path': name, 'bytes': wheel.getinfo(name).file_size, 'sha256': hashlib.sha256(wheel.read(name)).hexdigest()} for name in wheel.namelist() if 'license' in name.lower() and not name.endswith('/')]

(EVIDENCE / 'source-files.json').write_text(json.dumps({'commit': COMMIT, 'archive_sha256': verified['source']['sha256'], 'files': source_files}, indent=2), encoding='utf-8')
(EVIDENCE / 'toolchain-files.json').write_text(json.dumps({'files': package_files}, indent=2), encoding='utf-8')
(EVIDENCE / 'licenses-manifest.json').write_text(json.dumps({'toolchain': licenses, 'scons_wheel': wheel_licenses}, indent=2), encoding='utf-8')
summary = {'utc_finished': datetime.now(timezone.utc).isoformat(), 'tool_root': str(TOOL_ROOT), 'source_root': str(source), 'source_files': len(source_files), 'source_bytes': sum(f['bytes'] for f in source_files), 'toolchain_files': len(package_files), 'toolchain_bytes': sum(f['bytes'] for f in package_files), 'toolchain_license_files': len(licenses), 'scons_wheel_license_files': len(wheel_licenses), 'source_modified': False, 'GPU_or_binary_execution': False, 'original_failed_source_preserved': str(TOOL_ROOT / 'source'), 'resume_toolchain': resume_toolchain}
(EVIDENCE / 'extraction-summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps(summary))
