/** Global link router; the shell installs the real handler. */
export class LinkRouter {
  static handler: (href: string, rootPath: string) => void = (href: string, rootPath: string) => {
  }

  static open(href: string, rootPath: string = ''): void {
    LinkRouter.handler(href, rootPath)
  }
}
