import { PermissionOption, PermissionRequest, PlanApproval, Question, QuestionOption, QuestionRequest } from '../session/Interactive'
import { FileDiff } from '../session/Diff'
import { DiffView } from './DiffView'
import { MarkdownView } from './Markdown'
import { sym } from './Common'
import { L } from '../common/I18n'

@ComponentV2
export struct PermissionCard {
  @Param req: PermissionRequest = new PermissionRequest()
  @Event onChoose: (optionId: string) => void = (id: string) => {
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph(sym('ohos_lock')).fontSize(18).fontColor([$r('app.color.warning')])
        Text(L('Permission needed', '需要授权')).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text')).layoutWeight(1)
        if (this.req.queued > 0) {
          Text(L(`+${this.req.queued} waiting`, `还有 ${this.req.queued} 个`)).fontSize(12).fontColor($r('app.color.text3'))
        }
      }.width('100%')

      Text(this.req.title).fontSize(14).fontColor($r('app.color.text')).maxLines(4)
      if (this.req.command.length > 0) {
        Text(this.req.command).fontSize(12.5).fontFamily('monospace').fontColor($r('app.color.code_text'))
          .padding(10).width('100%').borderRadius(8).backgroundColor($r('app.color.code_bg')).maxLines(8)
      }
      if (this.req.planMarkdown.length > 0) {
        Scroll() {
          MarkdownView({ text: this.req.planMarkdown, fontSize: 14 })
        }.constraintSize({ maxHeight: 280 }).width('100%')
      }
      ForEach(this.req.diffs.slice(0, 3), (d: FileDiff, i: number) => {
        DiffView({ diff: d, maxLines: 16 })
      }, (d: FileDiff, i: number) => `${i}-${d.path}`)

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.req.options, (o: PermissionOption) => {
          Button(o.name)
            .type(ButtonType.Capsule)
            .fontSize(14)
            .height(38)
            .margin({ right: 8, top: 6 })
            .padding({ left: 16, right: 16 })
            .fontColor(o.isReject ? $r('app.color.danger') : (o.kind === 'allow_once' ? Color.White : $r('app.color.accent')))
            .backgroundColor(o.isReject ? $r('app.color.danger_soft') : (o.kind === 'allow_once' ?
            $r('app.color.accent') : $r('app.color.accent_soft')))
            .onClick(() => this.onChoose(o.id))
        }, (o: PermissionOption) => o.id)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1.5, color: $r('app.color.warning') })
    .shadow({ radius: 16, color: '#22000000', offsetY: 4 })
  }
}

@ComponentV2
export struct QuestionCard {
  @Param req: QuestionRequest = new QuestionRequest()
  @Local picks: Map<string, string[]> = new Map()
  @Local custom: Map<string, string> = new Map()
  @Local tick: number = 0
  @Event onAnswer: (answers: Map<string, string[]>, declined: boolean) => void =
    (a: Map<string, string[]>, d: boolean) => {
    }

  isPicked(q: Question, label: string): boolean {
    const t = this.tick
    return (this.picks.get(q.id) ?? []).includes(label) && t >= 0
  }

  toggle(q: Question, label: string): void {
    const cur = this.picks.get(q.id) ?? []
    if (q.multiSelect) {
      this.picks.set(q.id, cur.includes(label) ? cur.filter((x: string) => x !== label) : cur.concat([label]))
    } else {
      this.picks.set(q.id, [label])
    }
    this.tick++
  }

  submit(): void {
    const out: Map<string, string[]> = new Map()
    for (const q of this.req.questions) {
      const labels = (this.picks.get(q.id) ?? []).slice()
      const c = (this.custom.get(q.id) ?? '').trim()
      if (c.length > 0) {
        labels.push(c)
      }
      out.set(q.id, labels)
    }
    this.onAnswer(out, false)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph(sym('info_circle')).fontSize(18).fontColor([$r('app.color.accent')])
        Text(L('The agent has a question', '智能体提问')).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
      }

      ForEach(this.req.questions, (q: Question) => {
        Column({ space: 8 }) {
          if (q.header.length > 0) {
            Text(q.header).fontSize(11).fontColor($r('app.color.accent')).fontWeight(FontWeight.Medium)
          }
          Text(q.question).fontSize(14).fontColor($r('app.color.text'))
          ForEach(q.options, (o: QuestionOption) => {
            Row({ space: 10 }) {
              SymbolGlyph(sym(this.isPicked(q, o.label) ? (q.multiSelect ? 'checkmark_square_fill' :
                'checkmark_circle_fill') : (q.multiSelect ? 'square' : 'circle')))
                .fontSize(18).fontColor([this.isPicked(q, o.label) ? $r('app.color.accent') : $r('app.color.text3')])
              Column({ space: 2 }) {
                Text(o.label).fontSize(14).fontColor($r('app.color.text'))
                if (o.description.length > 0) {
                  Text(o.description).fontSize(12).fontColor($r('app.color.text3'))
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }
            .padding(10)
            .width('100%')
            .borderRadius(10)
            .backgroundColor(this.isPicked(q, o.label) ? $r('app.color.accent_soft') : $r('app.color.surface2'))
            .onClick(() => this.toggle(q, o.label))
          }, (o: QuestionOption) => o.label)
          TextInput({ placeholder: L('Other answer…', '其他回答…') })
            .type(q.isSecret ? InputType.Password : InputType.Normal)
            .fontSize(14).height(40).backgroundColor($r('app.color.surface2'))
            .onChange((v: string) => {
              this.custom.set(q.id, v)
            })
        }.alignItems(HorizontalAlign.Start).width('100%')
      }, (q: Question) => q.id)

      Row({ space: 10 }) {
        Button(L('Dismiss', '忽略')).type(ButtonType.Capsule).fontSize(14).height(38)
          .fontColor($r('app.color.text2')).backgroundColor($r('app.color.surface2'))
          .onClick(() => this.onAnswer(new Map(), true))
        Blank()
        Button(L('Submit', '提交')).type(ButtonType.Capsule).fontSize(14).height(38)
          .backgroundColor($r('app.color.accent')).padding({ left: 22, right: 22 })
          .onClick(() => this.submit())
      }.width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1.5, color: $r('app.color.accent') })
    .shadow({ radius: 16, color: '#22000000', offsetY: 4 })
  }
}

@ComponentV2
export struct PlanApprovalCard {
  @Param req: PlanApproval = new PlanApproval()
  @Local feedback: string = ''
  @Event onDecide: (decision: string, feedback: string) => void = (d: string, f: string) => {
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph(sym('lightbulb')).fontSize(18).fontColor([$r('app.color.accent')])
        Text(L('Review the plan', '审阅计划')).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      }
      Scroll() {
        MarkdownView({ text: this.req.markdown, fontSize: 14 })
      }.constraintSize({ maxHeight: 320 }).width('100%')
      TextInput({ placeholder: L('Feedback (optional)', '反馈（可选）') }).fontSize(14).height(40)
        .backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.feedback = v
        })
      Row({ space: 8 }) {
        Button(L('Abandon', '放弃')).type(ButtonType.Capsule).fontSize(13).height(36)
          .fontColor($r('app.color.danger')).backgroundColor($r('app.color.danger_soft'))
          .onClick(() => this.onDecide('abandon', this.feedback))
        Button(L('Request changes', '要求修改')).type(ButtonType.Capsule).fontSize(13).height(36)
          .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
          .onClick(() => this.onDecide('request_changes', this.feedback))
        Blank()
        Button(L('Approve', '批准')).type(ButtonType.Capsule).fontSize(13).height(36)
          .backgroundColor($r('app.color.accent'))
          .onClick(() => this.onDecide('approve', this.feedback))
      }.width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1.5, color: $r('app.color.accent') })
  }
}
