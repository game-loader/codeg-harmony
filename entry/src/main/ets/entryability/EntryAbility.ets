import { UIAbility, AbilityConstant, Want, errorManager } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { app } from '../store/AppState'
import { layout } from '../store/Layout'
import { AppPrefs } from '../store/ServerStore'
import { initLocale, setZh } from '../common/I18n'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    initLocale()
    app.init(this.context)
    // Keep the last uncaught JS error so the next launch can show it.
    try {
      errorManager.on('error', {
        onUnhandledException: (msg: string) => {
          AppPrefs.setSync('last_crash', `${new Date().toISOString()}\n${msg}`)
        },
        onException: (err: Error) => {
          AppPrefs.setSync('last_crash', `${new Date().toISOString()}\n${err.name}: ${err.message}\n${err.stack ?? ''}`)
        }
      })
    } catch (e) {
      // Older systems.
    }
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
