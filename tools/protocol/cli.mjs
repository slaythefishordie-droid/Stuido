import { readFileSync } from 'node:fs';
import { parsePackage, previewDuplicates } from './validator.mjs';

try {
  const [file, previousFile] = process.argv.slice(2);
  if (!file) throw new Error('用法：npm run validate -- <package.json|-> [previous-package.json]');
  const result = parsePackage(readFileSync(file === '-' ? 0 : file, 'utf8'));
  if (!result.valid) {
    console.error(JSON.stringify(result, null, 2));
    process.exitCode = 1;
  } else {
    const previous = previousFile ? parsePackage(readFileSync(previousFile, 'utf8')) : null;
    if (previous && !previous.valid) throw new Error('用于比较的已有导入包无效。');
    console.log(JSON.stringify({ valid: true, cards: result.data.cards.length, warnings: result.warnings,
      preview: previewDuplicates(result.data, previous ? [previous.data] : []) }, null, 2));
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
