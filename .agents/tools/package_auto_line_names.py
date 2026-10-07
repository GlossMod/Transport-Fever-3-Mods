"""Validate and package the current naming mod without publishing it."""
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / 'staging_area/xiaom_auto_line_names'
OUT = ROOT / 'output/mod_packages'
OUT.mkdir(parents=True, exist_ok=True)
definition = json.loads((MOD/'mod.json').read_text(encoding='utf-8'))
assert definition['modId'] == MOD.name and definition['revision'] == 4
revision = definition['revision']
index = json.loads((MOD/'_content.json').read_text(encoding='utf-8'))
assert set(index['files']) == {p.name for p in (MOD/'content').iterdir() if p.is_file()}
assert (MOD/'_metadata/mod.io_fileid.txt').read_text().strip() == '6426466'
files = [MOD/'mod.json', MOD/'_content.json', MOD/'strings.json', MOD/'README.md', MOD/'VALIDATION.md']
files += sorted(p for p in (MOD/'content').rglob('*') if p.is_file())
files += sorted(p for p in (MOD/'_metadata').iterdir() if p.is_file())
for p in files:
    if p.suffix in ('.json', '.lua', '.md', '.txt'):
        raw = p.read_bytes()
        assert not raw.startswith(b'\xef\xbb\xbf'), p
        raw.decode('utf-8')
    if p.suffix == '.json':
        json.loads(p.read_text(encoding='utf-8'))
archive = OUT / f'xiaom_auto_line_names_r{revision}.zip'
with ZipFile(archive, 'w', ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, MOD.name + '/' + p.relative_to(MOD).as_posix())
with ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == len(files)
    for p in files:
        assert z.read(MOD.name + '/' + p.relative_to(MOD).as_posix()) == p.read_bytes()
report = {
    'modId': definition['modId'], 'revision': revision, 'modioBinding': 6426466,
    'status': 'packaged_pending_ingame_validation', 'uploaded': False,
    'automatedTests': 71, 'simulatedLines': 5000, 'maxLinesPerUpdate': 64,
    'archive': str(archive), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'coverSha256': hashlib.sha256((MOD/'_metadata/0.png').read_bytes()).hexdigest(),
    'files': [p.relative_to(MOD).as_posix() for p in files],
    'pending': ['Isolated game scenarios', 'Save/reload in game', f'Mod Manager revision {revision} validation'],
}
(OUT/f'xiaom_auto_line_names_r{revision}-status.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps({k: report[k] for k in ('status', 'archive', 'sha256')}, ensure_ascii=False, indent=2))
