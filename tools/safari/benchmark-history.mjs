import assert from 'node:assert/strict';
import { fixture, reference } from './history-reference.mjs';
await import('../../ios/SafariExtension/Resources/history-index.js');
const queries = ['', 'b', 'bo', 'book', 'book 2', 'old', '新版', 'missing'];
const watched = {'00000000003': 999999};
function measure(action) {
  const samples = []; let checksum = 0;
  for (let i = 0; i < 21; i++) { const start = performance.now(); checksum += action(); samples.push(performance.now()-start); }
  return {samples_ms: samples, median_ms: [...samples].sort((a,b)=>a-b)[10], checksum};
}
const datasets = [100, 2000, 20000].map(count => {
  const marks = fixture(count), index = KnowledgeHistoryIndex.build(marks);
  for (const q of queries) assert.deepEqual(index.videos(q,undefined,'watched',watched).map(g=>g.id),reference(marks,q,undefined,'watched',watched).map(g=>g.id));
  const before = measure(() => queries.reduce((sum,q)=>sum+reference(marks,q,undefined,'watched',watched).length,0));
  const after = measure(() => queries.reduce((sum,q)=>sum+index.videos(q,undefined,'watched',watched).length,0));
  assert.equal(before.checksum,after.checksum);
  const build = measure(() => KnowledgeHistoryIndex.build(marks).videos('',undefined,'marked',watched).length);
  return {marks: count, queries: queries.length, before, after, build};
});
console.log(JSON.stringify({node:process.version,iterations:21,scope:'Node projection only; excludes DOM, native messaging, Safari and device energy.',datasets},null,2));
