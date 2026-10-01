import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, copyFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const godot = process.env.GODOT_BIN || (process.platform === 'darwin' ? '/Applications/Godot.app/Contents/MacOS/Godot' : 'godot');
if (!existsSync(resolve(root, '.cache/godot-web/web_nothreads_release.zip'))) {
  console.error('Missing Godot 4.7.2 web export template. See docs/WEB_HOSTING.md for the official download and setup.');
  process.exit(1);
}
const output = resolve(root, 'dist/web');
await mkdir(output, { recursive: true });
await writeFile(resolve(root, 'dist/.gdignore'), '');
for (const args of [
  ['--headless', '--path', root, '--editor', '--import', '--quit'],
  ['--headless', '--path', root, '--export-release', 'Web', resolve(output, 'index.html')],
  ['--headless', '--path', root, '--script', 'res://tools/export_notices.gd'],
]) {
  const result = spawnSync(godot, args, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  if (result.error || result.status !== 0 || /(?:SCRIPT ERROR:|^ERROR:)/m.test(result.stderr || '')) {
    console.error(result.error || 'Godot reported an import/export error.'); process.exit(1);
  }
}
await copyFile(resolve(root, 'ASSET_CREDITS.md'), resolve(output, 'ASSET_CREDITS.md'));
await copyFile(resolve(root, 'assets/third_party/ldraw/CAlicense4.txt'), resolve(output, 'LDraw-LICENSE.txt'));
await copyFile(resolve(root, 'assets/third_party/ldraw/selection.json'), resolve(output, 'LDraw-AUTHORS.json'));
await copyFile(resolve(root, 'assets/third_party/kenney_interface/License.txt'), resolve(output, 'Audio-LICENSE.txt'));
await copyFile(resolve(root, 'assets/fonts/geist/OFL.txt'), resolve(output, 'Font-LICENSE.txt'));
console.log('Static web build ready in dist/web. Preview with npm run web:serve. No save server is required.');
