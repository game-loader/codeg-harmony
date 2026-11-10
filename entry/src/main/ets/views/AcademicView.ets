import { app } from '../store/AppState'
import { errorText } from '../net/ApiError'
import { JObj, arr, asObj, obj, str, strArr } from '../common/Json'
import { L } from '../common/I18n'
import { EmptyState, IconButton, Loading, sym, toast } from '../components/Common'
import { MarkdownView } from '../components/Markdown'

class Collection {
  key: string = ''
  name: string = ''
  parent: string = ''
}

class Item {
  key: string = ''
  title: string = ''
  abstract: string = ''
  authors: string = ''
  doi: string = ''
  collections: string[] = []
}

class PaperConv {
  id: number = 0
  folderId: number = 0
  agentType: string = ''
  title: string = ''
}

class Paper {
  id: string = ''
  title: string = ''
  authors: string = ''
  abstract: string = ''
  status: string = ''
  error: string = ''
  analysis: string = ''
  folderId: number = 0
  repoUrl: string = ''
  convs: PaperConv[] = []

  static from(o: JObj): Paper {
    const p = new Paper()
    p.id = str(o, 'id')
    p.title = str(o, 'title')
    const a = o['authors']
    p.authors = Array.isArray(a) ? strArr(o, 'authors').join(', ') : str(o, 'authors')
    p.abstract = str(o, 'abstract_text')
    p.status = str(o, 'status')
    p.error = str(o, 'error')
    p.analysis = str(o, 'analysis')
    p.folderId = Number(str(o, 'folder_id', '0'))
    p.repoUrl = str(o, 'repo_url')
    for (const c of arr(o, 'conversations')) {
      const co = asObj(c)
      const pc = new PaperConv()
      pc.id = Number(str(co, 'id', '0'))
      pc.folderId = Number(str(co, 'folder_id', '0'))
      pc.agentType = str(co, 'agent_type')
      pc.title = str(co, 'title')
      p.convs.push(pc)
    }
    return p
  }
}

@ComponentV2
export struct AcademicView {
  @Event onOpenConversation: (id: number, folderId: number) => void = (id: number, f: number) => {
  }
  @Event onNewPaperSession: (paperId: string, folderId: number) => void = (p: string, f: number) => {
  }
  @Local loading: boolean = true
  @Local error: string = ''
  @Local collections: Collection[] = []
  @Local items: Item[] = []
  @Local coll: string = ''
  @Local query: string = ''
  @Local paper: Paper | null = null
  @Local paperLoading: boolean = false
  @Local showImport: boolean = false
  @Local importId: string = ''

  aboutToAppear(): void {
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    try {
      const lib = await app.api!.academicLibrary()
      this.collections = arr(lib, 'collections').map((v: Object) => {
        const o = asObj(v)
        const c = new Collection()
        c.key = str(o, 'key')
        c.name = str(o, 'name')
        c.parent = str(o, 'parent_key')
        return c
      })
      this.items = arr(lib, 'items').map((v: Object) => {
        const o = asObj(v)
        const it = new Item()
        it.key = str(o, 'key')
        it.title = str(o, 'title')
        it.abstract = str(o, 'abstract_text')
        it.authors = Array.isArray(o['authors']) ? strArr(o, 'authors').join(', ') : str(o, 'authors')
        it.doi = str(o, 'doi')
        it.collections = strArr(o, 'collections')
        return it
      })
      this.error = ''
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  @Computed
  get shown(): Item[] {
    const q = this.query.trim().toLowerCase()
    return this.items.filter((i: Item) => (this.coll.length === 0 || i.collections.includes(this.coll)) &&
      (q.length === 0 || i.title.toLowerCase().includes(q) || i.authors.toLowerCase().includes(q)))
  }

  async select(it: Item): Promise<void> {
    this.paperLoading = true
    try {
      this.paper = Paper.from(await app.api!.academicSelect(it.key))
    } catch (e) {
      toast(errorText(e))
    } finally {
      this.paperLoading = false
    }
  }

  async refreshPaper(): Promise<void> {
    if (this.paper === null) {
      return
    }
    try {
      this.paper = Paper.from(await app.api!.academicPaper(this.paper.id))
    } catch (e) {
      toast(errorText(e))
    }
  }

  @Builder
  importSheet() {
    Column({ space: 12 }) {
      Text(L('Import paper', '导入论文')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      TextInput({ placeholder: L('DOI, arXiv ID or URL', 'DOI、arXiv ID 或链接') }).height(44)
        .backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.importId = v
        })
      Button(L('Import', '导入')).type(ButtonType.Capsule).height(44).width('100%').backgroundColor($r('app.color.accent'))
        .onClick(async () => {
          try {
            await app.api!.academicImport(this.importId.trim(), this.coll)
            this.showImport = false
            this.load()
          } catch (e) {
            toast(errorText(e))
          }
        })
    }.padding(20).width('100%')
  }

  @Builder
  paperPane(p: Paper) {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => {
            this.paper = null
          } })
          Blank()
          IconButton({ icon: 'arrow_clockwise', sz: 18, onTap: () => {
            this.refreshPaper()
          } })
        }.width('100%')
        Text(p.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        Text(p.authors).fontSize(13).fontColor($r('app.color.text3'))
        Row({ space: 8 }) {
          Text(p.status).fontSize(12).fontColor($r('app.color.accent')).padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(10).backgroundColor($r('app.color.accent_soft'))
          if (p.repoUrl.length > 0) {
            Text(p.repoUrl).fontSize(12).fontColor($r('app.color.text3')).maxLines(1).layoutWeight(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.width('100%')
        if (p.error.length > 0) {
          Text(p.error).fontSize(13).fontColor($r('app.color.danger'))
        }
        Row({ space: 8 }) {
          Button(L('Prepare', '准备')).type(ButtonType.Capsule).height(38).fontSize(14)
            .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
            .onClick(async () => {
              try {
                await app.api!.academicPrepare(p.id)
                toast(L('Preparing paper workspace', '正在准备论文工作区'))
                this.refreshPaper()
              } catch (e) {
                toast(errorText(e))
              }
            })
          Button(L('New session', '新会话')).type(ButtonType.Capsule).height(38).fontSize(14)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => this.onNewPaperSession(p.id, p.folderId))
        }
        if (p.convs.length > 0) {
          Text(L('Sessions', '会话')).fontSize(12).fontColor($r('app.color.text3'))
          ForEach(p.convs, (c: PaperConv) => {
            Row({ space: 8 }) {
              SymbolGlyph(sym('message')).fontSize(15).fontColor([$r('app.color.accent')])
              Text(c.title.length > 0 ? c.title : `#${c.id}`).fontSize(14).fontColor($r('app.color.text'))
                .layoutWeight(1).maxLines(1)
              SymbolGlyph(sym('chevron_right')).fontSize(12).fontColor([$r('app.color.text3')])
            }
            .padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.surface'))
            .onClick(() => this.onOpenConversation(c.id, c.folderId))
          }, (c: PaperConv) => `${c.id}`)
        }
        if (p.analysis.length > 0) {
          Text(L('Analysis', '分析')).fontSize(12).fontColor($r('app.color.text3'))
          MarkdownView({ text: p.analysis, fontSize: 14.5 })
        }
        if (p.abstract.length > 0) {
          Text(L('Abstract', '摘要')).fontSize(12).fontColor($r('app.color.text3'))
          Text(p.abstract).fontSize(14).lineHeight(22).fontColor($r('app.color.text2'))
            .copyOption(CopyOptions.LocalDevice)
        }
      }.alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 90 })
    }.width('100%').height('100%').align(Alignment.Top)
  }

  build() {
    Column() {
      if (this.paper !== null) {
        this.paperPane(this.paper)
      } else {
        Row({ space: 4 }) {
          Text(L('Academic', '学术')).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
            .layoutWeight(1)
          IconButton({ icon: 'plus', sz: 20, color: $r('app.color.accent'), onTap: () => {
            this.showImport = true
          } })
        }.padding({ left: 20, right: 10, top: 10, bottom: 6 }).width('100%')
        Search({ value: this.query, placeholder: L('Search library', '搜索文献库') }).height(40)
          .margin({ left: 16, right: 16 }).backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.query = v
          })
        if (this.collections.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              Text(L('All', '全部')).fontSize(13).padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(16)
                .fontColor(this.coll === '' ? Color.White : $r('app.color.text2'))
                .backgroundColor(this.coll === '' ? $r('app.color.accent') : $r('app.color.surface'))
                .onClick(() => {
                  this.coll = ''
                })
              ForEach(this.collections, (c: Collection) => {
                Text(c.name).fontSize(13).padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(16)
                  .fontColor(this.coll === c.key ? Color.White : $r('app.color.text2'))
                  .backgroundColor(this.coll === c.key ? $r('app.color.accent') : $r('app.color.surface'))
                  .onClick(() => {
                    this.coll = c.key
                  })
              }, (c: Collection) => c.key)
            }.padding({ left: 16, right: 16 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).margin({ top: 10 }).width('100%')
        }
        if (this.loading) {
          Loading().layoutWeight(1)
        } else if (this.error.length > 0) {
          EmptyState({ icon: 'graduationcap', title: L('Library unavailable', '无法获取文献库'), message: this.error,
            action: L('Retry', '重试'), onAction: () => {
              this.load()
            } }).layoutWeight(1)
        } else if (this.shown.length === 0) {
          EmptyState({ icon: 'graduationcap', title: L('No papers', '没有论文') }).layoutWeight(1)
        } else {
          List({ space: 6 }) {
            ForEach(this.shown, (it: Item) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(it.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text')).maxLines(2)
                  Text(it.authors).fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .padding(14).width('100%').borderRadius(14).backgroundColor($r('app.color.surface'))
                .onClick(() => {
                  this.select(it)
                })
              }
            }, (it: Item) => it.key)
          }.padding({ left: 16, right: 16, top: 10 }).layoutWeight(1).scrollBar(BarState.Off)
        }
        if (this.paperLoading) {
          LoadingProgress().width(24).height(24).color($r('app.color.accent'))
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showImport, this.importSheet(), { height: 240, dragBar: true })
  }
}
