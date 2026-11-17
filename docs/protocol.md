# ChatGPT 导入协议 1.0

规范文件：`schemas/import-package-1.0.schema.json`（JSON Schema Draft 2020-12）。`npm ci --ignore-scripts && npm test` 可在 Windows、macOS 或 Linux 的 Node.js 22+ 执行。`npm run validate -- examples/import/valid-four-types.json` 校验文件；`npm run validate -- -` 从 stdin 读取粘贴文本，使用相同解析器。

## 外层与四类内容

只接受 `schema_version="1.0"`、`package_id`、`title`、`sources`、`cards`、`relations`。所有对象拒绝未知字段。只有 `word`、`expression`、`keyword`、`key_sentence` 四种主类型。

| type | content 必填 | 可选 |
|---|---|---|
| word | word, definition_en, example_en | 无 |
| expression | text | 无 |
| keyword | term | explanation |
| key_sentence | text | explanation |

每张候选卡必填 `id/type/content/source_refs/language/tags/provenance`。`note` 是有来源的导入说明，落到 `import_annotation`，绝不覆盖 `personal_note`。协议不包含 Project 选择、整理状态、复习状态、Mark、ReviewRecord 或删除操作。

Sources 必填 `id/kind/title/url/sha256`，未知 URL/文件指纹填 null，不能猜测。kind 是 `pdf/epub/youtube/local_video/text`。URL 仅接受 HTTPS；不抓取 URL、不执行包内内容。原始文件在 Library 由用户导入，JSON 不携带二进制资料。

## 出处与字段级 provenance

`source_refs` 是卡片内的数组，每项 `{id, source_id, locator}`。`source_id` 指向本包 Source；引用项 ID 只在当前卡片内有效。

| locator | 规则 |
|---|---|
| PDF | `{ "type":"pdf", "file_page":1, "printed_page":"i" }`。`file_page` 从 1 起，表示 PDF 文件页序；`printed_page` 是可选印刷页码，不能替代文件页序。UI/PDFKit 的 0 起始索引只在适配层转换。 |
| EPUB | `{ "type":"epub", "chapter":"Chapter 1" }`，可带 `href/cfi/progression`；至少有 chapter/href/cfi 之一。progression 在 0–1。只有章节名不代表可以精确回跳。阅读器生产定位优先，未来保留版本化 Readium locator 适配层。 |
| 视频 | `{ "type":"video", "seconds":0 }`，非负、有限秒数，允许小数和有效 0 秒。YouTube 和本地视频使用相同时间模型。 |
| 缺失 | `locator:null`。预览提示待补全，禁用定位回跳；不能编造页码或 Mark。 |

`provenance.fields` 的键必须与实际 `content` 字段一一对应，值为 `{kind,source_ref_ids}`。kind 仅 `original/ai_explanation/ai_generated/user_input`。`original` 必须有至少一个有效出处引用；解释与创作也可引用材料作为依据，但不能变成原句。`note` 存在时 `provenance.note` 必填。

JSON Schema 负责结构约束；同一验证入口继续检查 ID 唯一、Source/Relation/provenance 引用、定位与资料类型对应、内容非空、字段级 provenance 完整。JSON 重复键、注释、尾逗号、Markdown 围栏均拒绝。错误包含 JSON Pointer 或字符偏移。入口限制 5 MiB、64 层，最多 1,000 Source / 5,000 Card / 10,000 Relation。

校验器无法证明原文真实、释义使用英文或页码来自材料；AI Inbox 必须展示出处和生成身份，交给用户核对。不得把 Schema 通过称为事实核验通过。

## ID、重复、确认事务

Source、Card、Relation 的包内 ID 在包中全局唯一；正式对象使用新 UUID。阶段 2 在**一个数据库事务**中建立包 ID → 正式 UUID 的映射并同步重映射 Relation 与出处；复用用户确认的 Source，不重复复制原文件。当前阶段只交付校验和重复预览，不写正式卡片库。

重复预览分两层：

- `packageFingerprint` 忽略包 ID、本地对象 ID、包标题和集合顺序，保留内容、说明、provenance、来源和关系。换 package_id 仍能识别同一批内容。相同 package_id 但内容变化标为冲突，不静默覆盖。
- `contentFingerprint` 根据主类型、语言和主体文本给出候选重复；规范化 Unicode NFC、空白，word/keyword 忽略大小写。不因此判定两个解释语义等同，不自动合并。

正式流程：解析校验 → 用户匹配 Source（文件指纹/链接只能辅助）→ 重复候选 → AI Inbox 预览 → 选择项目与 skip/keep/merge → 原子确认。合并前保留用户字段、出处与双方发现来源；关系指向跳过条目时必须有明确既有对象映射，否则阻止确认。批次记录存原始包摘要、输入指纹、用户决策与映射，以支持重试幂等。任何一步失败不得留下半份正式对象。外部 Card 引用在 1.0 不支持。

## 样例与版本

`examples/import/valid-*.json` 提供各类型和联合包；`invalid-*` 包含版本、类型、字段、重复 ID、无效关系和页序错误；`boundary-*` 包含 0 秒、缺失定位、章节名称；`duplicate-new-package-id.json` 应与联合包匹配同批内容。示例材料是明确声明的演示内容，不冒充真实出版物。

空 cards 允许，返回 empty_package 警告；表示没有可整理内容，不创建正式对象。未知版本必须拒绝。将来更新以 `1.1` / `2.0` 新 Schema 发布，显式迁移函数从旧格式生成新候选包，保留原始导入记录；不得静默重解释旧字段。备份格式版本、数据库迁移版本、导入协议版本和原型存储版本是四个独立版本。
