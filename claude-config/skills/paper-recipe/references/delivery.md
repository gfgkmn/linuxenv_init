# 引用基础设施与交付

---

## 一、页码地图

```bash
pdftotext -layout paper.pdf paper.txt              # 全文, 保留版面
pdftoppm -png -r 150 -f <页> -l <页> paper.pdf out # 渲染某页, 读图必须用
```

逐页提取首行文本以建立页码映射表, 确保后文各项结论均可精确定位至具体页面:

```python
import pypdf
r = pypdf.PdfReader(pdf)
for i, pg in enumerate(r.pages):
    print(i+1, (pg.extract_text() or "").replace("\n", " ")[:160])
```

## 二、导入文献管理器

Bookends 提供了 AppleScript 接口, 完整接口定义可查阅 `sdef /Applications/Bookends.app`:

```applescript
tell application "Bookends"
  set refs to quick add "<arXiv ID 或 DOI 或 PMID>"
  set r to first publication item of front library window whose id is "<refID>"
  attach local pdf "<PDF 路径>" to r given «class atac»:"copy"
  add {r} to (first group item of front library window whose name is "<分组名>")
  sql search "authors REGEX '<姓氏>'"     -- 直接参数就是 SQL, 不要传分组名
end tell
```

`quick add` 会通过网络检索元数据, 其准确度显著高于基于文件名的推断. 文献库名称默认设定为 `Readventuer`.

## 三、逐句深链

本步骤应在研读全文并确定笔记内容后执行 (阶段 6), 而非在文献导入阶段执行: 唯有在完成全文阅读后, 方能确定所需引用的具体结论.

文献管理器仅为**已有批注**生成深度链接, 因此须预先向 PDF 中注入高亮标记. 相关脚本位于 `~/.claude/skills/paper-recipe/scripts/`, 调用时须指定完整绝对路径.

```
claims.json   [{"key","phrase","page","note"}, ...]
   ↓ python <skill>/scripts/inject_highlights.py <原始.pdf> <高亮版.pdf> claims.json
高亮版 PDF
   ↓ attach local pdf
   ↓ extract pdf annotations <path> for reference id "<refID>"
links.json    {key: {page, link, text}}
```

要点:

- phrase 须选取原文中具有唯一性的连续词段. 跨行连字符不影响匹配, 文本归一化处理时将自动去除.
- pdftotext 的坐标原点位于左上角, 而 PDF 批注的坐标原点位于左下角, 因此 y 轴坐标须执行翻转映射.
- 程序注入的高亮标记可被正常识别, 无须人工手动标注.
- **在将 PDF 关联至文献条目之前 `link` 字段为空**, 此执行顺序不可颠倒.
- 须利用 `contents` 字段回填 key, 因 extract 操作不会返回批注标题.

深链格式如下:

```
bookends://sonnysoftware.com/annotation/<库名>/<refID>/<附件ID>/<页-1>/<-x>/<-y>
```

条目级链接 `bookends://sonnysoftware.com/<refID>` 仅用于打开文献条目, 无法定位至具体语句.

## 四、写进笔记

**正文撰写阶段须统一使用占位符, 待成稿后集中替换.** 手动构造链接极易出错.

```python
out = re.sub(r"\{\{([a-z0-9\-]+)\}\}",
             lambda m: f'[<sup>p.{L[m.group(1)]["page"]}</sup>]({L[m.group(1)]["link"]})',
             src)
```

完成替换后须核验三项要求: 无遗漏的 key, 无残留的占位符, 无未使用的 key.
**存在未使用的 key 表明正文遗漏了对应结论**, 这是一个重要的自检机制.

### 链接格式

```
对   [<sup>p.14</sup>](bookends://...)
错   <sup>[p.14](bookends://...)</sup>
```

Obsidian 不解析行内 HTML 标签**内部**的 markdown 语法, 但支持解析 markdown 链接**标签内**的 HTML 标记. 若两者层级结构颠倒, 将被直接渲染为字面文本及括号中的 URL 字符串.

## 五、frontmatter

深链内嵌了文献库名称与 refID. 更换文献库会导致 ID 重新编号, 因此须预留充分的重建信息:

```yaml
arxiv: <ID 与版本>
bookends_id: "<refID>"
bookends_library: <库名>
bookends: bookends://sonnysoftware.com/<refID>
data: <数据集 URL>
pdf_pages: <总页数>
```

文件路径变更不会影响深链有效性, 因深链中不包含路径信息. 仅在迁移文献库时才需要重新定向, 届时通过修改 frontmatter 中的单行配置即可完成.

## 六、交付校验

**在覆盖写入 vault 之前须先执行备份, 并确认目标文件未被外部修改.**

```bash
cp "$VAULT_FILE" ./vault-backup-$(date +%Y%m%d)-<说明>.md
```

写入完成后须逐项核验:

- [ ] 无残留占位符, 无导出工具留下的冗余标记.
- [ ] 链接总数与 links.json 保持一致.
- [ ] 每一个 `![[...]]` 引用在 `assets/png/` 中均真实存在.
- [ ] frontmatter 元数据完整.
- [ ] **从 vault 文件中随机抽检一条深链**, 打开后确认准确定位至对应 PDF 页面.
- [ ] **双链回补**: 针对新笔记所引用的每篇既有笔记, 须返回相应旧笔记中, 将**所有**指向新笔记 (包括论文标题、作者年份等) 的纯文本提及均转换为显式双向链接, 严禁仅补全单处. 例外规则: 小节标题中的提及不添加链接 (小节标题作为入链锚点, 修改将破坏外部指向该标题的链接); 同一语句内已存在链接的重复提及无须重复添加. Markdown 表格单元格内的别名竖线须转义为 `\|`.
- [ ] **提示用户在 Obsidian 界面中实际核验渲染效果**.
- [ ] **若本次任务基于既有对话记录** (提取模式), 须将该记录标记为已消费:

```bash
python3 "/Users/gfgkmn/Documents/ChatgptHistory/Unified Search/consume.py" mark \
  --file "<对话 json 路径>" --method paper-recipe \
  --artifact "<笔记文件名>.md" --coverage full
```

冷启动论文 (精读模式, 无对话记录) 可跳过此项. 记账以对话自身的 `id` 为唯一凭据而非文件路径, 因而后续的文件重命名、去重或重新导出均不受影响. 记账完成后, `wkstat` 将新增一行 paper-recipe 记录, `ss` 检索中该条对话亦将显示 `✓✓ paper`.

最终视觉核验不可省略. URL 能够被底层系统解析, 并不等同于其在 Obsidian 中能正确渲染为可点击的链接. **核验重点在于实际渲染效果, 而非仅验证语法解析.**

## 七、标题与结构

- 文件名须严格保持原样, 以免破坏其他笔记中可能存在的反向链接.
- 严禁添加与文件名重复的 H1 一级标题, vault 知识库内的所有笔记均遵循此规范.
- 二级标题自 `## 1.` 开始编号, 以便于正文中的交叉引用 (如 `见 §6.1`).
- **跨笔记引用至具体小节时, 必须使用标题级链接** `[[笔记名#小节完整标题|显示文字 §N.n]]`, 严禁采用 "笔记级链接 + 纯文本小节号" 的形式 —— 该类链接点击后仅定位至笔记开头, 小节编号将失去导航作用. 推论: 修改小节标题前须检索是否存在指向该标题的标题级链接, 任何标题修改均会导致既有链接断裂.

## 八、语言

撰写完成后须调用 `stop-slop-zh` (中文) 或 `stop-slop` (英文) 进行审查, 严禁凭主观记忆套用规则.

重点复查要求: 文本加粗仅限术语首次出现及每节至多一处核心结论; 关键结论须独立成段呈现, 严禁淹没于推导论述之中; 评价性内容须全部置于论述主体之后.
