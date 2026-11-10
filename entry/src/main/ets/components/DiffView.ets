import { DiffLine, FileDiff } from '../session/Diff'
import { sym } from './Common'
import { L } from '../common/I18n'

@ComponentV2
export struct DiffView {
  @Param diff: FileDiff = new FileDiff()
  @Param maxLines: number = 60
  @Param showHeader: boolean = true
  @Local expanded: boolean = false

  get shown(): DiffLine[] {
    if (this.expanded || this.diff.lines.length <= this.maxLines) {
      return this.diff.lines
    }
    return this.diff.lines.slice(0, this.maxLines)
  }

  build() {
    Column() {
      if (this.showHeader) {
        Row({ space: 6 }) {
          SymbolGlyph(sym('doc_text')).fontSize(13).fontColor([$r('app.color.text3')])
          Text(this.diff.path.length > 0 ? this.diff.path : L('changes', '改动')).fontSize(12)
            .fontFamily('monospace').fontColor($r('app.color.text2')).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
          Text(`+${this.diff.additions}`).fontSize(12).fontColor($r('app.color.success')).fontFamily('monospace')
          Text(`-${this.diff.deletions}`).fontSize(12).fontColor($r('app.color.danger')).fontFamily('monospace')
        }
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .width('100%')
        .backgroundColor($r('app.color.surface2'))
      }
      Scroll() {
        Column() {
          ForEach(this.shown, (l: DiffLine, i: number) => {
            Row() {
              Text(l.kind === '@' ? '' : l.kind === '+' ? `${l.newNo}` : `${l.oldNo > 0 ? l.oldNo : ''}`)
                .fontSize(10.5).fontFamily('monospace').fontColor($r('app.color.text3'))
                .width(34).textAlign(TextAlign.End).padding({ right: 6 })
              Text(l.kind === '@' ? l.text : `${l.kind === ' ' ? ' ' : l.kind} ${l.text}`)
                .fontSize(12).fontFamily('monospace').lineHeight(18)
                .fontColor(l.kind === '+' ? $r('app.color.diff_add_text') : l.kind === '-' ?
                $r('app.color.diff_del_text') : l.kind === '@' ? $r('app.color.accent') : $r('app.color.code_text'))
                .padding({ right: 12 })
            }
            .constraintSize({ minWidth: '100%' })
            .backgroundColor(l.kind === '+' ? $r('app.color.diff_add') : l.kind === '-' ? $r('app.color.diff_del') :
              Color.Transparent)
          }, (l: DiffLine, i: number) => `${i}`)
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 4, bottom: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')

      if (this.diff.lines.length > this.maxLines) {
        Text(this.expanded ? L('Collapse', '收起') :
          L(`Show ${this.diff.lines.length - this.maxLines} more lines`, `再显示 ${this.diff.lines.length - this.maxLines} 行`))
          .fontSize(12).fontColor($r('app.color.accent')).padding(8)
          .onClick(() => {
            this.expanded = !this.expanded
          })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius(10)
    .border({ width: 0.5, color: $r('app.color.border') })
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }
}
