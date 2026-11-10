import { promptAction } from '@kit.ArkUI'
import { agentColor, agentGlyph, agentIcon, agentIconIsTemplate, agentName, statusColor, statusLabel } from '../common/Agents'

export function toast(msg: string): void {
  try {
    promptAction.showToast({ message: msg, duration: 2200 })
  } catch (e) {
    // UI context not ready.
  }
}

export function sym(name: string): Resource {
  return $r(`sys.symbol.${name}`)
}

@ComponentV2
export struct Icon {
  @Param name: string = 'doc'
  @Param sz: number = 20
  @Param color: ResourceColor = $r('app.color.text2')

  build() {
    SymbolGlyph(sym(this.name))
      .fontSize(this.sz)
      .fontColor([this.color])
  }
}

@ComponentV2
export struct IconButton {
  @Param icon: string = 'plus'
  @Param sz: number = 20
  @Param color: ResourceColor = $r('app.color.text2')
  @Param bg: ResourceColor = Color.Transparent
  @Param box: number = 40
  @Param enabledBtn: boolean = true
  @Event onTap: () => void = () => {
  }

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(sym(this.icon)).fontSize(this.sz).fontColor([this.color])
    }
    .width(this.box)
    .height(this.box)
    .backgroundColor(this.bg)
    .enabled(this.enabledBtn)
    .opacity(this.enabledBtn ? 1 : 0.4)
    .onClick(() => this.onTap())
  }
}

@ComponentV2
export struct AgentAvatar {
  @Param agent: string = ''
  @Param sz: number = 32

  build() {
    if (agentIcon(this.agent) !== null) {
      Stack() {
        if (agentIconIsTemplate(this.agent)) {
          Image(agentIcon(this.agent)).width(this.sz * 0.62).height(this.sz * 0.62)
            .objectFit(ImageFit.Contain).fillColor($r('app.color.text')).draggable(false)
        } else {
          Image(agentIcon(this.agent)).width(this.sz * 0.66).height(this.sz * 0.66)
            .objectFit(ImageFit.Contain).draggable(false)
        }
      }
      .width(this.sz)
      .height(this.sz)
      .borderRadius(this.sz * 0.3)
      .backgroundColor($r('app.color.surface2'))
      .border({ width: 0.5, color: $r('app.color.border') })
    } else {
      Text(agentGlyph(this.agent))
        .width(this.sz)
        .height(this.sz)
        .borderRadius(this.sz * 0.3)
        .backgroundColor(agentColor(this.agent))
        .fontColor(Color.White)
        .fontSize(this.sz * 0.45)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
    }
  }
}

@ComponentV2
export struct AgentChip {
  @Param agent: string = ''

  build() {
    Row({ space: 6 }) {
      AgentAvatar({ agent: this.agent, sz: 18 })
      Text(agentName(this.agent)).fontSize(13).fontColor($r('app.color.text2')).maxLines(1)
    }
  }
}

@ComponentV2
export struct StatusPill {
  @Param status: string = ''

  build() {
    Row({ space: 4 }) {
      Circle().width(6).height(6).fill(statusColor(this.status))
      Text(statusLabel(this.status)).fontSize(11).fontColor(statusColor(this.status))
    }
    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
    .borderRadius(10)
    .backgroundColor($r('app.color.surface2'))
  }
}

@ComponentV2
export struct EmptyState {
  @Param icon: string = 'doc'
  @Param title: string = ''
  @Param message: string = ''
  @Param action: string = ''
  @Event onAction: () => void = () => {
  }

  build() {
    Column({ space: 12 }) {
      SymbolGlyph(sym(this.icon)).fontSize(44).fontColor([$r('app.color.text3')])
      Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)
      if (this.message.length > 0) {
        Text(this.message).fontSize(14).fontColor($r('app.color.text3')).textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 360 })
      }
      if (this.action.length > 0) {
        Button(this.action).type(ButtonType.Capsule).backgroundColor($r('app.color.accent'))
          .fontSize(15).height(40).padding({ left: 20, right: 20 })
          .onClick(() => this.onAction())
      }
    }
    .padding(32)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
export struct SectionHeader {
  @Param title: string = ''
  @Param trailing: string = ''
  @Event onTrailing: () => void = () => {
  }

  build() {
    Row() {
      Text(this.title.toUpperCase()).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text3')).letterSpacing(0.6).layoutWeight(1)
      if (this.trailing.length > 0) {
        Text(this.trailing).fontSize(13).fontColor($r('app.color.accent')).onClick(() => this.onTrailing())
      }
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 6 })
    .width('100%')
  }
}

/** A tappable settings-style row. */
@ComponentV2
export struct NavRow {
  @Param icon: string = ''
  @Param iconColor: ResourceColor = $r('app.color.accent')
  @Param title: string = ''
  @Param subtitle: string = ''
  @Param value: string = ''
  @Param chevron: boolean = true
  @Param danger: boolean = false
  @Event onTap: () => void = () => {
  }

  build() {
    Row({ space: 12 }) {
      if (this.icon.length > 0) {
        Row() {
          SymbolGlyph(sym(this.icon)).fontSize(17).fontColor([Color.White])
        }
        .width(30).height(30).borderRadius(8).justifyContent(FlexAlign.Center)
        .backgroundColor(this.danger ? $r('app.color.danger') : this.iconColor)
      }
      Column({ space: 2 }) {
        Text(this.title).fontSize(16).fontColor(this.danger ? $r('app.color.danger') : $r('app.color.text'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(12).fontColor($r('app.color.text3')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.value.length > 0) {
        Text(this.value).fontSize(14).fontColor($r('app.color.text3')).maxLines(1)
          .constraintSize({ maxWidth: 160 }).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.chevron) {
        SymbolGlyph(sym('chevron_right')).fontSize(14).fontColor([$r('app.color.text3')])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 14, top: 11, bottom: 11 })
    .onClick(() => this.onTap())
  }
}

@ComponentV2
export struct Card {
  @BuilderParam content: () => void = noop

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .clip(true)
  }
}

@Builder
function noop() {
}

@ComponentV2
export struct Divider1 {
  @Param inset: number = 16

  build() {
    Divider().strokeWidth(0.5).color($r('app.color.border')).margin({ left: this.inset })
  }
}

/** Page header for NavDestination-less panes. */
@ComponentV2
export struct PaneTitle {
  @Param title: string = ''
  @Param subtitle: string = ''
  @BuilderParam actions: () => void = noop

  build() {
    Row({ space: 4 }) {
      Column({ space: 2 }) {
        Text(this.title).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(13).fontColor($r('app.color.text3')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.actions()
    }
    .width('100%')
    .padding({ left: 20, right: 12, top: 12, bottom: 8 })
  }
}

@ComponentV2
export struct Loading {
  @Param label: string = ''

  build() {
    Column({ space: 10 }) {
      LoadingProgress().width(32).height(32).color($r('app.color.accent'))
      if (this.label.length > 0) {
        Text(this.label).fontSize(13).fontColor($r('app.color.text3'))
      }
    }
    .width('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
export struct Banner {
  @Param text: string = ''
  @Param kind: string = 'error'
  @Event onClose: () => void = () => {
  }

  build() {
    Row({ space: 8 }) {
      SymbolGlyph(sym(this.kind === 'error' ? 'exclamationmark_triangle' : 'info_circle'))
        .fontSize(16)
        .fontColor([this.kind === 'error' ? $r('app.color.danger') : $r('app.color.warning')])
      Text(this.text).fontSize(13).fontColor($r('app.color.text')).layoutWeight(1).maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).copyOption(CopyOptions.LocalDevice)
      SymbolGlyph(sym('xmark')).fontSize(14).fontColor([$r('app.color.text3')]).onClick(() => this.onClose())
    }
    .padding(12)
    .margin({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(12)
    .backgroundColor(this.kind === 'error' ? $r('app.color.danger_soft') : $r('app.color.warning_soft'))
  }
}
