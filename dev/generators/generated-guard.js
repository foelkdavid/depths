// Protects hand edits from the asset generators (build-hexapod.js, build-crawlers.js).
//
// Every file a generator writes is recorded with its SHA-256 in a hidden manifest
// (.<script>.manifest.json). On the next run, before anything is written, files whose content no longer
// matches the manifest (e.g. glow/light rules changed in the editor's Materials dialog, numbers tuned
// in an .anim.json) stop the run with a list. Nothing is overwritten unless --force is given; then the
// edited files are first copied to .generator-backups/<script>-<time>/ (hidden from the asset browser).
// Extra files the editor created next to generated ones (per-part <stem>.materials.json) are reported;
// generators never touch them, so they keep applying.
//
// Usage at the top of a generator, right after require('fs'):
//   require('./generated-guard.js').start('build-crawlers', { skip: ['catalog.json'], dirs: ['parts-crawler'] });
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function start(script, { skip = [], dirs = [] } = {}) {
  const manifestFile = `.${script}.manifest.json`;
  const force = process.argv.includes('--force');
  let previous = {};
  try { previous = JSON.parse(fs.readFileSync(manifestFile, 'utf8')).files || {}; } catch { /* first run */ }

  const edited = Object.keys(previous).filter(f => fs.existsSync(f) && sha(f) !== previous[f]);
  const extra = [];
  for (const d of dirs) if (fs.existsSync(d)) for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (!f.startsWith('.') && !(p in previous) && Object.keys(previous).length) extra.push(p);
  }
  if (extra.length) console.log(`Note: kept files not made by ${script} (still applied by the engine):\n  ${extra.join('\n  ')}`);
  if (edited.length && !force) {
    console.error(`${script}: these generated files were changed since the last run (editor or by hand):\n  ${edited.join('\n  ')}\n` +
      'Nothing was written. Copy the changes into the script, or re-run with --force to back them up\n' +
      `to .generator-backups/ and regenerate.`);
    process.exit(2);
  }
  if (edited.length) {
    const dir = path.join('.generator-backups', `${script}-${new Date().toISOString().replace(/[:.]/g, '-')}`);
    for (const f of edited) { fs.mkdirSync(path.join(dir, path.dirname(f)), { recursive: true }); fs.copyFileSync(f, path.join(dir, f)); }
    console.log(`--force: backed up ${edited.length} edited file(s) to ${dir}`);
  }

  // Record every file the generator writes (paths relative to this folder).
  const written = new Set();
  const write = fs.writeFileSync;
  fs.writeFileSync = function (file, ...rest) {
    const r = write.call(fs, file, ...rest);
    const rel = path.relative(process.cwd(), path.resolve(String(file)));
    if (!skip.includes(rel)) written.add(rel);
    return r;
  };
  process.on('exit', code => {
    if (code !== 0) return;  // failed run: keep the old manifest
    const files = {};
    for (const f of [...written].sort()) if (fs.existsSync(f)) files[f] = sha(f);
    write.call(fs, manifestFile, JSON.stringify({ script: `${script}.js`, note: 'SHA-256 of generated files; see generated-guard.js', files }, null, 1) + '\n');
  });
}
module.exports = { start };
