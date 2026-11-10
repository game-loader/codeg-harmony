import { app } from '../store/AppState'
import { FolderDetail, GitLogEntry, GitStatusEntry, GitBranches } from '../model/Models'
import { ApiError, errorText } from '../net/ApiError'
import { GitCredentials } from '../net/Api'
import { FileDiff, parseUnifiedDiff } from '../session/Diff'
import { DiffView } from '../components/DiffView'
import { L, relativeTime } from '../common/I18n'
import { EmptyState, IconButton, Loading, sym, toast } from '../components/Common'

function statusColorOf(s: string): ResourceColor {
  const c = s.trim().substring(0, 1)
  if (c === 'A' || c === '?') {
    return $r('app.color.success')
  }
  if (c === 'D') {
    return $r('app.color.danger')
  }
  return $r('app.color.warning')
}

@ComponentV2
export struct GitView {
  @Param folder: FolderDetail | null = null
  @Local tab: number = 0
  @Local loading: boolean = false
  @Local notRepo: boolean = false
  @Local error: string = ''
  @Local changes: GitStatusEntry[] = []
  @Local selected: Set<string> = new Set()
  @Local selTick: number = 0
  @Local diffs: FileDiff[] = []
  @Local diffTitle: string = ''
  @Local showDiff: boolean = false
  @Local log: GitLogEntry[] = []
  @Local branch: string = ''
  @Local branches: GitBranches = new GitBranches()
  @Local message: string = ''
  @Local busy: string = ''
  @Local showCred: boolean = false
  @Local credUser: string = ''
  @Local credPass: string = ''
  @Local newBranch: string = ''
  private pendingAuth: (c: GitCredentials) => Promise<void> = async (c: GitCredentials) => {
  }

  get path(): string {
    return this.folder?.path ?? ''
  }

  aboutToAppear(): void {
    this.reload()
  }

  async reload(): Promise<void> {
    const api = app.api
    if (api === null || this.path.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      this.branch = await api.currentBranch(this.path)
      if (this.tab === 0) {
        this.changes = await api.gitStatus(this.path)
        const s = new Set<string>()
        this.changes.forEach((c: GitStatusEntry) => s.add(c.path))
        this.selected = s
        this.selTick++
      } else if (this.tab === 1) {
        this.log = await api.gitLog(this.path, 80)
      } else {
        this.branches = await api.branches(this.path)
      }
      this.notRepo = false
    } catch (e) {
      if (e instanceof ApiError && (e as ApiError).isNotGitRepo) {
        this.notRepo = true
      } else {
        this.error = errorText(e)
      }
    } finally {
      this.loading = false
    }
  }

  isSel(p: string): boolean {
    return this.selected.has(p) && this.selTick >= 0
  }

  toggle(p: string): void {
    if (this.selected.has(p)) {
      this.selected.delete(p)
    } else {
      this.selected.add(p)
    }
    this.selTick++
  }

  async openDiff(file: string, commit?: string): Promise<void> {
    const api = app.api
    if (api === null) {
      return
    }
    try {
      const raw = commit !== undefined ? await api.gitShowDiff(this.path, commit, file.length > 0 ? file : undefined) :
        await api.gitDiff(this.path, file)
      this.diffs = parseUnifiedDiff(raw)
      this.diffTitle = file.length > 0 ? file : (commit ?? '')
      this.showDiff = true
    } catch (e) {
      toast(errorText(e))
    }
  }

  /** Runs a remote git op; on an auth failure asks for credentials and retries. */
  async remote(label: string, op: (c?: GitCredentials) => Promise<string>): Promise<void> {
    this.busy = label
    try {
      toast(await op(undefined))
      this.reload()
    } catch (e) {
      if (e instanceof ApiError && (e as ApiError).isGitAuth) {
        this.pendingAuth = async (c: GitCredentials) => {
          this.busy = label
          try {
            toast(await op(c))
            this.reload()
          } catch (e2) {
            toast(errorText(e2))
          } finally {
            this.busy = ''
          }
        }
        this.showCred = true
      } else {
        toast(errorText(e))
      }
    } finally {
      this.busy = ''
    }
  }

  async commit(): Promise<void> {
    const api = app.api
    const files = this.changes.map((c: GitStatusEntry) => c.path).filter((p: string) => this.selected.has(p))
    if (api === null || this.message.trim().length === 0 || files.length === 0) {
      toast(L('Enter a message and select files', '请填写提交信息并选择文件'))
      return
    }
    this.busy = 'commit'
    try {
      const n = await api.commit(this.path, this.message.trim(), files, this.folder?.id)
      toast(L(`Committed ${n} files`, `已提交 ${n} 个文件`))
      this.message = ''
      this.reload()
    } catch (e) {
      toast(errorText(e))
    } finally {
      this.busy = ''
    }
  }

  @Builder
  credSheet() {
    Column({ space: 12 }) {
      Text(L('Git credentials', 'Git 凭据')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      TextInput({ placeholder: L('Username', '用户名') }).height(44).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.credUser = v
        })
      TextInput({ placeholder: L('Password or token', '密码或令牌') }).type(InputType.Password).height(44)
        .backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.credPass = v
        })
      Button(L('Continue', '继续')).type(ButtonType.Capsule).height(44).width('100%')
        .backgroundColor($r('app.color.accent'))
        .onClick(() => {
          const c = new GitCredentials()
          c.username = this.credUser
          c.password = this.credPass
          this.showCred = false
          this.pendingAuth(c)
        })
    }.padding(20).width('100%')
  }

  @Builder
  diffSheet() {
    Column() {
      Text(this.diffTitle).fontSize(14).fontFamily('monospace').fontColor($r('app.color.text2')).maxLines(1)
        .padding(14).width('100%')
      if (this.diffs.length === 0) {
        Text(L('No textual changes', '没有文本改动')).fontSize(14).fontColor($r('app.color.text3')).padding(20)
      }
      List({ space: 10 }) {
        ForEach(this.diffs, (d: FileDiff, i: number) => {
          ListItem() {
            DiffView({ diff: d, maxLines: 400 })
          }
        }, (d: FileDiff, i: number) => `${i}-${d.path}`)
      }.padding({ left: 12, right: 12, bottom: 20 }).layoutWeight(1)
    }.width('100%').height('100%')
  }

  @Builder
  tabBtn(i: number, label: string) {
    Text(label).fontSize(14).fontWeight(this.tab === i ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.tab === i ? $r('app.color.text') : $r('app.color.text3'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 }).borderRadius(16)
      .backgroundColor(this.tab === i ? $r('app.color.surface') : Color.Transparent)
      .onClick(() => {
        this.tab = i
        this.reload()
      })
  }

  @Builder
  changesTab() {
    Column() {
      if (this.changes.length === 0) {
        EmptyState({ icon: 'checkmark_circle', title: L('Working tree clean', '工作区干净') }).layoutWeight(1)
      } else {
        List() {
          ForEach(this.changes, (c: GitStatusEntry) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph(sym(this.isSel(c.path) ? 'checkmark_square_fill' : 'square')).fontSize(19)
                  .fontColor([this.isSel(c.path) ? $r('app.color.accent') : $r('app.color.text3')])
                  .onClick(() => this.toggle(c.path))
                Text(c.status.trim().length > 0 ? c.status.trim() : '?').fontSize(12).fontFamily('monospace')
                  .fontColor(statusColorOf(c.status)).width(22)
                Text(c.file).fontSize(13.5).fontFamily('monospace').fontColor($r('app.color.text')).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.MARQUEE })
              }
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .width('100%')
              .onClick(() => {
                this.openDiff(c.path)
              })
            }
            .swipeAction({ end: { builder: () => {
              this.discardBtn(c)
            } } })
          }, (c: GitStatusEntry) => `${c.status}-${c.file}`)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.border'), startMargin: 16 })
      }
      Column({ space: 8 }) {
        TextArea({ text: this.message, placeholder: L('Commit message', '提交信息') })
          .height(72).fontSize(14).backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.message = v
          })
        Row({ space: 8 }) {
          Button(this.busy === 'commit' ? '…' : L('Commit', '提交')).type(ButtonType.Capsule).height(40)
            .layoutWeight(1).backgroundColor($r('app.color.accent')).enabled(this.busy.length === 0)
            .onClick(() => {
              this.commit()
            })
          Button(this.busy === 'pull' ? '…' : L('Pull', '拉取')).type(ButtonType.Capsule).height(40)
            .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
            .enabled(this.busy.length === 0)
            .onClick(() => {
              this.remote('pull', async (c?: GitCredentials): Promise<string> => {
                const n = await app.api!.pull(this.path, c)
                return L(`Pulled · ${n} files updated`, `已拉取 · 更新 ${n} 个文件`)
              })
            })
          Button(this.busy === 'push' ? '…' : L('Push', '推送')).type(ButtonType.Capsule).height(40)
            .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
            .enabled(this.busy.length === 0)
            .onClick(() => {
              this.remote('push', async (c?: GitCredentials): Promise<string> => {
                const n = await app.api!.push(this.path, this.folder?.id, c)
                return L(`Pushed ${n} commits`, `已推送 ${n} 个提交`)
              })
            })
        }.width('100%')
      }.padding(12).width('100%')
    }.width('100%').layoutWeight(1)
  }

  @Builder
  discardBtn(c: GitStatusEntry) {
    Column({ space: 4 }) {
      SymbolGlyph(sym('arrow_clockwise')).fontSize(18).fontColor([Color.White])
      Text(L('Discard', '还原')).fontSize(11).fontColor(Color.White)
    }
    .width(80).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.danger'))
    .onClick(() => {
      this.getUIContext().showAlertDialog({
        title: L('Discard changes?', '还原改动？'), message: c.file,
        primaryButton: { value: L('Cancel', '取消'), action: () => {
        } },
        secondaryButton: {
          value: L('Discard', '还原'), fontColor: $r('app.color.danger'), action: async () => {
            try {
              await app.api?.rollbackFile(this.path, c.path)
              this.reload()
            } catch (e) {
              toast(errorText(e))
            }
          }
        }
      })
    })
  }

  @Builder
  historyTab() {
    List() {
      ForEach(this.log, (e: GitLogEntry) => {
        ListItem() {
          Column({ space: 4 }) {
            Text(e.message.split('\n')[0]).fontSize(14.5).fontColor($r('app.color.text')).maxLines(2)
            Row({ space: 8 }) {
              Text(e.hash.substring(0, 8)).fontSize(12).fontFamily('monospace').fontColor($r('app.color.accent'))
              Text(e.author).fontSize(12).fontColor($r('app.color.text3')).maxLines(1).layoutWeight(1)
              if (e.pushed === false) {
                SymbolGlyph(sym('arrow_up')).fontSize(12).fontColor([$r('app.color.warning')])
              }
              Text(relativeTime(e.date)).fontSize(11).fontColor($r('app.color.text3'))
            }.width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .width('100%')
          .onClick(() => {
            this.openDiff('', e.fullHash)
          })
        }
      }, (e: GitLogEntry) => e.fullHash)
    }
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: $r('app.color.border'), startMargin: 16 })
  }

  @Builder
  branchesTab() {
    List() {
      ListItem() {
        Row({ space: 8 }) {
          TextInput({ text: this.newBranch, placeholder: L('New branch name', '新分支名') }).height(40).layoutWeight(1)
            .backgroundColor($r('app.color.surface'))
            .onChange((v: string) => {
              this.newBranch = v
            })
          Button(L('Create', '创建')).type(ButtonType.Capsule).height(40).backgroundColor($r('app.color.accent'))
            .onClick(async () => {
              if (this.newBranch.trim().length === 0) {
                return
              }
              try {
                await app.api?.newBranch(this.path, this.newBranch.trim())
                this.newBranch = ''
                this.reload()
              } catch (e) {
                toast(errorText(e))
              }
            })
        }.padding(12)
      }
      ForEach(this.branches.local, (b: string) => {
        ListItem() {
          Row({ space: 10 }) {
            SymbolGlyph(sym(b === this.branch ? 'checkmark_circle_fill' : 'circle')).fontSize(17)
              .fontColor([b === this.branch ? $r('app.color.accent') : $r('app.color.text3')])
            Text(b).fontSize(14).fontFamily('monospace').fontColor($r('app.color.text')).layoutWeight(1)
            if (this.branches.worktreeBranches.includes(b)) {
              Text(L('worktree', '工作树')).fontSize(11).fontColor($r('app.color.text3'))
            }
          }
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .width('100%')
          .onClick(async () => {
            if (b === this.branch) {
              return
            }
            try {
              await app.api?.checkout(this.path, b)
              toast(L(`Switched to ${b}`, `已切换到 ${b}`))
              this.reload()
              app.refresh(true)
            } catch (e) {
              toast(errorText(e))
            }
          })
        }
      }, (b: string) => b)
      if (this.branches.remote.length > 0) {
        ListItem() {
          Text(L('Remote', '远程')).fontSize(12).fontColor($r('app.color.text3')).padding({ left: 16, top: 14, bottom: 6 })
        }
        ForEach(this.branches.remote, (b: string) => {
          ListItem() {
            Text(b).fontSize(13.5).fontFamily('monospace').fontColor($r('app.color.text2'))
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          }
        }, (b: string) => `r-${b}`)
      }
    }.layoutWeight(1)
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        SymbolGlyph(sym('rectangle_split_3x1')).fontSize(14).fontColor([$r('app.color.text3')])
        Text(this.branch.length > 0 ? this.branch : '—').fontSize(13).fontFamily('monospace')
          .fontColor($r('app.color.text2')).layoutWeight(1).maxLines(1)
        IconButton({ icon: 'arrow_clockwise', sz: 17, box: 32, onTap: () => {
          this.reload()
        } })
      }.padding({ left: 16, right: 8 }).width('100%')
      Row({ space: 4 }) {
        this.tabBtn(0, L('Changes', '改动'))
        this.tabBtn(1, L('History', '历史'))
        this.tabBtn(2, L('Branches', '分支'))
      }
      .padding(4).borderRadius(20).backgroundColor($r('app.color.surface2')).margin({ top: 4, bottom: 8 })

      if (this.notRepo) {
        EmptyState({ icon: 'folder', title: L('Not a git repository', '不是 Git 仓库') }).layoutWeight(1)
      } else if (this.loading && this.changes.length === 0 && this.log.length === 0) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        EmptyState({ icon: 'exclamationmark_triangle', title: L('Git error', 'Git 错误'), message: this.error })
          .layoutWeight(1)
      } else if (this.tab === 0) {
        this.changesTab()
      } else if (this.tab === 1) {
        this.historyTab()
      } else {
        this.branchesTab()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showDiff, this.diffSheet(), { height: SheetSize.LARGE, dragBar: true })
    .bindSheet($$this.showCred, this.credSheet(), { height: 320, dragBar: true })
  }
}
