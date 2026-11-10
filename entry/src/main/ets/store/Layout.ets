import { display, window } from '@kit.ArkUI'

/**
 * Window-class breakpoints and fold posture.
 * sm  < 600vp : phone, or a foldable's cover screen
 * md  < 840vp : unfolded book-style foldable, small tablet portrait
 * lg >= 840vp : tablet landscape, 2in1, wide unfolded screens
 * Half-folded (tent/laptop posture) on a horizontal crease splits the session
 * view across the crease: transcript above, composer below.
 */
@ObservedV2
export class LayoutState {
  @Trace widthVp: number = 360
  @Trace heightVp: number = 780
  @Trace bp: string = 'sm'
  @Trace foldStatus: number = 0
  @Trace halfFolded: boolean = false
  @Trace creaseTopVp: number = 0
  @Trace creaseHeightVp: number = 0
  @Trace topInset: number = 0
  @Trace bottomInset: number = 0
  @Trace keyboardVp: number = 0
  @Trace dark: boolean = false
  private density: number = 3

  attach(win: window.Window): void {
    try {
      this.density = display.getDefaultDisplaySync().densityPixels
    } catch (e) {
      this.density = 3
    }
    const r = win.getWindowProperties().windowRect
    this.setSize(r.width, r.height)
    win.on('windowSizeChange', (s: window.Size) => {
      this.setSize(s.width, s.height)
      this.readCrease()
    })
    try {
      const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      this.topInset = sys.topRect.height / this.density
      this.bottomInset = nav.bottomRect.height / this.density
      win.on('avoidAreaChange', (d: window.AvoidAreaOptions) => {
        if (d.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.topInset = d.area.topRect.height / this.density
        } else if (d.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomInset = d.area.bottomRect.height / this.density
        } else if (d.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.keyboardVp = d.area.bottomRect.height / this.density
        }
      })
    } catch (e) {
      // Older systems lack some avoid-area types.
    }
    try {
      if (display.isFoldable()) {
        this.applyFold(display.getFoldStatus())
        display.on('foldStatusChange', (s: display.FoldStatus) => {
          this.applyFold(s)
        })
      }
    } catch (e) {
      // Not a foldable.
    }
  }

  private setSize(wPx: number, hPx: number): void {
    this.widthVp = wPx / this.density
    this.heightVp = hPx / this.density
    this.bp = this.widthVp < 600 ? 'sm' : this.widthVp < 840 ? 'md' : 'lg'
  }

  private applyFold(s: display.FoldStatus): void {
    this.foldStatus = s
    this.readCrease()
  }

  private readCrease(): void {
    this.halfFolded = false
    if (this.foldStatus !== display.FoldStatus.FOLD_STATUS_HALF_FOLDED) {
      return
    }
    try {
      const region = display.getCurrentFoldCreaseRegion()
      if (region.creaseRects.length === 0) {
        return
      }
      const c = region.creaseRects[0]
      // A horizontal crease (wider than tall) means the screen bends top/bottom.
      if (c.width > c.height) {
        this.creaseTopVp = c.top / this.density
        this.creaseHeightVp = c.height / this.density
        this.halfFolded = this.creaseTopVp > 120
      }
    } catch (e) {
      this.halfFolded = false
    }
  }

  /** Concrete text color for rasterised content (formulas). Matches app.color.text. */
  get inkColor(): string {
    return this.dark ? '#ECEEF6' : '#141826'
  }

  get isCompact(): boolean {
    return this.bp === 'sm'
  }

  get isWide(): boolean {
    return this.bp === 'lg'
  }

  /** Width of the list column in split layouts. */
  get listWidth(): number {
    if (this.bp === 'lg') {
      return Math.min(380, Math.max(320, this.widthVp * 0.28))
    }
    return Math.min(340, Math.max(280, this.widthVp * 0.4))
  }

  /** Readable max width for transcript content on very wide panes. */
  get contentMax(): number {
    return 860
  }
}

export const layout: LayoutState = new LayoutState()
