import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const root = new URL('../../ios/SafariExtension/Resources/', import.meta.url);
const context = vm.createContext({ URL, TextEncoder });
for (const file of ['legacy.js', 'adapters.js']) vm.runInContext(readFileSync(new URL(file, root), 'utf8'), context);
const { KnowledgeLegacy: legacy, KnowledgeAdapters: adapters } = context;
const record = { videoID: 'dQw4w9WgXcQ', seconds: 10, title: 'Lesson', createdAt: 1_700_000_000_000, note: 'Keep my note' };

test('bookmark export/import retains exact locator, creation time and note without reapplying pre-roll', () => {
  const [restored] = legacy.parse(legacy.serialize([record]));
  for (const field of ['videoID', 'seconds', 'title', 'createdAt', 'note']) assert.equal(restored[field], record[field]);
  assert.equal(restored.preRoll, 0);
  assert.equal(legacy.parse(legacy.serialize([{ ...record, deletedAt: 1000 }])).length, 0);
});
test('legacy input is fully validated before native writes, rejecting malformed entries and oversized arrays', () => {
  const good = JSON.parse(legacy.serialize([record]));
  for (const edit of [value => value.version = 2, value => value.marks.push({ ...value.marks[0], time: -1 }), value => value.marks[0].videoId = '../escape', value => value.marks = Array(20001).fill(value.marks[0])]) {
    const input = structuredClone(good); edit(input); assert.throws(() => legacy.parse(JSON.stringify(input)));
  }
});
test('article and podcast adapters share a source envelope while preserving typed locators', () => {
  const article = adapters.capturePage({ url: 'https://example.org/article#paragraph', title: 'Article', text: 'Original sentence', paragraphID: 'paragraph' }, 'id', 1000);
  assert.equal(article.sourceURL, 'https://example.org/article'); assert.equal(article.locator.kind, 'article'); assert.equal(article.excerpt, 'Original sentence');
  const podcast = adapters.capturePage({ url: 'https://example.org/episode', title: 'Episode', seconds: 0, duration: 200, readyState: 4 }, 'id', 1000);
  assert.equal(podcast.locator.seconds, 0); assert.equal(podcast.locator.kind, 'podcast');
  assert.throws(() => adapters.capturePage({ url: 'https://example.org/', title: 'No quote' }, 'id', 1000));
  assert.throws(() => adapters.capturePage({ url: 'https://example.org/', title: 'Live', seconds: 3, duration: Infinity, readyState: 4 }, 'id', 1000));
});
