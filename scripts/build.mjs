// Bundles src/app/main.ts to dist/app.js and copies static files to dist/.
// public/config.js is copied only if the developer has placed it there (it is git-ignored).
import { build } from 'esbuild';
import { cp, mkdir, rm, copyFile, access } from 'node:fs/promises';

await rm('dist', { recursive: true, force: true });
await mkdir('dist', { recursive: true });

await build({
  entryPoints: ['src/app/main.ts'],
  bundle: true,
  format: 'esm',
  target: 'es2020',
  minify: true,
  sourcemap: false,
  outfile: 'dist/app.js',
  logLevel: 'warning',
});

await copyFile('index.html', 'dist/index.html');
await copyFile('src/styles/tokens.css', 'dist/styles.css');
await cp('public', 'dist', { recursive: true, filter: (src) => !src.endsWith('config.js') });
try {
  await access('public/config.js');
  await copyFile('public/config.js', 'dist/config.js');
  console.log('config.js copied (development file present)');
} catch {
  console.log('no config.js present: the app will show the configuration error screen');
}
console.log('build ok: dist/');
