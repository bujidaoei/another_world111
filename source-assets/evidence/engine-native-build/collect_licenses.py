"""Keep complete license documents and origins for this private diagnostic toolchain."""
from pathlib import Path
from urllib.request import Request, urlopen
import hashlib
import base64
import json
import re
import sys
import zipfile

root = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf')
evidence = Path(__file__).resolve().parent
output = evidence / 'licenses'
output.mkdir(exist_ok=True)
records = []
def preserve(name, data, origin):
    destination = output / name
    if destination.exists() and destination.read_bytes() != data:
        raise RuntimeError(f'Existing license evidence differs: {name}')
    if not destination.exists():
        destination.write_bytes(data)
    records.append({'file': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'origin': origin})
    (evidence / 'license-collection-progress.json').write_text(json.dumps({'complete': False, 'documents': records}, indent=2), encoding='utf-8')

preserve('Godot-MIT-LICENSE.txt', (root / 'src/LICENSE.txt').read_bytes(), 'Unmodified fixed Godot ed1daf0bf archive LICENSE.txt')
preserve('Godot-THIRDPARTY-COPYRIGHT.txt', (root / 'src/COPYRIGHT.txt').read_bytes(), 'Unmodified fixed Godot ed1daf0bf archive COPYRIGHT.txt; engine bundled third-party notices')
with zipfile.ZipFile(root / 'downloads/scons-4.11.1-py3-none-any.whl') as wheel:
    paths = [name for name in wheel.namelist() if 'license' in name.lower() and not name.endswith('/')]
    for index, name in enumerate(paths):
        preserve(f'SCons-notice-{index}-{Path(name).name}.txt', wheel.read(name), f'Verified SCons4.11.1 wheel: {name}')
preserve('GDB-bundled-Python-LICENSE.txt', (root / 'toolchain/mingw64/lib/python3.9/LICENSE.txt').read_bytes(), 'Verified WinLibs archive; mingw64/lib/python3.9/LICENSE.txt')
preserve('WinLibs-CPack-GenericLicense-Template.txt', (root / 'toolchain/mingw64/share/cmake-4.4/Templates/CPack.GenericLicense.txt').read_bytes(), 'Verified WinLibs archive; generic CPack template, not a complete CMake license')
documents = [
    ('GCC-GDB-GPL3-COPYING.txt', 'https://api.github.com/repos/gcc-mirror/gcc/contents/COPYING3?ref=releases/gcc-16.2.0', b'GNU GENERAL PUBLIC LICENSE'),
    ('GCC-RUNTIME-EXCEPTION-3.1.txt', 'https://api.github.com/repos/gcc-mirror/gcc/contents/COPYING.RUNTIME?ref=releases/gcc-16.2.0', b'GCC RUNTIME LIBRARY EXCEPTION'),
    ('MinGW-w64-14.0.0-COPYING.txt', 'https://api.github.com/repos/mingw-w64/mingw-w64/contents/COPYING?ref=v14.0.0', b'Copyright'),
    ('MinGW-w64-winpthreads-COPYING.txt', 'https://api.github.com/repos/mingw-w64/mingw-w64/contents/mingw-w64-libraries/winpthreads/COPYING?ref=v14.0.0', b'Copyright'),
]
for name, url, marker in documents:
    if '--from-dom' in sys.argv[1:]:
        dom_files = {
            'GCC-GDB-GPL3-COPYING.txt': ('license-dom-gpl3.json', 'https://github.com/gcc-mirror/gcc/blob/releases/gcc-16.2.0/COPYING3'),
            'GCC-RUNTIME-EXCEPTION-3.1.txt': ('license-dom-gcc-runtime.json', 'https://github.com/gcc-mirror/gcc/blob/releases/gcc-16.2.0/COPYING.RUNTIME'),
            'MinGW-w64-14.0.0-COPYING.txt': ('license-dom-mingw.json', 'https://github.com/mingw-w64/mingw-w64/blob/v14.0.0/COPYING'),
            'MinGW-w64-winpthreads-COPYING.txt': ('license-dom-winpthreads.json', 'https://github.com/mingw-w64/mingw-w64/blob/v14.0.0/mingw-w64-libraries/winpthreads/COPYING'),
        }
        dom_file, expected_url = dom_files[name]
        document = json.loads((evidence / dom_file).read_text(encoding='utf-8'))
        if document['url'] != expected_url or len(document['rawLines']) != document['lineCount']:
            raise RuntimeError('Actual source DOM provenance/line count mismatch')
        data = ('\n'.join(document['rawLines']) + '\n').encode('utf-8')
        url = expected_url + ' (complete Playwright DOM rawLines; normalized LF)'
    else:
        with urlopen(Request(url, headers={'User-Agent': 'AnotherWorld-native-license-evidence', 'Accept': 'application/vnd.github+json'}), timeout=20) as response:
            payload = response.read(200_001)
        if len(payload) > 200_000:
            raise RuntimeError('Unexpected GitHub license JSON size')
        document = json.loads(payload)
        data = base64.b64decode(document['content'])
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\x00' + data).hexdigest()
        if blob != document['sha']:
            raise RuntimeError('Official API Git blob mismatch')
    if marker.lower() not in data.lower():
        raise RuntimeError(f'Unexpected primary license document: {url}')
    preserve(name, data, url)
gdb = root / 'toolchain/mingw64/bin/gdb.exe'
strings = [b.decode('ascii') for b in re.findall(rb'[\x20-\x7e]{10,}', gdb.read_bytes()) if b'GPLv3' in b or b'License GPL' in b]
(evidence / 'gdb-license-binary-strings.json').write_text(json.dumps({'executed': False, 'path': str(gdb), 'matching_ascii_strings': strings}, indent=2), encoding='utf-8')
(evidence / 'preserved-license-manifest.json').write_text(json.dumps({'complete': True, 'documents': records, 'scope': 'Private diagnostic build; full core MIT/GPL/runtime-exception notices, package included notices retained; unused extra tool components are not redistributed', 'gdb_GPL_reference': 'https://sourceware.org/gdb/current/onlinedocs/gdb.html/Copying.html'}, indent=2), encoding='utf-8')
print(json.dumps({'documents': len(records), 'bytes': sum(r['bytes'] for r in records), 'GPU_or_GDB_executed': False}))
