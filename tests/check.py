"""Run with python tests/check.py --luau-dir /path/to/luau binaries."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--luau-dir', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
installer = (root / 'INSTALL_ANIMATIONS_v0.3.lua').read_text()
for label, filename in [('combat', 'CombatServer_v0.3.lua'), ('boulder', 'BoulderServer_v0.3.lua'), ('localScript', 'CombatAnimationClient.lua')]:
    match = re.search(rf'{label}\.Source = \[====\[\n(.*?)\]====\]', installer, re.S)
    assert match and match[1].rstrip('\n') == (root / filename).read_text().rstrip('\n'), f'{filename} installer mismatch'
print('PASS: all three installer blocks match standalone sources', flush=True)
for path in root.glob('*.lua'):
    subprocess.run([str(args.luau_dir / 'luau-compile'), '--null', str(path)], check=True)
print('PASS: all four Lua files compile with Luau', flush=True)
with tempfile.TemporaryDirectory(prefix='ec-check-') as directory:
    combined = Path(directory) / 'animation_checks.luau'
    combined.write_text((root / 'tests/animation_runtime.luau').read_text() + '\n' + (root / 'CombatAnimationClient.lua').read_text() + '\n' + (root / 'tests/animation_assertions.luau').read_text())
    subprocess.run([str(args.luau_dir / 'luau'), str(combined)], check=True)
    combined = Path(directory) / 'installer_checks.luau'
    combined.write_text((root / 'tests/installer_runtime.luau').read_text() + '\nlocal function install()\n' + installer + '\nend\n' + (root / 'tests/installer_assertions.luau').read_text())
    subprocess.run([str(args.luau_dir / 'luau'), str(combined)], check=True)
