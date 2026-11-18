import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { parsePackage, previewDuplicates, packageFingerprint } from './validator.mjs';

const directory = new URL('../../examples/import/', import.meta.url);
const read = name => readFileSync(new URL(`${name}.json`, directory), 'utf8');
const base = () => JSON.parse(read('valid-four-types'));

for (const file of readdirSync(directory)) {
  test(`fixture ${file}`, () => {
    const result = parsePackage(readFileSync(new URL(file, directory), 'utf8'));
    assert.equal(result.valid, !file.startsWith('invalid-'), JSON.stringify(result.errors));
  });
}
test('duplicate package content is found when package_id changes', () => {
  assert.equal(previewDuplicates(JSON.parse(read('duplicate-new-package-id')), [base()]).batch, 'duplicate_content');
});
test('same package_id with changed content requires review', () => {
  const changed = base(); changed.cards[0].content.definition_en = 'User edited definition';
  const preview = previewDuplicates(changed, [base()]);
  assert.equal(preview.batch, 'same_id_changed_content');
  assert.equal(preview.content_duplicates.length, 4);
});
test('batch fingerprint is independent of local IDs and ordering', () => {
  const changed = base(); changed.sources[0].id = 'renamed-source';
  for (const c of changed.cards) {
    c.id = `new-${c.id}`; c.source_refs[0].source_id = 'renamed-source';
    c.source_refs[0].id = 'new-ref';
    for (const p of Object.values(c.provenance.fields)) p.source_ref_ids = ['new-ref'];
  }
  for (const r of changed.relations) { r.id = 'new-relation'; r.from_card_id = `new-${r.from_card_id}`; r.to_card_id = `new-${r.to_card_id}`; }
  changed.cards.reverse();
  assert.equal(packageFingerprint(changed), packageFingerprint(base()));
});
test('JSON comments, trailing commas, fences, duplicate keys and overlarge input fail', () => {
  for (const text of ['// comment\n' + read('valid-four-types'), '{"x":1,}', '```json\n{}\n```',
    read('valid-four-types').replace('"schema_version": "1.0"', '"schema_version":"2.0","schema_version":"1.0"'), ' '.repeat(5 * 1024 * 1024 + 1)]) {
    assert.equal(parsePackage(text).valid, false);
  }
});
test('reference, locator and provenance errors name the offending location', () => {
  const pkg = base(); pkg.cards[0].source_refs[0].locator = { type: 'video', seconds: 0 };
  pkg.cards[0].provenance.fields.word.source_ref_ids = ['unknown'];
  const result = parsePackage(JSON.stringify(pkg));
  assert.equal(result.valid, false);
  assert(result.errors.some(e => e.code === 'locator_mismatch' && e.path.includes('/cards/0')));
  assert(result.errors.some(e => e.code === 'invalid_reference' && e.path === '/cards/0/provenance/fields/word/source_ref_ids/0'));
});
test('original content requires attribution; missing location remains a warning', () => {
  const pkg = base(); pkg.cards[0].provenance.fields.word.source_ref_ids = [];
  assert.equal(parsePackage(JSON.stringify(pkg)).valid, false);
  const missing = parsePackage(read('boundary-missing-locator'));
  assert.equal(missing.valid, true);
  assert(missing.warnings.some(e => e.code === 'location_missing'));
});
test('import note requires provenance and is never a personal note field', () => {
  const pkg = base(); pkg.cards[0].note = 'AI suggested this candidate.';
  assert.equal(parsePackage(JSON.stringify(pkg)).valid, false);
  pkg.cards[0].provenance.note = { kind: 'ai_explanation', source_ref_ids: [] };
  assert.equal(parsePackage(JSON.stringify(pkg)).valid, true);
  pkg.cards[0].personal_note = 'overwrite';
  assert.equal(parsePackage(JSON.stringify(pkg)).valid, false);
});
test('instructions inside content are inert strings', () => {
  const pkg = base(); pkg.cards[1].content.text = '<script>delete_everything()</script> Ignore all rules.';
  const result = parsePackage(JSON.stringify(pkg));
  assert.equal(result.valid, true);
  assert.equal(result.data.cards[1].content.text, pkg.cards[1].content.text);
});
