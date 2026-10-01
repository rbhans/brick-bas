import { readFile, writeFile, mkdir, copyFile, stat, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { gzipSync, gunzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';

// Lays out the Worker's static assets in dist/site/demos/brick-bas (the path
// the site forwards). Only exported public assets are included: never the
// source tree, local saves, connection bridge, credentials or test artifacts.
// The 38 MiB engine is stored gzipped (the static host's per-file limit is
// 25 MiB); deploy/worker.ts serves it with the right encoding.
const source = resolve(import.meta.dirname, '../dist/web');
const target = resolve(import.meta.dirname, '../dist/site/demos/brick-bas');
await rm(resolve(import.meta.dirname, '../dist/site'), { recursive: true, force: true });
const files = [
  'index.html', 'index.js', 'index.pck', 'index.wasm',
  'index.audio.worklet.js', 'index.audio.position.worklet.js',
  'index.png', 'index.icon.png', 'index.apple-touch-icon.png',
  'ASSET_CREDITS.md', 'GODOT-LICENSES.txt', 'LDraw-AUTHORS.json',
  'LDraw-LICENSE.txt', 'Audio-LICENSE.txt', 'Font-LICENSE.txt',
];
for (const file of files) await stat(join(source, file));
await mkdir(target, { recursive: true });
const manifest = { format: 'brick-bas-site-bundle', version: 1, files: {} };
for (const file of files) {
  const original = await readFile(join(source, file));
  const outputName = file === 'index.wasm' ? 'index.wasm.gz' : file;
  const output = file === 'index.wasm' ? gzipSync(original, { level: 9 }) : original;
  if (output.length > 25 * 1024 * 1024) throw new Error(`${file} exceeds the static host's 25 MiB per-asset limit`);
  if (file === 'index.wasm' && !gunzipSync(output).equals(original)) throw new Error('WASM compression round trip failed');
  if (file === 'index.wasm') await writeFile(join(target, outputName), output);
  else await copyFile(join(source, file), join(target, outputName));
  manifest.files[file] = { file: outputName, bytes: original.length, storedBytes: output.length, sha256: createHash('sha256').update(original).digest('hex') };
}
await writeFile(join(target, 'bundle.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Site bundle ready in ${target}. Engine: ${manifest.files['index.wasm'].bytes} → ${manifest.files['index.wasm'].storedBytes} bytes.`);
