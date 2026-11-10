import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { app } from '../store/AppState'
import { layout } from '../store/Layout'
import { AppPrefs } from '../store/ServerStore'
import { initLocale, setZh } from '../common/I18n'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    initLocale()
    app.init(this.context)
    const lang = AppPrefs.get('lang')
    if (lang.length > 0) {
      setZh(lang === 'zh')
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      layout.attach(windowStage.getMainWindowSync())
    } catch (e) {
      // Keep default breakpoints.
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        console.error(`codeg: loadContent failed ${err.code}`)
      }
    })
  }

  onForeground(): void {
    app.resume()
  }

  onBackground(): void {
    app.pause()
  }
}
