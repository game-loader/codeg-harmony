import { SessionController } from '../session/SessionController'
import { AgentOptionsModel } from '../session/AgentOptionsModel'
import { ConfigChoice, ConfigOption } from '../session/Interactive'
import { L } from '../common/I18n'
import { agentName } from '../common/Agents'
import { sym } from './Common'

/**
 * An agent's options, one block per option with its choices as chips. Tapping
 * a chip reports the pick; the owner applies it.
 */
@ComponentV2
export struct OptionRows {
  @Param opts: AgentOptionsModel = new AgentOptionsModel()
  /** Which rows to list: all | primary (model and mode) | more (the rest). */
  @Param part: string = 'all'
  @Event onPick: (key: string, value: string) => void = (k: string, v: string) => {
  }

  shown(): ConfigOption[] {
    const o = this.opts.options
    if (o === null) {
      return []
    }
    return this.part === 'primary' ? o.primaryRows : this.part === 'more' ? o.moreRows : o.rows
  }

  @Builder
  chips(row: ConfigOption, list: ConfigChoice[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(list, (ch: ConfigChoice) => {
        Text(ch.name).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '100%' })
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ right: 8, bottom: 8 }).borderRadius(18)
          .fontColor(row.current === ch.value ? Color.White : $r('app.color.text'))
          .backgroundColor(row.current === ch.value ? $r('app.color.accent') : $r('app.color.surface2'))
          .onClick(() => {
            this.onPick(row.id, ch.value)
          })
      }, (ch: ConfigChoice) => `${ch.group}/${ch.value}`)
    }
  }

  build() {
    Column({ space: 10 }) {
      // The key carries the model's revision: rows are plain values, so they
      // are redrawn whenever the selection, the lists or the busy state change.
      ForEach(this.shown(), (row: ConfigOption) => {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(row.name).fontSize(12).fontColor($r('app.color.text3'))
            if (this.opts.applying === row.id) {
              LoadingProgress().width(14).height(14).color($r('app.color.accent'))
            }
          }
          if (row.groupNames.length > 0) {
            ForEach(row.groupNames, (g: string) => {
              Column({ space: 6 }) {
                Text(g).fontSize(11).fontColor($r('app.color.text3')).margin({ top: 2 })
                this.chips(row, row.inGroup(g))
              }.alignItems(HorizontalAlign.Start).width('100%')
            }, (g: string) => g)
          } else {
            this.chips(row, row.choices)
          }
          if (row.currentDescription.length > 0) {
            Text(row.currentDescription).fontSize(12).fontColor($r('app.color.text3')).margin({ top: -4 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .opacity(this.opts.locked ? 0.6 : 1)
      }, (row: ConfigOption) => `${row.id}#${this.opts.rev}`)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

/** Sheet content for an open session: its mode, model and other agent options. */
@ComponentV2
export struct AgentOptionsPanel {
  @Param ctrl: SessionController | null = null

  @Builder
  status(text: string) {
    Row({ space: 10 }) {
      LoadingProgress().width(20).height(20).color($r('app.color.accent'))
      Text(text).fontSize(13).fontColor($r('app.color.text2')).layoutWeight(1)
    }.width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text(L('Session options', '会话选项')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        if (this.ctrl !== null) {
          if (this.ctrl.opts.phase === 'loading') {
            this.status(L(`Reading the options ${agentName(this.ctrl.agentType)} offers…`,
              `正在读取 ${agentName(this.ctrl.agentType)} 提供的选项…`))
          } else if (this.ctrl.opts.phase === 'connecting') {
            this.status(L('Starting the agent to read this session\'s settings…', '正在启动智能体以读取本会话的设置…'))
          } else if (this.ctrl.opts.phase === 'error') {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                SymbolGlyph(sym('exclamationmark_triangle')).fontSize(15).fontColor([$r('app.color.danger')])
                Text(this.ctrl.opts.error).fontSize(13).fontColor($r('app.color.danger')).layoutWeight(1)
                  .copyOption(CopyOptions.LocalDevice)
              }.width('100%')
              Button(L('Try again', '重试')).type(ButtonType.Capsule).height(34).fontSize(13)
                .backgroundColor($r('app.color.accent'))
                .onClick(() => {
                  this.ctrl?.loadOptions(true)
                })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.danger_soft'))
          }

          if (this.ctrl.opts.options !== null && this.ctrl.opts.phase !== 'error') {
            if (this.ctrl.opts.error.length > 0) {
              Text(this.ctrl.opts.error).fontSize(13).fontColor($r('app.color.danger'))
                .copyOption(CopyOptions.LocalDevice)
            }
            if (this.ctrl.opts.options.rows.length > 0) {
              OptionRows({
                opts: this.ctrl.opts, onPick: (k: string, v: string) => {
                  this.ctrl?.pickOption(k, v)
                }
              })
              Text(L(`Your choices also become the starting point for new ${agentName(this.ctrl.agentType)} sessions on this device.`,
                `你的选择也会成为本设备上新建 ${agentName(this.ctrl.agentType)} 会话的初始设置。`))
                .fontSize(11).fontColor($r('app.color.text3'))
            } else if (this.ctrl.opts.phase === 'ready') {
              Text(L('This agent has no selectable options', '该智能体没有可选项')).fontSize(14)
                .fontColor($r('app.color.text3'))
            }
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .backgroundColor($r('app.color.surface'))
  }
}
