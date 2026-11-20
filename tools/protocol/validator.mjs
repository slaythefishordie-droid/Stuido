import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { parseTree, printParseErrorCode } from 'jsonc-parser';

export const schema = JSON.parse(readFileSync(new URL('../../schemas/import-package-1.0.schema.json', import.meta.url)));
const ajv = new Ajv2020({ allErrors: true, strict: true, validateFormats: true });
addFormats(ajv);
const validateSchema = ajv.compile(schema);
const issue = (path, code, message) => ({ path, code, message });

/** One entry point for file contents and pasted text. No imports, URLs, or content are executed. */
export function parsePackage(text) {
  if (Buffer.byteLength(text, 'utf8') > 5 * 1024 * 1024) {
    return { valid: false, errors: [issue('', 'size_limit', '导入包不能超过 5 MiB。')] };
  }
  const syntax = [];
  let root;
  try { root = parseTree(text, syntax, { disallowComments: true, allowTrailingComma: false }); }
  catch { return { valid: false, errors: [issue('', 'parse_error', 'JSON 结构过深或无法解析。')] }; }
  const errors = syntax.map(e => issue(`offset:${e.offset}`, 'parse_error', printParseErrorCode(e.error)));
  const visit = (node, path = '', depth = 0) => {
    if (!node) return;
    if (depth > 64) { errors.push(issue(path, 'depth_limit', 'JSON 嵌套不能超过 64 层。')); return; }
    if (node.type === 'object') {
      const keys = new Set();
      for (const entry of node.children ?? []) {
        const [key, value] = entry.children;
        const next = `${path}/${key.value.replaceAll('~', '~0').replaceAll('/', '~1')}`;
        if (keys.has(key.value)) errors.push(issue(next, 'duplicate_key', 'JSON 对象中出现重复字段。'));
        keys.add(key.value);
        visit(value, next, depth + 1);
      }
    } else if (node.type === 'array') {
      (node.children ?? []).forEach((value, index) => visit(value, `${path}/${index}`, depth + 1));
    }
  };
  visit(root);
  if (errors.length) return { valid: false, errors };
  let data;
  try { data = JSON.parse(text); }
  catch { return { valid: false, errors: [issue('', 'parse_error', '请输入严格 JSON，不含 Markdown 围栏。')] }; }
  return validatePackage(data);
}

export function validatePackage(data) {
  if (!validateSchema(data)) {
    return { valid: false, errors: validateSchema.errors.map(e => issue(e.instancePath, e.keyword, `${e.message} ${JSON.stringify(e.params)}`)) };
  }
  const errors = [];
  const warnings = [];
  if (data.cards.length === 0) warnings.push(issue('/cards', 'empty_package', '没有候选卡片；仅预览，不创建正式对象。'));
  const ids = new Set();
  for (const collection of ['sources', 'cards', 'relations']) {
    data[collection].forEach((item, index) => {
      if (ids.has(item.id)) errors.push(issue(`/${collection}/${index}/id`, 'duplicate_id', `包内 ID 重复：${item.id}`));
      ids.add(item.id);
    });
  }
  const sources = new Map(data.sources.map(s => [s.id, s]));
  const cardIDs = new Set(data.cards.map(c => c.id));
  data.cards.forEach((card, index) => {
    const path = `/cards/${index}`;
    const refs = new Set();
    card.source_refs.forEach((ref, j) => {
      const at = `${path}/source_refs/${j}`;
      if (refs.has(ref.id)) errors.push(issue(`${at}/id`, 'duplicate_ref_id', '卡片内出处引用 ID 重复。'));
      refs.add(ref.id);
      const source = sources.get(ref.source_id);
      if (!source) errors.push(issue(`${at}/source_id`, 'invalid_reference', '引用了不存在的 Source。'));
      const expected = source && ({ pdf: 'pdf', epub: 'epub', youtube: 'video', local_video: 'video', text: null })[source.kind];
      if (ref.locator && source && ref.locator.type !== expected) errors.push(issue(`${at}/locator`, 'locator_mismatch', '定位类型与资料类型不匹配。'));
      if (ref.locator === null) warnings.push(issue(at, 'location_missing', '出处定位待补全，不能宣称可回跳。'));
      if (ref.locator?.type === 'epub' && !ref.locator.href && !ref.locator.cfi) {
        warnings.push(issue(at, 'chapter_only', '仅有章节名称，尚无可验证的阅读器回跳位置。'));
      }
    });
    const contentKeys = Object.keys(card.content).sort();
    const provenanceKeys = Object.keys(card.provenance.fields).sort();
    if (JSON.stringify(contentKeys) !== JSON.stringify(provenanceKeys)) {
      errors.push(issue(`${path}/provenance/fields`, 'provenance_mismatch', '每个实际 content 字段必须有且只有一条 provenance。'));
    }
    if (('note' in card) !== ('note' in card.provenance)) errors.push(issue(`${path}/provenance/note`, 'provenance_mismatch', '导入说明存在时必须提供其 provenance。'));
    const checkReferences = (field, fieldPath) => {
      field.source_ref_ids.forEach((id, index) => {
        if (!refs.has(id)) errors.push(issue(`${fieldPath}/source_ref_ids/${index}`, 'invalid_reference', `不存在的出处引用：${id}`));
      });
    };
    for (const [key, field] of Object.entries(card.provenance.fields)) {
      checkReferences(field, `${path}/provenance/fields/${key}`);
    }
    if (card.provenance.note) checkReferences(card.provenance.note, `${path}/provenance/note`);
    for (const [key, value] of Object.entries(card.content)) {
      if (!value.trim()) errors.push(issue(`${path}/content/${key}`, 'empty_content', '内容不能只包含空白。'));
    }
  });
  data.relations.forEach((relation, index) => {
    for (const field of ['from_card_id', 'to_card_id']) {
      if (!cardIDs.has(relation[field])) errors.push(issue(`/relations/${index}/${field}`, 'invalid_reference', '关系只能引用本包中的 Card。'));
    }
    if (relation.from_card_id === relation.to_card_id) errors.push(issue(`/relations/${index}`, 'self_relation', '1.0 不支持自关系。'));
  });
  return errors.length ? { valid: false, errors } : { valid: true, data, errors: [], warnings };
}

const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return typeof value === 'string' ? value.normalize('NFC') : value;
};
const hash = value => createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
// Compute the canonical sort key once per value instead of once per comparison.
const sorted = values => values
  .map(value => ({ value, key: JSON.stringify(canonical(value)) }))
  .sort((left, right) => {
    if (left.key < right.key) return -1;
    if (left.key > right.key) return 1;
    return 0;
  })
  .map(entry => entry.value);

/** Content duplicates are suggestions, never automatic overwrite/merge instructions. */
export function contentFingerprint(card) {
  const key = { word: 'word', expression: 'text', keyword: 'term', key_sentence: 'text' }[card.type];
  let text = card.content[key].normalize('NFC').trim().replace(/\s+/gu, ' ');
  if (['word', 'keyword'].includes(card.type)) text = text.toLowerCase();
  return hash({ type: card.type, language: card.language, text });
}

/** Ignore package/local IDs and array order, but retain exact content, provenance and notes. */
export function packageFingerprint(data) {
  const sources = new Map(data.sources.map(({ id, ...source }) => [id, hash(source)]));
  const cards = new Map(data.cards.map(card => {
    const refs = new Map(card.source_refs.map(({ id, source_id, ...ref }) => [id, { ...ref, source: sources.get(source_id) }]));
    const mapField = field => ({ ...field, source_ref_ids: sorted(field.source_ref_ids.map(id => refs.get(id))) });
    return [card.id, hash({ type: card.type, content: card.content, language: card.language,
      tags: [...card.tags].sort(), source_refs: sorted([...refs.values()]), note: card.note,
      provenance: { fields: Object.fromEntries(Object.entries(card.provenance.fields).map(([k, p]) => [k, mapField(p)])),
        ...(card.provenance.note ? { note: mapField(card.provenance.note) } : {}) } })];
  }));
  return hash({ version: data.schema_version, sources: [...sources.values()].sort(), cards: [...cards.values()].sort(),
    relations: sorted(data.relations.map(({ id, from_card_id, to_card_id, ...relation }) => ({
      ...relation, from: cards.get(from_card_id), to: cards.get(to_card_id)
    }))) });
}

export function previewDuplicates(data, previousPackages = []) {
  const fingerprint = packageFingerprint(data);
  const sameContent = previousPackages.find(p => packageFingerprint(p) === fingerprint);
  const sameID = previousPackages.find(p => p.package_id === data.package_id);
  const seen = new Map();
  for (const previous of previousPackages) for (const card of previous.cards) seen.set(contentFingerprint(card), `previous:${previous.package_id}/${card.id}`);
  const contentDuplicates = [];
  for (const card of data.cards) {
    const key = contentFingerprint(card);
    if (seen.has(key)) contentDuplicates.push({ card_id: card.id, matches: seen.get(key), allowed_actions: ['skip', 'keep', 'merge_after_review'] });
    else seen.set(key, `incoming:${card.id}`);
  }
  return { batch: sameContent ? 'duplicate_content' : sameID ? 'same_id_changed_content' : 'new',
    fingerprint, content_duplicates: contentDuplicates };
}
