#!/usr/bin/env python3
"""Validate pinned Too dependencies and release identity without building."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'ArcadeDemoManifest.json').read_text())
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

check(manifest['sharedSourceRoot'] == 'ArcadeShared', 'Arcade dependencies must be inside MyFitbites.')
snapshot = root / manifest['sharedSourceRoot']
members = manifest['sources'] + manifest['resources']
check(len(members) == len(set(members)), 'Duplicate manifest membership.')
check(set(members) == set(manifest['sha256']), 'Checksums do not cover the full manifest.')
actual = {str(p.relative_to(snapshot)) for p in snapshot.rglob('*') if p.is_file() and p.name != '.DS_Store'}
check(actual == set(members), 'Snapshot inventory differs from the manifest.')
for rel in members:
    path = snapshot / rel
    check(path.is_file(), f'Missing dependency: {rel}')
    check(not path.is_symlink() and path.resolve().is_relative_to(snapshot.resolve()), f'External dependency: {rel}')
    if path.is_file():
        check(hashlib.sha256(path.read_bytes()).hexdigest() == manifest['sha256'].get(rel), f'Changed snapshot file: {rel}')
check(len({Path(p).name for p in manifest['resources']}) == len(manifest['resources']), 'Resource names collide in the bundle.')

project = root / 'MyFitbites.xcodeproj/project.pbxproj'
objects = json.loads(subprocess.check_output(['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(project)]))['objects']
group = objects['195A53EB70E818E35BFCDD74']
check(group['path'] == 'ArcadeShared', 'Xcode still references a sibling checkout.')
check({objects[ref]['path'] for ref in group['children']} == set(members), 'Xcode shared group differs from manifest.')
for kind, phase in [('sources', 'A10000000000000000000008'), ('resources', 'A10000000000000000000009')]:
    paths = [objects[objects[build]['fileRef']]['path'] for build in objects[phase]['files']]
    check(set(paths) == set(manifest[kind]) and len(paths) == len(set(paths)), f'Xcode {kind} phase differs from manifest.')
for config in ['A1000000000000000000000E', 'A1000000000000000000000F']:
    settings = objects[config]['buildSettings']
    check(settings['DEVELOPMENT_TEAM'] == '9V3UZFAA66', 'Configuration is not assigned to the organization.')
    check(settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'vn.com.fitbites.MyFitbites', 'Production Bundle ID changed.')

app = root / 'MyFitbites'
compiled = '\n'.join(p.read_text() for directory in [app, snapshot] for p in directory.rglob('*.swift'))
for forbidden in ['TielPlatformScene', 'TielPlatformScreen', 'TielHomeScreen', 'tielDemo', '"--arcade-tiel-preview"', '"tiel_demo"']:
    check(forbidden not in compiled, f'Removed platformer still compiled: {forbidden}')
picker = (app / 'Features/Progress/ProgressView.swift').read_text()
check('[.tooDemo, .puzzle]' in picker, 'The picker must retain Too and Puzzle.')
check('Text("3 GAMES")' not in picker, 'Arcade count still includes the removed preview.')
check(not (app / 'Resources/Assets.xcassets/ArcadeTielIcon.imageset').exists(), 'Removed preview icon is still bundled.')
check(manifest['availableGames'] == ['too_demo', 'puzzle'], 'Unexpected game lineup.')

if errors:
    print('\n'.join('ERROR: ' + error for error in errors), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(manifest["sources"])} pinned sources, {len(manifest["resources"])} resources; Too + Puzzle; organization identity.')
