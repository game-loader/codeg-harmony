import { pasteboard } from '@kit.BasicServicesKit'
import { MdBlock, MdKind, MdListItem, MdSpan, SpanKind, fileIconFor, parseInline, parseMarkdown } from './MarkdownParse'
import { parseFileTarget } from '../session/FileRefs'
import { LinkRouter } from './Links'
import { sym, toast } from './Common'
import { L } from '../common/I18n'
import { math, MathImage } from './MathRenderer'
import { normalizeTex, texToRuns, TexRun } from './TexLite'
import { LengthMetrics } from '@kit.ArkUI'
import { layout } from '../store/Layout'

/** Re-evaluated whenever a formula finishes rendering (reads math.version). */
function inlineSpans(text: string, v: number): MdSpan[] {
  return v >= 0 ? parseInline(text) : []
}

function spanKey(s: MdSpan, i: number, size: number): string {
  const ready = s.kind === SpanKind.Math && math.has(normalizeTex(s.text), false, layout.inkColor, size)
  return `${i}-${s.kind}-${s.text}-${ready}`
}

function inlineMath(tex: string, size: number): MathImage | undefined {
  const m = math.get(normalizeTex(tex), false, layout.inkColor, size)
  return m !== undefined && !m.failed ? m : undefined
}

export function copyText(s: string): void {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, s)
    pasteboard.getSystemPasteboard().setDataSync(data)
    toast(L('Copied', '已复制'))
  } catch (e) {
    toast(L('Copy failed', '复制失败'))
  }
}

function baseName(p: string): string {
  const parts = p.split('/')
  return parts[parts.length - 1]
}

@Builder
export function InlineText(text: string, size: number, color: ResourceColor, weight: FontWeight, root: string) {
  Text() {
    ForEach(inlineSpans(text, math.version), (s: MdSpan) => {
      if (s.kind === SpanKind.Code) {
        Span(` ${s.text} `)
          .fontFamily('monospace')
          .fontSize(size - 1.5)
          .fontColor($r('app.color.code_text'))
          .textBackgroundStyle({ color: $r('app.color.code_bg'), radius: 5 })
      } else if (s.kind === SpanKind.CodeFile) {
        // A path in backticks: still code, but tapping it opens the file.
        Span(` ${s.text} `)
          .fontFamily('monospace')
          .fontSize(size - 1.5)
          .fontColor($r('app.color.accent'))
          .textBackgroundStyle({ color: $r('app.color.code_bg'), radius: 5 })
          .onClick(() => LinkRouter.open(s.href, root))
      } else if (s.kind === SpanKind.Math) {
        if (inlineMath(s.text, size) !== undefined) {
          ImageSpan(inlineMath(s.text, size)?.png ?? '')
            .width(inlineMath(s.text, size)?.w ?? 0)
            .height(inlineMath(s.text, size)?.h ?? 0)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .objectFit(ImageFit.Fill)
        } else {
          // Native fallback: real sub/superscripts until (or unless) MathJax delivers.
          ForEach(texToRuns(normalizeTex(s.text)), (r: TexRun) => {
            Span(r.text)
              .fontFamily('serif')
              .fontStyle(r.italic ? FontStyle.Italic : FontStyle.Normal)
              .fontSize(r.level === 0 ? size : size * 0.7)
              .baselineOffset(LengthMetrics.vp(r.level < 0 ? -size * 0.22 : r.level > 0 ? size * 0.38 : 0))
          }, (r: TexRun, i: number) => `${i}-${r.level}-${r.text}`)
        }
      } else if (s.kind === SpanKind.Bold) {
        Span(s.text).fontWeight(FontWeight.Bold)
      } else if (s.kind === SpanKind.Italic) {
        Span(s.text).fontStyle(FontStyle.Italic)
      } else if (s.kind === SpanKind.BoldItalic) {
        Span(s.text).fontWeight(FontWeight.Bold).fontStyle(FontStyle.Italic)
      } else if (s.kind === SpanKind.Strike) {
        Span(s.text).decoration({ type: TextDecorationType.LineThrough })
      } else if (s.kind === SpanKind.File) {
        SymbolSpan(sym(fileIconFor(s.href))).fontSize(size - 1).fontColor([$r('app.color.accent')])
        Span(` ${s.text.length > 0 ? s.text : baseName(parseFileTarget(s.href).path)}`)
          .fontColor($r('app.color.accent'))
          .fontWeight(FontWeight.Medium)
          .onClick(() => LinkRouter.open(s.href, root))
      } else if (s.kind === SpanKind.Ref) {
        SymbolSpan(sym(s.href.startsWith('codeg://agent') ? 'person' : s.href.startsWith('codeg://session') ?
          'message' : 'link')).fontSize(size - 1).fontColor([$r('app.color.accent2')])
        Span(` ${s.text}`).fontColor($r('app.color.accent2')).fontWeight(FontWeight.Medium)
          .onClick(() => LinkRouter.open(s.href, root))
      } else if (s.kind === SpanKind.Link) {
        Span(s.text).fontColor($r('app.color.accent'))
          .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent_soft') })
          .onClick(() => LinkRouter.open(s.href, root))
      } else {
        Span(s.text)
      }
    }, (s: MdSpan, i: number) => spanKey(s, i, size))
  }
  .fontSize(size)
  .fontColor(color)
  .fontWeight(weight)
  .lineHeight(size * 1.55)
  .copyOption(CopyOptions.LocalDevice)
  .width('100%')
}

@ComponentV2
export struct CodeBlock {
  @Param code: string = ''
  @Param lang: string = ''
  @Param maxLines: number = 0
  @Local expanded: boolean = false

  build() {
    Column() {
      Row() {
        Text(this.lang.length > 0 ? this.lang : 'code').fontSize(11).fontColor($r('app.color.text3'))
          .fontFamily('monospace').layoutWeight(1)
        Row({ space: 4 }) {
          SymbolGlyph(sym('doc_filled_on_doc')).fontSize(13).fontColor([$r('app.color.text3')])
          Text(L('Copy', '复制')).fontSize(11).fontColor($r('app.color.text3'))
        }.onClick(() => copyText(this.code))
      }
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .width('100%')

      Scroll() {
        Text(this.code)
          .fontFamily('monospace')
          .fontSize(12.5)
          .lineHeight(19)
          .fontColor($r('app.color.code_text'))
          .copyOption(CopyOptions.LocalDevice)
          .maxLines(this.maxLines > 0 && !this.expanded ? this.maxLines : 100000)
          .padding({ left: 12, right: 12, bottom: 10 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')

      if (this.maxLines > 0 && this.code.split('\n').length > this.maxLines) {
        Text(this.expanded ? L('Show less', '收起') : L('Show all', '展开全部'))
          .fontSize(12).fontColor($r('app.color.accent')).padding({ left: 12, bottom: 8 })
          .onClick(() => {
            this.expanded = !this.expanded
          })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius(12)
    .border({ width: 0.5, color: $r('app.color.border') })
  }
}

@ComponentV2
export struct MarkdownView {
  @Param text: string = ''
  @Param fontSize: number = 15.5
  @Param color: ResourceColor = $r('app.color.text')
  @Param rootPath: string = ''

  @Computed
  get blocks(): MdBlock[] {
    return parseMarkdown(this.text)
  }

  build() {
    Column({ space: 10 }) {
      ForEach(this.blocks, (b: MdBlock) => {
        this.renderBlock(b)
      }, (b: MdBlock) => b.key)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  renderBlock(b: MdBlock) {
    if (b.kind === MdKind.Para) {
      InlineText(b.text, this.fontSize, this.color, FontWeight.Normal, this.rootPath)
    } else if (b.kind === MdKind.Heading) {
      InlineText(b.text, b.level <= 1 ? this.fontSize + 6 : b.level === 2 ? this.fontSize + 3.5 : this.fontSize + 1.5,
        this.color, FontWeight.Bold, this.rootPath)
    } else if (b.kind === MdKind.Code) {
      CodeBlock({ code: b.text, lang: b.lang, maxLines: 40 })
    } else if (b.kind === MdKind.Math) {
      MathBlock({ tex: b.text, fontSize: this.fontSize + 1 })
    } else if (b.kind === MdKind.Quote) {
      Row() {
        Column().width(3).height('100%').backgroundColor($r('app.color.accent')).borderRadius(2)
        Column() {
          MarkdownView({ text: b.text, fontSize: this.fontSize - 0.5, color: $r('app.color.text2'), rootPath: this.rootPath })
        }.padding({ left: 12 }).layoutWeight(1)
      }.width('100%')
    } else if (b.kind === MdKind.Rule) {
      Divider().strokeWidth(1).color($r('app.color.border')).margin({ top: 4, bottom: 4 })
    } else if (b.kind === MdKind.List) {
      Column({ space: 5 }) {
        ForEach(b.items, (it: MdListItem, idx: number) => {
          Row({ space: 8 }) {
            if (it.task >= 0) {
              SymbolGlyph(sym(it.task === 1 ? 'checkmark_square_fill' : 'square'))
                .fontSize(this.fontSize).fontColor([it.task === 1 ? $r('app.color.success') : $r('app.color.text3')])
                .margin({ top: 3 })
            } else {
              Text(it.ordered ? `${it.index}.` : (it.level % 2 === 0 ? '•' : '◦'))
                .fontSize(this.fontSize).fontColor($r('app.color.text3'))
                .constraintSize({ minWidth: it.ordered ? 20 : 10 })
                .lineHeight(this.fontSize * 1.55)
            }
            Column() {
              InlineText(it.text, this.fontSize, this.color, FontWeight.Normal, this.rootPath)
            }.layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .padding({ left: it.level * 18 })
          .width('100%')
        }, (it: MdListItem, idx: number) => `${idx}-${it.text}`)
      }.width('100%')
    } else if (b.kind === MdKind.Table) {
      Scroll() {
        Column() {
          ForEach(b.rows, (row: string[], ri: number) => {
            Row() {
              ForEach(row, (cell: string, ci: number) => {
                Column() {
                  InlineText(cell, this.fontSize - 1.5, this.color, ri === 0 ? FontWeight.Bold : FontWeight.Normal,
                    this.rootPath)
                }
                .width(Math.max(110, Math.min(260, 560 / Math.max(1, row.length))))
                .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                .alignItems(b.align[ci] === 'end' ? HorizontalAlign.End :
                  b.align[ci] === 'center' ? HorizontalAlign.Center : HorizontalAlign.Start)
              }, (cell: string, ci: number) => `${ci}-${cell}`)
            }
            .backgroundColor(ri === 0 ? $r('app.color.surface2') : ri % 2 === 0 ? $r('app.color.surface') : Color.Transparent)
          }, (row: string[], ri: number) => `${ri}-${row.join('|')}`)
        }
        .border({ width: 0.5, color: $r('app.color.border') })
        .borderRadius(10)
        .clip(true)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
    }
  }
}

/** Display formula: rendered image when ready, TeX source until then or on error. */
@ComponentV2
export struct MathBlock {
  @Param tex: string = ''
  @Param fontSize: number = 16

  image(): MathImage | undefined {
    const v = math.version
    const m = v >= 0 ? math.get(normalizeTex(this.tex), true, layout.inkColor, this.fontSize) : undefined
    return m !== undefined && !m.failed ? m : undefined
  }

  build() {
    Scroll() {
      if (this.image() !== undefined) {
        Image(this.image()?.png ?? '')
          .width(this.image()?.w ?? 0)
          .height(this.image()?.h ?? 0)
          .objectFit(ImageFit.Fill)
          .draggable(false)
          .margin({ top: 6, bottom: 6 })
      } else {
        Text() {
          ForEach(texToRuns(normalizeTex(this.tex)), (r: TexRun) => {
            Span(r.text)
              .fontFamily('serif')
              .fontStyle(r.italic ? FontStyle.Italic : FontStyle.Normal)
              .fontSize(r.level === 0 ? this.fontSize : this.fontSize * 0.7)
              .baselineOffset(LengthMetrics.vp(r.level < 0 ? -this.fontSize * 0.22 :
                r.level > 0 ? this.fontSize * 0.38 : 0))
          }, (r: TexRun, i: number) => `${i}-${r.level}-${r.text}`)
        }
        .fontColor($r('app.color.text'))
        .copyOption(CopyOptions.LocalDevice)
        .padding({ top: 10, bottom: 10, left: 4, right: 4 })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Center)
    .bindContextMenu(this.menu(), ResponseType.LongPress)
  }

  @Builder
  menu() {
    Menu() {
      MenuItem({ content: L('Copy TeX', '复制 TeX') }).onClick(() => copyText(this.tex))
    }
  }
}
