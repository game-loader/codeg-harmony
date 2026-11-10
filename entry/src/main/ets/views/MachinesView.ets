import { app } from '../store/AppState'
import { Machine } from '../model/Models'
import { errorText } from '../net/ApiError'
import { JObj, obj, str, num } from '../common/Json'
import { L, formatBytes } from '../common/I18n'
import { Card, Divider1, EmptyState, IconButton, Loading, sym, toast } from '../components/Common'

class Metric {
  label: string = ''
  value: string = ''
}

function metricsOf(r: JObj): Metric[] {
  const m = obj(r, 'metrics')
  const out: Metric[] = []
  const add = (label: string, v: string) => {
    if (v.length > 0) {
      const x = new Metric()
      x.label = label
      x.value = v
      out.push(x)
    }
  }
  add(L('Hostname', '主机名'), str(m, 'hostname'))
  add(L('OS', '系统'), str(m, 'os'))
  add(L('Architecture', '架构'), str(m, 'architecture'))
  add('CPU', str(m, 'cpu'))
  if (num(m, 'cpu_cores') > 0) {
    add(L('Cores', '核心'), `${num(m, 'cpu_cores')}`)
  }
  const total = num(m, 'memory_total')
  if (total > 0) {
    add(L('Memory', '内存'), `${formatBytes(total - num(m, 'memory_available'))} / ${formatBytes(total)}`)
  } else {
    add(L('Memory', '内存'), str(m, 'memory_total'))
  }
  add(L('Disk', '磁盘'), str(m, 'disk'))
  add(L('Load', '负载'), str(m, 'load'))
  add(L('Uptime', '运行时间'), str(m, 'uptime'))
  add('GPU', str(m, 'gpu'))
  add('SSH', str(r, 'ssh_target'))
  return out
}

@ComponentV2
export struct MachinesView {
  @Local list: Machine[] = []
  @Local loading: boolean = true
  @Local error: string = ''
  @Local selected: Machine | null = null
  @Local probing: boolean = false
  @Local metrics: Metric[] = []
  @Local probeError: string = ''
  @Local showAdd: boolean = false
  @Local fName: string = ''
  @Local fHost: string = ''
  @Local fPort: string = '22'
  @Local fUser: string = ''
  @Local fPass: string = ''

  aboutToAppear(): void {
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    try {
      this.list = await app.api!.machines()
      this.error = ''
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  async probe(m: Machine): Promise<void> {
    this.selected = m
    this.metrics = []
    this.probeError = ''
    this.probing = true
    try {
      this.metrics = metricsOf(await app.api!.probeMachine(m.id, m.sshUser))
    } catch (e) {
      this.probeError = errorText(e)
    } finally {
      this.probing = false
    }
  }

  async save(): Promise<void> {
    const input: JObj = {
      'name': this.fName.trim(), 'host': this.fHost.trim(), 'port': Number(this.fPort) || 22,
      'username': this.fUser.trim()
    } as JObj
    if (this.fPass.length > 0) {
      input['password'] = this.fPass
    }
    try {
      await app.api!.saveManualMachine(input)
      this.showAdd = false
      this.load()
    } catch (e) {
      toast(errorText(e))
    }
  }

  @Builder
  addSheet() {
    Column({ space: 10 }) {
      Text(L('Add machine', '添加机器')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      TextInput({ placeholder: L('Name', '名称') }).height(44).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.fName = v
        })
      TextInput({ placeholder: L('Host or IP', '主机或 IP') }).height(44).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.fHost = v
        })
      Row({ space: 8 }) {
        TextInput({ text: this.fPort, placeholder: '22' }).type(InputType.Number).height(44).width(90)
          .backgroundColor($r('app.color.surface2'))
          .onChange((v: string) => {
            this.fPort = v
          })
        TextInput({ placeholder: L('SSH user', 'SSH 用户') }).height(44).layoutWeight(1)
          .backgroundColor($r('app.color.surface2'))
          .onChange((v: string) => {
            this.fUser = v
          })
      }
      TextInput({ placeholder: L('Password (optional)', '密码（可选）') }).type(InputType.Password).height(44)
        .backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.fPass = v
        })
      Button(L('Save', '保存')).type(ButtonType.Capsule).height(44).width('100%')
        .backgroundColor($r('app.color.accent'))
        .onClick(() => {
          this.save()
        })
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Text(L('Machines', '机器')).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .layoutWeight(1)
        IconButton({ icon: 'arrow_clockwise', sz: 19, onTap: () => {
          this.load()
        } })
        IconButton({ icon: 'plus', sz: 20, color: $r('app.color.accent'), onTap: () => {
          this.showAdd = true
        } })
      }.padding({ left: 20, right: 10, top: 10, bottom: 6 }).width('100%')

      if (this.loading) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        EmptyState({ icon: 'exclamationmark_triangle', title: L('Machines unavailable', '无法获取机器'),
          message: this.error, action: L('Retry', '重试'), onAction: () => {
            this.load()
          } }).layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Card() {
              ForEach(this.list, (m: Machine, i: number) => {
                if (i > 0) {
                  Divider1({ inset: 56 })
                }
                Row({ space: 12 }) {
                  Row() {
                    SymbolGlyph(sym(m.isSelf ? 'house' : 'computer')).fontSize(17).fontColor([Color.White])
                  }
                  .width(30).height(30).borderRadius(8).justifyContent(FlexAlign.Center)
                  .backgroundColor(m.online === false ? $r('app.color.text3') : $r('app.color.accent2'))
                  Column({ space: 2 }) {
                    Text(m.name.length > 0 ? m.name : m.dnsName).fontSize(15.5).fontColor($r('app.color.text'))
                    Text([m.os, m.addresses.length > 0 ? m.addresses[0] : '', m.isManual ? L('manual', '手动') : 'Tailscale']
                      .filter((s: string) => s.length > 0).join(' · '))
                      .fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Circle().width(8).height(8)
                    .fill(m.online === true ? $r('app.color.success') : m.online === false ? $r('app.color.text3') :
                    $r('app.color.warning'))
                }
                .padding({ left: 14, right: 14, top: 11, bottom: 11 })
                .width('100%')
                .backgroundColor(this.selected?.id === m.id ? $r('app.color.accent_soft') : Color.Transparent)
                .onClick(() => {
                  this.probe(m)
                })
                .bindContextMenu(this.machineMenu(m), ResponseType.LongPress)
              }, (m: Machine) => m.id)
            }

            if (this.selected !== null) {
              Column({ space: 8 }) {
                Text(this.selected.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
                if (this.probing) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(18).height(18).color($r('app.color.accent'))
                    Text(L('Probing over SSH… (up to ~40s)', '通过 SSH 探测中…（最多约 40 秒）')).fontSize(13)
                      .fontColor($r('app.color.text3'))
                  }
                } else if (this.probeError.length > 0) {
                  Text(this.probeError).fontSize(13).fontColor($r('app.color.danger'))
                } else {
                  ForEach(this.metrics, (x: Metric) => {
                    Row() {
                      Text(x.label).fontSize(13).fontColor($r('app.color.text3')).width(100)
                      Text(x.value).fontSize(13).fontColor($r('app.color.text')).layoutWeight(1)
                        .copyOption(CopyOptions.LocalDevice)
                    }.width('100%')
                  }, (x: Metric) => x.label)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding(16)
              .width('100%')
              .borderRadius(16)
              .backgroundColor($r('app.color.surface'))
            }
          }.padding({ left: 16, right: 16, bottom: 90 })
        }.layoutWeight(1).align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showAdd, this.addSheet(), { height: SheetSize.FIT_CONTENT, dragBar: true })
  }

  @Builder
  machineMenu(m: Machine) {
    Menu() {
      MenuItem({ content: L('Probe', '探测') }).onClick(() => {
        this.probe(m)
      })
      if (m.isManual) {
        MenuItem({ content: L('Delete', '删除') }).onClick(async () => {
          try {
            await app.api!.deleteManualMachine(m.id)
            this.load()
          } catch (e) {
            toast(errorText(e))
          }
        })
      }
    }
  }
}
