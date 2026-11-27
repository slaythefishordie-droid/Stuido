import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fixture, reference } from './history-reference.mjs';
await import('../../ios/SafariExtension/Resources/history-index.js');
const build = globalThis.KnowledgeHistoryIndex.build;
test('history preserves title aliases, stable ties, current filter, watch order and row order', () => {
  const marks = fixture(20000), index = build(marks), before = JSON.stringify(marks);
  for (const watched of [{}, {'00000000001': 999}, {'00000000002': 999}])
    for (const query of ['', 'old', '新版', '00000000001', 'missing'])
      for (const current of [undefined, null, '00000000001'])
        for (const sort of ['marked', 'watched']) {
          const expected = reference(marks, query, current, sort, watched);
          assert.deepEqual(index.videos(query, current, sort, watched).map(g => [g.id, g.title, g.recent, g.marks.length]),
            expected.map(g => [g.id, g.title, g.recent, g.marks.length]));
        }
  const id = '00000000001';
  assert.deepEqual(index.marks(id), reference(marks, '', id, 'marked', {})[0].marks.sort((a,b) => a.seconds-b.seconds));
  assert.equal(index.marks(id), index.marks(id));
  assert.equal(JSON.stringify(marks), before);
});
test('refresh replaces removed records and renamed titles; no stale index survives', () => {
  const marks = fixture(20), old = build(marks);
  const next = build(marks.filter(m => m.videoID !== '00000000001').map(m => ({...m, title: 'Changed'})));
  assert.ok(old.group('00000000001'));
  assert.equal(next.group('00000000001'), undefined);
  assert.equal(next.videos('book', undefined, 'marked', {}).length, 0);
  assert.ok(next.videos('changed', undefined, 'marked', {}).length);
  assert.deepEqual(build([]).videos('', undefined, 'watched', {}), []);
});
test('index loads before its consumer in Safari manifest', () => {
  const manifest = JSON.parse(readFileSync(new URL('../../ios/SafariExtension/Resources/manifest.json', import.meta.url)));
  const scripts = manifest.content_scripts[0].js;
  assert.ok(scripts.indexOf('history-index.js') >= 0);
  assert.ok(scripts.indexOf('history-index.js') < scripts.indexOf('quickmark-tools.js'));
});
