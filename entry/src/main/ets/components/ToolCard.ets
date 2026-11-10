import { ToolCall, PlanEntry } from '../session/Transcript'
import { FileDiff } from '../session/Diff'
import { DiffView } from './DiffView'
import { CodeBlock, MarkdownView } from './Markdown'
import { sym } from './Common'
import { L } from '../common/I18n'
import { obj, str } from '../common/Json'
import { agentName } from '../common/Agents'

function iconFor(cat: string): string {
  switch (cat) {
    case 'edit':
      return 'square_and_pencil'
    case 'read':
      return 'doc_text'
    case 'search':
      return 'magnifyingglass'
    case 'execute':
      return 'keyboard'
    case 'web':
      return 'wifi'
    case 'todo':
      return 'list_bullet'
    case 'agent':
      return 'person_2'
    case 'plan':
      return 'lightbulb'
    default:
      return 'wrench_and_screwdriver'
  }
}

function verb(cat: string): string {
  switch (cat) {
    case 'edit':
      return L('Edit', '编辑')
    case 'read':
      return L('Read', '读取')
    case 'search':
      return L('Search', '搜索')
    case 'execute':
      return L('Run', '运行')
    case 'web':
      return L('Web', '网页')
    case 'todo':
      return L('Tasks', '任务')
    case 'agent':
      return L('Sub-agent', '子智能体')
    case 'plan':
      return L('Plan', '计划')
    default:
      return L('Tool', '工具')
  }
}

@Builder
export function PlanList(entries: PlanEntry[]) {
  Column({ space: 6 }) {
    ForEach(entries, (p: PlanEntry, i: number) => {
      Row({ space: 8 }) {
        SymbolGlyph(sym(p.status === 'completed' ? 'checkmark_circle_fill' : p.status === 'in_progress' ?
          'clock' : 'circle'))
          .fontSize(15)
          .fontColor([p.status === 'completed' ? $r('app.color.success') : p.status === 'in_progress' ?
          $r('app.color.accent') : $r('app.color.text3')])
        Text(p.content).fontSize(14).layoutWeight(1)
          .fontColor(p.status === 'completed' ? $r('app.color.text3') : $r('app.color.text'))
          .decoration({ type: p.status === 'completed' ? TextDecorationType.LineThrough : TextDecorationType.None })
      }.alignItems(VerticalAlign.Top).width('100%')
    }, (p: PlanEntry, i: number) => `${i}-${p.status}-${p.content}`)
  }.width('100%')
}

@ComponentV2
export struct ToolCard {
  @Param tool: ToolCall = new ToolCall()
  @Param rootPath: string = ''
  @Local open: boolean = false

  build() {
    Column() {
      Row({ space: 10 }) {
        Row() {
          SymbolGlyph(sym(iconFor(this.tool.category))).fontSize(15).fontColor([$r('app.color.accent')])
        }
        .width(28).height(28).borderRadius(8).justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.accent_soft'))

        Column({ space: 1 }) {
          Text(this.title()).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.tool.detail.length > 0) {
            Text(this.tool.detail).fontSize(12).fontFamily('monospace').fontColor($r('app.color.text3'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.tool.status === 'in_progress' || this.tool.status === 'pending') {
          LoadingProgress().width(18).height(18).color($r('app.color.accent'))
        } else if (this.tool.status === 'failed' || this.tool.isError) {
          SymbolGlyph(sym('xmark_circle_fill')).fontSize(16).fontColor([$r('app.color.danger')])
        } else {
          SymbolGlyph(sym('checkmark_circle_fill')).fontSize(16).fontColor([$r('app.color.success')])
        }
        SymbolGlyph(sym(this.open ? 'chevron_up' : 'chevron_down')).fontSize(13).fontColor([$r('app.color.text3')])
      }
      .width('100%')
      .padding({ left: 10, right: 12, top: 9, bottom: 9 })
      .onClick(() => {
        this.open = !this.open
      })

      if (this.tool.category === 'todo' && this.tool.todos.length > 0) {
        Column() {
          PlanList(this.tool.todos)
        }.padding({ left: 14, right: 14, bottom: 12 })
      } else if (this.tool.category === 'edit' && !this.open) {
        ForEach(this.tool.diffs.slice(0, 2), (d: FileDiff, i: number) => {
          Column() {
            DiffView({ diff: d, maxLines: 14 })
          }.padding({ left: 10, right: 10, bottom: 10 })
        }, (d: FileDiff, i: number) => `${i}-${d.path}-${d.lines.length}`)
      }

      if (this.tool.subText.length > 0 && !this.open) {
        Text(this.tool.subText.length > 400 ? '…' + this.tool.subText.substring(this.tool.subText.length - 400) :
        this.tool.subText)
          .fontSize(12).fontColor($r('app.color.text3')).maxLines(5)
          .padding({ left: 14, right: 14, bottom: 10 })
      }

      if (this.open) {
        Column({ space: 8 }) {
          if (this.tool.category === 'edit') {
            ForEach(this.tool.diffs, (d: FileDiff, i: number) => {
              DiffView({ diff: d, maxLines: 200 })
            }, (d: FileDiff, i: number) => `${i}-${d.path}`)
          }
          if (this.tool.input.length > 0 && this.tool.category !== 'edit') {
            Text(L('Input', '输入')).fontSize(11).fontColor($r('app.color.text3'))
            CodeBlock({ code: this.tool.input, lang: 'json', maxLines: 30 })
          }
          if (this.tool.content.length > 0 && this.tool.category !== 'edit') {
            CodeBlock({ code: this.tool.content, lang: '', maxLines: 30 })
          }
          if (this.tool.subText.length > 0) {
            MarkdownView({ text: this.tool.subText, fontSize: 13.5, rootPath: this.rootPath })
          }
          if (this.tool.output.length > 0) {
            Text(L('Output', '输出')).fontSize(11).fontColor($r('app.color.text3'))
            CodeBlock({ code: this.tool.output, lang: '', maxLines: 40 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 10, right: 10, bottom: 10 })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 0.5, color: $r('app.color.border') })
    .clip(true)
  }

  title(): string {
    const cat = this.tool.category
    if (cat === 'agent') {
      const d = obj(this.tool.meta, 'codeg.delegation')
      const a = str(d, 'agent_type', str(d, 'agentType'))
      if (a.length > 0) {
        return `${verb(cat)} · ${agentName(a)}`
      }
    }
    const n = this.tool.name
    if (n.length > 0 && n.length < 60) {
      return n
    }
    return verb(cat)
  }
}
