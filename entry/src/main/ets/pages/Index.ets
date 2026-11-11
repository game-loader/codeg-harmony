import { common } from '@kit.AbilityKit'
import { app } from '../store/AppState'
import { layout } from '../store/Layout'
import { ConversationSummary, FolderDetail } from '../model/Models'
import { SessionController } from '../session/SessionController'
import { LinkRouter } from '../components/Links'
import { isFileHref, isFilePathText, parseFileTarget, resolveFile } from '../session/FileRefs'
import { EmptyState, sym, toast } from '../components/Common'
import { L } from '../common/I18n'
import { AppPrefs as Prefs } from '../store/ServerStore'
import { SessionView } from '../views/SessionView'
import { SessionsList } from '../views/SessionsList'
import { Onboarding } from '../views/ServersView'
import { ProjectsList } from '../views/ProjectsView'
import { ProjectDetail } from '../views/ProjectDetail'
import { FilePreview } from '../views/FilesView'
import { MachinesView } from '../views/MachinesView'
import { AcademicView } from '../views/AcademicView'
import { SettingsView } from '../views/SettingsView'
import { NewSessionSheet } from '../views/NewSessionSheet'
import { MathHost } from '../components/MathRenderer'

class Section {
  id: string
  icon: string
  label: string

  constructor(id: string, icon: string, label: string) {
    this.id = id
    this.icon = icon
    this.label = label
  }
}

/**
 * Adaptive shell.
 * sm (phone / cover screen): bottom bar + stacked pages.
 * md (unfolded foldable): side rail + list + detail; the open session survives folding/unfolding.
 * lg (tablet / 2in1): same, with a wider list column.
 */
@Entry
@ComponentV2
struct Index {
  @Local section: string = 'sessions'
  @Local session: SessionController | null = null
  @Local project: FolderDetail | null = null
  @Local previewRoot: string = ''
  @Local previewPath: string = ''
  @Local previewLine: number = 0
  @Local showNew: boolean = false
  @Local newFolder: number = -1
  @Local newPaper: string = ''
  @Local langFlip: boolean = false
  @Local sessionFromProject: boolean = false
  @Local lastCrash: string = ''

  sections(): Section[] {
    return [
      new Section('sessions', 'message', L('Sessions', '会话')),
      new Section('projects', 'folder', L('Projects', '项目')),
      new Section('machines', 'computer', L('Machines', '机器')),
      new Section('academic', 'graduationcap', L('Academic', '学术')),
      new Section('settings', 'gearshape', L('Settings', '设置'))
    ]
  }

  aboutToAppear(): void {
    this.lastCrash = Prefs.get('last_crash')
    this.applyTheme()
    LinkRouter.handler = (href: string, root: string) => this.openLink(href, root)
  }

  ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  applyTheme(): void {
    app.applyTheme()
  }

  openLink(href: string, root: string): void {
    if (href.startsWith('codeg://session/')) {
      const id = Number(href.substring('codeg://session/'.length).split(/[/?#]/)[0])
      if (id > 0) {
        this.openConversationId(id)
      }
      return
    }
    if (href.startsWith('codeg://')) {
      return
    }
    if (isFileHref(href) || isFilePathText(href)) {
      this.openFile(href, root)
      return
    }
    // A web address written without its scheme (`www.example.com`).
    const url = new RegExp('^[A-Za-z][A-Za-z\\d+.-]*:').test(href) ? href : `https://${href}`
    this.ctx().openLink(url).catch(() => {
      toast(L('Cannot open link', '无法打开链接'))
    })
  }

  /** Opens a file an agent referred to: `/abs/a.md`, `src/a.ts:12` (from the session folder), `~/out/demo.mp4`. */
  async openFile(ref: string, root: string): Promise<void> {
    const target = parseFileTarget(ref)
    const home = target.path.startsWith('~/') ? await app.homeDir() : ''
    const file = resolveFile(target, root, home)
    if (file === null) {
      toast(target.path.startsWith('~/') ? L('Could not read the server\'s home directory', '无法读取服务器的主目录') :
      L('This path is relative, and this session has no folder to resolve it from', '这是相对路径，而当前会话没有可用来定位它的目录'))
      return
    }
    this.previewRoot = file.root
    this.previewLine = file.line
    this.previewPath = file.abs
  }

  disposeSession(): void {
    this.session?.dispose()
    this.session = null
  }

  openConversation(c: ConversationSummary, fromProject: boolean = false): void {
    this.openConversationId(c.id, fromProject)
  }

  openConversationId(id: number, fromProject: boolean = false): void {
    if (app.api === null) {
      return
    }
    if (this.session !== null && this.session.conversationId === id) {
      return
    }
    this.disposeSession()
    const conv = app.conversationById(id)
    const folder = conv !== undefined ? app.folderById(conv.folderId) : null
    const s = new SessionController(app.api)
    s.onListChanged = () => {
      app.refresh(true)
    }
    s.onSeen = (cid: number) => {
      app.markSeen(cid)
    }
    if (conv !== undefined) {
      s.agentType = conv.agentType
      s.title = conv.displayTitle
    }
    this.session = s
    this.sessionFromProject = fromProject
    s.open(id, folder)
  }

  startNew(agentType: string, folder: FolderDetail | null): void {
    if (app.api === null) {
      return
    }
    this.showNew = false
    this.disposeSession()
    Prefs.set('last_agent', agentType)
    const s = new SessionController(app.api)
    s.onListChanged = () => {
      app.refresh(true)
    }
    s.onSeen = (cid: number) => {
      app.markSeen(cid)
    }
    s.startDraft(folder, agentType)
    if (this.newPaper.length > 0) {
      s.paperId = this.newPaper
      this.newPaper = ''
    }
    this.session = s
    this.sessionFromProject = this.section === 'projects'
    if (this.section !== 'projects') {
      this.section = 'sessions'
    }
  }

  /** System back: close preview, then session, then project, then fall back to the Sessions tab. */
  onBackPress(): boolean {
    if (this.previewPath.length > 0) {
      this.previewPath = ''
      return true
    }
    if (this.session !== null && (layout.isCompact || this.section === 'projects')) {
      this.disposeSession()
      return true
    }
    if (this.section === 'projects' && this.project !== null && layout.isCompact) {
      this.project = null
      return true
    }
    if (this.section !== 'sessions') {
      this.section = 'sessions'
      return true
    }
    return false
  }

  newSession(folderId: number = -1): void {
    if (folderId < 0) {
      this.newPaper = ''
    }
    this.newFolder = folderId
    this.showNew = true
  }

  @Builder
  newSheet() {
    NewSessionSheet({ presetFolder: this.newFolder, onStart: (a: string, f: FolderDetail | null) => this.startNew(a, f) })
  }

  // ---------- panes ----------

  @Builder
  listPane() {
    if (this.section === 'sessions') {
      SessionsList({
        selectedId: this.session?.conversationId ?? 0,
        onOpen: (c: ConversationSummary) => this.openConversation(c),
        onNew: () => this.newSession()
      })
    } else if (this.section === 'projects') {
      ProjectsList({
        selectedId: this.project?.id ?? 0,
        onOpen: (f: FolderDetail) => {
          this.project = f
          this.disposeSession()
        }
      })
    } else if (this.section === 'machines') {
      MachinesView()
    } else if (this.section === 'academic') {
      AcademicView({
        onOpenConversation: (id: number, f: number) => {
          this.section = 'sessions'
          this.openConversationId(id)
        },
        onNewPaperSession: (paper: string, f: number) => {
          this.newPaper = paper
          this.newSession(f)
        }
      })
    } else {
      SettingsView({ onLanguage: () => {
        this.langFlip = !this.langFlip
      } })
    }
  }

  @Builder
  sessionPane(showBack: boolean) {
    SessionView({
      ctrl: this.session, showBack: showBack,
      onBack: () => this.disposeSession(),
      onOpenFiles: () => {
        const f = this.session?.folder ?? null
        if (f !== null) {
          this.section = 'projects'
          this.project = f
          this.disposeSession()
        }
      }
    })
  }

  @Builder
  projectPane(showBack: boolean) {
    ProjectDetail({
      folder: this.project, showBack: showBack,
      selectedConversation: this.session?.conversationId ?? 0,
      onBack: () => {
        this.project = null
      },
      onOpenConversation: (c: ConversationSummary) => this.openConversation(c, true),
      onNewSession: (f: FolderDetail) => this.newSession(f.id),
      onPreview: (r: string, p: string) => {
        this.previewRoot = r
        this.previewLine = 0
        this.previewPath = p
      },
      onOpenFolder: (f: FolderDetail) => {
        this.project = f
      }
    })
  }

  hasDetail(): boolean {
    return this.section === 'sessions' || this.section === 'projects'
  }

  @Builder
  detailPane() {
    if (this.previewPath.length > 0) {
      FilePreview({ root: this.previewRoot, path: this.previewPath, lineNo: this.previewLine, onClose: () => {
        this.previewPath = ''
      } })
    } else if (this.session !== null && (this.section === 'sessions' || this.sessionFromProject)) {
      this.sessionPane(this.section === 'projects')
    } else if (this.section === 'projects' && this.project !== null) {
      this.projectPane(false)
    } else {
      EmptyState({
        icon: this.section === 'projects' ? 'folder' : 'message',
        title: this.section === 'projects' ? L('Select a project', '选择一个项目') : L('Select a session', '选择一个会话'),
        message: L('Unfold or rotate to work side by side; the open session stays put.',
          '展开或横屏即可并排工作，打开的会话会保持不变。'),
        action: L('New session', '新建会话'), onAction: () => this.newSession()
      })
    }
  }

  // ---------- chrome ----------

  @Builder
  rail() {
    Column({ space: 6 }) {
      Image($r('app.media.app_icon')).width(36).height(36).borderRadius(10).margin({ top: 12, bottom: 10 })
      ForEach(this.sections(), (s: Section) => {
        Column({ space: 3 }) {
          SymbolGlyph(sym(s.icon)).fontSize(21)
            .fontColor([this.section === s.id ? $r('app.color.accent') : $r('app.color.text3')])
          Text(s.label).fontSize(10).fontColor(this.section === s.id ? $r('app.color.accent') : $r('app.color.text3'))
        }
        .width(60).padding({ top: 8, bottom: 8 }).borderRadius(14)
        .backgroundColor(this.section === s.id ? $r('app.color.accent_soft') : Color.Transparent)
        .onClick(() => {
          this.section = s.id
        })
      }, (s: Section) => s.id)
      Blank()
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(sym('plus')).fontSize(22).fontColor([Color.White])
      }
      .width(48).height(48).backgroundColor($r('app.color.accent')).margin({ bottom: 16 })
      .onClick(() => this.newSession())
    }
    .width(76)
    .height('100%')
    .backgroundColor($r('app.color.rail'))
  }

  @Builder
  bottomBar() {
    Row() {
      ForEach(this.sections(), (s: Section) => {
        Column({ space: 2 }) {
          SymbolGlyph(sym(s.icon)).fontSize(22)
            .fontColor([this.section === s.id ? $r('app.color.accent') : $r('app.color.text3')])
          Text(s.label).fontSize(10).fontColor(this.section === s.id ? $r('app.color.accent') : $r('app.color.text3'))
        }
        .layoutWeight(1).padding({ top: 7, bottom: 6 })
        .onClick(() => {
          this.section = s.id
        })
      }, (s: Section) => s.id)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.5 }, color: $r('app.color.border') })
  }

  @Builder
  compactLayout() {
    if (this.previewPath.length > 0) {
      FilePreview({ root: this.previewRoot, path: this.previewPath, lineNo: this.previewLine, onClose: () => {
        this.previewPath = ''
      } })
    } else if (this.session !== null && (this.section === 'sessions' || this.sessionFromProject ||
      this.section === 'academic')) {
      this.sessionPane(true)
    } else if (this.section === 'projects' && this.project !== null) {
      this.projectPane(true)
    } else {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          this.listPane()
        }.width('100%').height('100%')
        if (this.section === 'sessions' || this.section === 'projects') {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(sym('plus')).fontSize(24).fontColor([Color.White])
          }
          .width(56).height(56).backgroundColor($r('app.color.accent')).margin({ right: 18, bottom: 18 })
          .shadow({ radius: 18, color: '#33000000', offsetY: 6 })
          .onClick(() => this.newSession())
        }
      }.layoutWeight(1).width('100%')
      this.bottomBar()
    }
  }

  @Builder
  splitLayout() {
    Row() {
      this.rail()
      if (this.hasDetail()) {
        Column() {
          this.listPane()
        }
        .width(layout.listWidth)
        .height('100%')
        .border({ width: { right: 0.5 }, color: $r('app.color.border') })
        Column() {
          this.detailPane()
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor($r('app.color.bg'))
      } else {
        Column() {
          this.listPane()
        }.layoutWeight(1).height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  content() {
    if (app.servers.length === 0) {
      Onboarding()
    } else if (layout.isCompact) {
      Column() {
        this.compactLayout()
      }.width('100%').height('100%')
    } else {
      this.splitLayout()
    }
  }

  @Builder
  crashBanner() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph(sym('exclamationmark_triangle')).fontSize(16).fontColor([$r('app.color.danger')])
        Text(L('The app crashed last time. Long-press to copy the details and send them to the developer.',
          '上次运行时崩溃了，长按可复制详情发给开发者。')).fontSize(13).fontColor($r('app.color.text')).layoutWeight(1)
        SymbolGlyph(sym('xmark')).fontSize(15).fontColor([$r('app.color.text3')]).onClick(() => {
          this.lastCrash = ''
          Prefs.set('last_crash', '')
        })
      }.width('100%')
      Scroll() {
        Text(this.lastCrash).fontSize(11).fontFamily('monospace').fontColor($r('app.color.text2'))
          .copyOption(CopyOptions.LocalDevice)
      }.constraintSize({ maxHeight: 160 }).width('100%').align(Alignment.TopStart)
    }
    .padding(12)
    .margin({ left: 12, right: 12, top: layout.topInset + 4 })
    .borderRadius(12)
    .backgroundColor($r('app.color.danger_soft'))
  }

  build() {
    Column() {
      if (this.lastCrash.length > 0) {
        this.crashBanner()
      }
      // Toggling rebuilds the tree so language changes apply everywhere.
      if (this.langFlip) {
        this.content()
      } else {
        this.content()
      }
      // Hidden MathJax page that rasterises formulas; out of layout flow.
      MathHost().position({ x: 0, y: 0 }).zIndex(-1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showNew, this.newSheet(), {
      height: SheetSize.LARGE, dragBar: true, preferType: SheetType.CENTER, backgroundColor: $r('app.color.surface')
    })
  }

  onPageShow(): void {
    app.resume()
  }

  onPageHide(): void {
    app.pause()
  }
}

