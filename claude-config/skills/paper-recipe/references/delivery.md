# 引用基础设施与交付

---

## 一、页码地图

```bash
pdftotext -layout paper.pdf paper.txt              # 全文, 保留版面
pdftoppm -png -r 150 -f <页> -l <页> paper.pdf out # 渲染某页, 读图必须用
```

逐页抽首行建页码地图, 后面每条结论都要能落到具体页:

```python
import pypdf
r = pypdf.PdfReader(pdf)
for i, pg in enumerate(r.pages):
    print(i+1, (pg.extract_text() or "").replace("\n", " ")[:160])
```

## 二、导入文献管理器

Bookends 的 AppleScript 接口, 完整定义查 `sdef /Applications/Bookends.app`:

```applescript
tell application "Bookends"
  set refs to quick add "<arXiv ID 或 DOI 或 PMID>"
  set r to first publication item of front library window whose id is "<refID>"
  attach local pdf "<PDF 路径>" to r given «class atac»:"copy"
  add {r} to (first group item of front library window whose name is "<分组名>")
  sql search "authors REGEX '<姓氏>'"     -- 直接参数就是 SQL, 不要传分组名
end tell
```

`quick add` 会联网抓元数据, 比从文件名猜准得多. 库名默认 `Readventuer`.

## 三、逐句深链

这一步在读完论文、定了笔记内容之后做 (阶段 6), 不在导入时做: 要引用哪些结论,
读完才知道.

文献管理器只给**已有批注**生成深链, 所以要先往 PDF 里注入高亮. 脚本在
`~/.claude/skills/paper-recipe/scripts/`, 调用时写全路径.

```
claims.json   [{"key","phrase","page","note"}, ...]
   ↓ python <skill>/scripts/inject_highlights.py <原始.pdf> <高亮版.pdf> claims.json
高亮版 PDF
   ↓ attach local pdf
   ↓ extract pdf annotations <path> for reference id "<refID>"
links.json    {key: {page, link, text}}
```

要点:

- `phrase` 取原文里一段独特的连续词. 跨行连字符没关系, 归一化时会去掉
- pdftotext 坐标原点在左上, PDF 批注在左下, y 要翻转
- 程序写入的高亮能被正常识别, 不必手工标注
- **PDF 挂到条目之前 `link` 字段是空的**, 顺序不能反
- 用 `contents` 字段回填 key, extract 不返回注释标题

深链形如:

```
bookends://sonnysoftware.com/annotation/<库名>/<refID>/<附件ID>/<页-1>/<-x>/<-y>
```

条目级链接 `bookends://sonnysoftware.com/<refID>` 打开条目但不定位到句子.

## 四、写进笔记

**用占位符写正文, 最后统一替换.** 手写链接必错.

```python
out = re.sub(r"\{\{([a-z0-9\-]+)\}\}",
             lambda m: f'[<sup>p.{L[m.group(1)]["page"]}</sup>]({L[m.group(1)]["link"]})',
             src)
```

替换完检查三件事: 无遗漏 key, 无残留占位符, 无未使用的 key.
**未使用的 key 说明正文漏掉了一条结论**, 这是个很有用的自检.

### 链接格式

```
对   [<sup>p.14</sup>](bookends://...)
错   <sup>[p.14](bookends://...)</sup>
```

Obsidian 不解析行内 HTML 标签**内部**的 markdown, 但解析 markdown 链接**标签里**的
HTML. 写反了就渲染成字面文本加一串括号里的 URL.

## 五、frontmatter

深链里嵌了库名和 refID. 换库会让 id 重排, 所以要留够重建信息:

```yaml
arxiv: <ID 与版本>
bookends_id: "<refID>"
bookends_library: <库名>
bookends: bookends://sonnysoftware.com/<refID>
data: <数据集 URL>
pdf_pages: <总页数>
```

路径变化不影响深链, 它们不含路径. 只有换库才需要重指, 那时靠 frontmatter 一行就能改.

## 六、交付校验

**覆盖 vault 之前先备份, 并确认目标文件没被别人改过.**

```bash
cp "$VAULT_FILE" ./vault-backup-$(date +%Y%m%d)-<说明>.md
```

写入后逐项验:

- [ ] 无残留占位符, 无导出工具留下的垃圾标记
- [ ] 链接数量与 links.json 一致
- [ ] 每个 `![[...]]` 在 `assets/png/` 里真实存在
- [ ] frontmatter 完整
- [ ] **从 vault 文件里随机抽一条深链**, 打开后确认显示的是正确 PDF
- [ ] **双链回补**: 新笔记链到的每篇旧笔记, 回到旧笔记里把**所有**对新笔记
      (论文、作者年份) 的裸文字提及转成显式链接, 不是只补一条. 例外: 小节标题里
      的提及不加链 (标题是入链目标, 改了会断别人的标题链接); 同一句里已有链接的
      重复提及不再加. 表格单元格内的别名竖线要转义成 `\|`
- [ ] **让用户在 Obsidian 里实际看一眼**
- [ ] **若本次基于已有对话记录** (提取模式), 把该记录标记为已消费:

```bash
python3 "/Users/gfgkmn/Documents/ChatgptHistory/Unified Search/consume.py" mark \
  --file "<对话 json 路径>" --method paper-recipe \
  --artifact "<笔记文件名>.md" --coverage full
```

冷论文 (精读模式, 没有对话记录) 跳过这条. 记账用的是对话自身的 `id` 而不是路径,
所以之后文件改名、去重、重新导出都不影响. 记完 `wkstat` 会多一行 paper-recipe,
`ss` 里那条对话会显示 `✓✓ paper`.

最后一条不能省. URL 能被系统解析, 不等于在 Obsidian 里渲染成可点的链接.
**验渲染, 不是验解析.**

## 七、标题与结构

- 文件名保持原样, 别的笔记可能有反向链接
- 不要加与文件名重复的 H1, vault 里的笔记都不加
- `## 1.` 起编号, 便于正文交叉引用 (`见 §6.1`)
- **跨笔记引用到小节时, 必须用标题级链接** `[[笔记名#小节完整标题|显示文字 §N.n]]`,
  不要"笔记级链接 + 裸文字小节号"—— 那种链接点开落在笔记开头, 小节号成了死文字.
  推论: 改小节标题前先查有没有别的笔记用标题链接指着它, 改了会断链

## 八、语言

写完调用 `stop-slop-zh` (中文) 或 `stop-slop` (英文). 不要凭记忆套规则.

重点复查: 加粗只留术语首现和每节至多一处关键结论; 关键结论独立成段, 不要埋在推导段
中间; 评价性内容全部在主体之后.
