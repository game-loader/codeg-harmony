import { CodegClient, Timeouts, UploadFile } from './CodegClient'
import { JObj, arr, asArr, asObj, bool, isObj, num, obj, str, strArr } from '../common/Json'
import {
  AgentInfo, ConversationDetail, ConversationSummary, ConversationTag, DirEntry, ExpertSkill,
  FolderDetail, GitBranches, GitLogEntry, GitStatusEntry, GitWorktree, Machine, QuickMessage
} from '../model/Models'

export class HealthInfo {
  status: string = ''
  version: string = ''
}

export class UploadedAttachment {
  path: string = ''
  name: string = ''
  size: number = 0
  mimeType: string = ''

  /** Percent-encoded file:// URI for a server path; handles Windows drive and UNC paths. */
  get fileUri(): string {
    let p = this.path.replace(new RegExp('\\\\', 'g'), '/')
    if (p.startsWith('//')) {
      return 'file:' + encodeURI(p)
    }
    if (new RegExp('^[A-Za-z]:/').test(p)) {
      p = '/' + p
    }
    return 'file://' + encodeURI(p).replace(new RegExp('#', 'g'), '%23').replace(new RegExp('\\?', 'g'), '%3F')
  }
}

/** Result of `create_chat_conversation`: the new row and the hidden folder the chat runs in. */
export class ChatCreated {
  conversationId: number = 0
  folderId: number = 0
  folder: FolderDetail | null = null
}

export class GitCredentials {
  username: string = ''
  password: string = ''
}

function credObj(c?: GitCredentials): JObj | undefined {
  if (c === undefined) {
    return undefined
  }
  const o: JObj = { 'username': c.username, 'password': c.password }
  return o
}

/** Drops undefined values so the server sees omitted keys instead of nulls. */
export function body(o: Record<string, Object | undefined>): JObj {
  const out: JObj = {} as JObj
  for (const k of Object.keys(o)) {
    const v = o[k]
    if (v !== undefined) {
      out[k] = v
    }
  }
  return out
}

/** Typed wrappers over the server commands the client uses. */
export class Api {
  readonly c: CodegClient

  constructor(c: CodegClient) {
    this.c = c
  }

  async health(): Promise<HealthInfo> {
    const o = asObj(await this.c.call('health', undefined, Timeouts.LIST))
    const h = new HealthInfo()
    h.status = str(o, 'status')
    h.version = str(o, 'version')
    return h
  }

  // ---- folders & conversations ----

  async allFolders(): Promise<FolderDetail[]> {
    return asArr(await this.c.call('list_all_folder_details', undefined, Timeouts.LIST))
      .map((v: Object) => FolderDetail.from(v))
  }

  async openFolders(): Promise<FolderDetail[]> {
    return asArr(await this.c.call('list_open_folder_details', undefined, Timeouts.LIST))
      .map((v: Object) => FolderDetail.from(v))
  }

  async conversations(search?: string): Promise<ConversationSummary[]> {
    return asArr(await this.c.call('list_all_conversations', body({ 'search': search }), Timeouts.LIST))
      .map((v: Object) => ConversationSummary.from(v))
  }

  async conversation(id: number): Promise<ConversationDetail> {
    return ConversationDetail.from(asObj(await this.c.call('get_folder_conversation', { 'conversationId': id })))
  }

  async createConversation(folderId: number, agentType: string, title?: string, paperId?: string): Promise<number> {
    const r = await this.c.send('create_conversation',
      body({ 'folderId': folderId, 'agentType': agentType, 'title': title, 'academicPaperId': paperId }))
    return typeof r === 'number' ? r as number : num(asObj(r), 'id')
  }

  async createChatConversation(agentType: string, title?: string, paperId?: string): Promise<ChatCreated> {
    const o = asObj(await this.c.send('create_chat_conversation',
      body({ 'agentType': agentType, 'title': title, 'academicPaperId': paperId })))
    const r = new ChatCreated()
    r.conversationId = num(o, 'conversationId', num(o, 'conversation_id'))
    r.folderId = num(o, 'folderId', num(o, 'folder_id'))
    if (isObj(o['folder'])) {
      r.folder = FolderDetail.from(o['folder'])
    }
    return r
  }

  async setPinned(id: number, pinned: boolean): Promise<void> {
    await this.c.send('update_conversation_pinned', { 'conversationId': id, 'pinned': pinned })
  }

  async setTitle(id: number, title: string): Promise<void> {
    await this.c.send('update_conversation_title', { 'conversationId': id, 'title': title })
  }

  async setStatus(id: number, status: string): Promise<void> {
    await this.c.send('update_conversation_status', { 'conversationId': id, 'status': status })
  }

  async deleteConversation(id: number): Promise<void> {
    await this.c.send('delete_conversation', { 'conversationId': id })
  }

  async tags(): Promise<ConversationTag[]> {
    try {
      return asArr(await this.c.call('list_conversation_tags', undefined, Timeouts.LIST))
        .map((v: Object) => ConversationTag.from(v))
    } catch (e) {
      return []
    }
  }

  async updateConversationTags(id: number, add: number[], remove: number[]): Promise<void> {
    await this.c.send('update_conversation_tags', { 'conversationId': id, 'add': add, 'remove': remove })
  }

  async createTag(name: string, color: string, folderId?: number): Promise<void> {
    await this.c.send('create_conversation_tag', body({ 'folderId': folderId, 'name': name, 'color': color }))
  }

  async deleteTag(tagId: number): Promise<void> {
    await this.c.send('delete_conversation_tag', { 'tagId': tagId })
  }

  // ---- ACP ----

  async agents(): Promise<AgentInfo[]> {
    const list = asArr(await this.c.call('acp_list_agents', undefined, Timeouts.LIST))
      .map((v: Object) => AgentInfo.from(v))
    return list.sort((a: AgentInfo, b: AgentInfo) => a.sortOrder - b.sortOrder)
  }

  async connect(agentType: string, workingDir?: string, sessionId?: string, modeId?: string,
    config?: JObj): Promise<string> {
    const r = await this.c.send('acp_connect', body({
      'agentType': agentType, 'workingDir': workingDir, 'sessionId': sessionId,
      'preferredModeId': modeId, 'preferredConfigValues': config
    }), Timeouts.PROBE)
    return typeof r === 'string' ? r as string : str(asObj(r), 'connection_id')
  }

  async prompt(connectionId: string, blocks: JObj[], folderId?: number, conversationId?: number,
    clientMessageId?: string): Promise<void> {
    await this.c.send('acp_prompt', body({
      'connectionId': connectionId, 'blocks': blocks, 'folderId': folderId,
      'conversationId': conversationId, 'clientMessageId': clientMessageId
    }))
  }

  async cancel(connectionId: string): Promise<void> {
    await this.c.send('acp_cancel', { 'connectionId': connectionId })
  }

  async respondPermission(connectionId: string, requestId: string, optionId: string): Promise<void> {
    await this.c.send('acp_respond_permission',
      { 'connectionId': connectionId, 'requestId': requestId, 'optionId': optionId })
  }

  async answerQuestion(connectionId: string, questionId: string, answers: JObj[], declined: boolean): Promise<void> {
    const answer: JObj = { 'answers': answers, 'declined': declined }
    await this.c.send('acp_answer_question',
      { 'connectionId': connectionId, 'questionId': questionId, 'answer': answer })
  }

  async answerPlanApproval(connectionId: string, approvalId: string, decision: string, feedback?: string): Promise<void> {
    await this.c.send('acp_answer_plan_approval', {
      'connectionId': connectionId, 'approvalId': approvalId,
      'answer': body({ 'decision': decision, 'feedback': feedback })
    })
  }

  async findConnection(conversationId: number, agentType: string, sessionId?: string): Promise<string | null> {
    const r = await this.c.call('acp_find_connection_for_conversation',
      body({ 'conversationId': conversationId, 'sessionId': sessionId, 'agentType': agentType }))
    if (r === null) {
      return null
    }
    const id = str(asObj(r), 'connection_id')
    return id.length > 0 ? id : null
  }

  /** The live state of a connection; null when the server no longer has it. */
  async sessionSnapshot(connectionId: string): Promise<JObj | null> {
    const r = await this.c.call('acp_get_session_snapshot', { 'connectionId': connectionId })
    return r === null ? null : asObj(r)
  }

  /**
   * The modes and options an agent offers a new session. `configValues` are
   * applied first, as a launch would: pass the model so that the lists that
   * depend on it (effort levels, fast mode) are the ones for that model.
   */
  async describeAgentOptions(agentType: string, workingDir?: string, configValues?: JObj): Promise<JObj> {
    return asObj(await this.c.call('acp_describe_agent_options',
      body({ 'agentType': agentType, 'workingDir': workingDir, 'configValues': configValues }), Timeouts.PROBE))
  }

  async setMode(connectionId: string, modeId: string): Promise<void> {
    await this.c.send('acp_set_mode', { 'connectionId': connectionId, 'modeId': modeId })
  }

  async setConfigOption(connectionId: string, configId: string, valueId: string): Promise<void> {
    await this.c.send('acp_set_config_option',
      { 'connectionId': connectionId, 'configId': configId, 'valueId': valueId })
  }

  async submitFeedback(connectionId: string, text: string): Promise<void> {
    await this.c.send('submit_session_feedback', { 'connectionId': connectionId, 'text': text })
  }

  /** `env` is required and stored as given, so resend the agent's current env to avoid wiping it. */
  async setAgentEnabled(a: AgentInfo, enabled: boolean): Promise<void> {
    await this.c.send('acp_update_agent_env', body({
      'agentType': a.agentType, 'enabled': enabled, 'env': a.env, 'modelProviderId': a.modelProviderId
    }))
  }

  async preflight(agentType: string): Promise<JObj> {
    return asObj(await this.c.call('acp_preflight', { 'agentType': agentType, 'forceRefresh': true },
      Timeouts.PROBE))
  }

  // ---- composer helpers ----

  async quickMessages(): Promise<QuickMessage[]> {
    try {
      return asArr(await this.c.call('quick_messages_list', undefined, Timeouts.LIST))
        .map((v: Object) => QuickMessage.from(v))
        .sort((a: QuickMessage, b: QuickMessage) => a.sortOrder - b.sortOrder)
    } catch (e) {
      return []
    }
  }

  async createQuickMessage(title: string, content: string): Promise<void> {
    await this.c.send('quick_messages_create', { 'title': title, 'content': content })
  }

  async updateQuickMessage(id: number, title: string, content: string): Promise<void> {
    await this.c.send('quick_messages_update', { 'id': id, 'title': title, 'content': content })
  }

  async deleteQuickMessage(id: number): Promise<void> {
    await this.c.send('quick_messages_delete', { 'id': id })
  }

  /** Experts linked to codeg for the given agent. */
  async experts(agentType: string, lang: string): Promise<ExpertSkill[]> {
    try {
      const list = asArr(await this.c.call('experts_list', undefined, Timeouts.LIST))
      const statuses = asArr(await this.c.call('experts_list_all_install_statuses', undefined, Timeouts.LIST))
      const linked = new Set<string>()
      for (const s of statuses) {
        const o = asObj(s)
        if (str(o, 'agentType', str(o, 'agent_type')) === agentType && str(o, 'state') === 'linked_to_codeg') {
          linked.add(str(o, 'expertId', str(o, 'expert_id')))
        }
      }
      const out: ExpertSkill[] = []
      for (const v of list) {
        const m = obj(asObj(v), 'metadata')
        const id = str(m, 'id')
        if (!linked.has(id)) {
          continue
        }
        const e = new ExpertSkill()
        e.id = id
        e.category = str(m, 'category')
        e.name = localized(obj(m, 'display_name'), lang, id)
        e.description = localized(obj(m, 'description'), lang, '')
        out.push(e)
      }
      return out
    } catch (e) {
      return []
    }
  }

  async uploadAttachment(f: UploadFile): Promise<UploadedAttachment> {
    const o = asObj(await this.c.upload(f))
    const u = new UploadedAttachment()
    u.path = str(o, 'path')
    u.name = str(o, 'name', f.name)
    u.size = num(o, 'size')
    u.mimeType = str(o, 'mimeType', str(o, 'mime_type', f.mimeType))
    return u
  }

  // ---- filesystem ----

  async homeDirectory(): Promise<string> {
    const r = await this.c.call('get_home_directory')
    return typeof r === 'string' ? r as string : ''
  }

  async directoryEntries(path: string): Promise<DirEntry[]> {
    return asArr(await this.c.call('list_directory_entries', { 'path': path }, Timeouts.LIST))
      .map((v: Object) => DirEntry.from(v))
  }

  async directoryWithFiles(path: string): Promise<DirEntry[]> {
    return asArr(await this.c.call('list_directory_with_files', { 'path': path }, Timeouts.LIST))
      .map((v: Object) => DirEntry.from(v))
  }

  async openFolder(path: string): Promise<FolderDetail> {
    return FolderDetail.from(asObj(await this.c.send('open_folder', { 'path': path })))
  }

  async readFile(rootPath: string, relPath: string): Promise<string> {
    return str(asObj(await this.c.call('read_file_preview', { 'rootPath': rootPath, 'path': relPath })), 'content')
  }

  async readFileBase64(rootPath: string, relPath: string, maxBytes: number): Promise<string> {
    const r = await this.c.call('read_workspace_file_base64',
      { 'rootPath': rootPath, 'path': relPath, 'maxBytes': maxBytes })
    return typeof r === 'string' ? r as string : ''
  }

  async startVideoPreview(rootPath: string, relPath: string): Promise<string> {
    const o = asObj(await this.c.send('start_video_preview', { 'rootPath': rootPath, 'path': relPath }))
    return str(o, 'token')
  }

  async stopVideoPreview(token: string): Promise<void> {
    try {
      await this.c.send('stop_video_preview', { 'token': token })
    } catch (e) {
      // The server expires tokens on its own.
    }
  }

  async deleteEntry(rootPath: string, relPath: string): Promise<void> {
    await this.c.send('delete_file_tree_entry', { 'rootPath': rootPath, 'path': relPath })
  }

  async cloneRepository(url: string, targetDir: string, cred?: GitCredentials): Promise<void> {
    await this.c.send('clone_repository', body({ 'url': url, 'targetDir': targetDir, 'credentials': credObj(cred) }),
      Timeouts.INSTALL)
  }

  // ---- git ----

  async gitStatus(path: string): Promise<GitStatusEntry[]> {
    return asArr(await this.c.call('git_status', { 'path': path, 'showAllUntracked': true }))
      .map((v: Object) => GitStatusEntry.from(v))
  }

  async gitDiff(path: string, file?: string): Promise<string> {
    const r = await this.c.call('git_diff', body({ 'path': path, 'file': file }))
    return typeof r === 'string' ? r as string : ''
  }

  async gitShowDiff(path: string, commit: string, file?: string): Promise<string> {
    const r = await this.c.call('git_show_diff', body({ 'path': path, 'commit': commit, 'file': file }))
    return typeof r === 'string' ? r as string : ''
  }

  async gitLog(path: string, limit: number): Promise<GitLogEntry[]> {
    const o = asObj(await this.c.call('git_log', { 'path': path, 'limit': limit }))
    return arr(o, 'entries').map((v: Object) => GitLogEntry.from(v))
  }

  async branches(path: string): Promise<GitBranches> {
    return GitBranches.from(asObj(await this.c.call('git_list_all_branches', { 'path': path })))
  }

  async currentBranch(path: string): Promise<string> {
    const r = await this.c.call('get_git_branch', { 'path': path })
    return typeof r === 'string' ? r as string : ''
  }

  async checkout(path: string, branch: string): Promise<void> {
    await this.c.send('git_checkout', { 'path': path, 'branchName': branch })
  }

  async newBranch(path: string, branch: string, startPoint?: string): Promise<void> {
    await this.c.send('git_new_branch', body({ 'path': path, 'branchName': branch, 'startPoint': startPoint }))
  }

  async commit(path: string, message: string, files: string[], folderId?: number): Promise<number> {
    const o = asObj(await this.c.send('git_commit',
      body({ 'folderId': folderId, 'path': path, 'message': message, 'files': files })))
    return num(o, 'committed_files')
  }

  async push(path: string, folderId?: number, cred?: GitCredentials): Promise<number> {
    const o = asObj(await this.c.send('git_push',
      body({ 'folderId': folderId, 'path': path, 'credentials': credObj(cred) }), Timeouts.PROBE))
    return num(o, 'pushed_commits')
  }

  async pull(path: string, cred?: GitCredentials): Promise<number> {
    const o = asObj(await this.c.send('git_pull', body({ 'path': path, 'credentials': credObj(cred) }),
      Timeouts.PROBE))
    return num(o, 'updated_files')
  }

  async fetch(path: string, cred?: GitCredentials): Promise<void> {
    await this.c.send('git_fetch', body({ 'path': path, 'credentials': credObj(cred) }), Timeouts.PROBE)
  }

  async rollbackFile(path: string, file: string): Promise<void> {
    await this.c.send('git_rollback_file', { 'path': path, 'file': file })
  }

  async worktrees(path: string): Promise<GitWorktree[]> {
    return asArr(await this.c.call('git_list_worktrees', { 'path': path })).map((v: Object) => GitWorktree.from(v))
  }

  async worktreeAdd(path: string, branch: string, worktreePath: string, base?: string): Promise<void> {
    await this.c.send('git_worktree_add',
      body({ 'path': path, 'branchName': branch, 'worktreePath': worktreePath, 'base': base }))
  }

  async openWorktreeFolder(path: string, sourceFolderId: number): Promise<FolderDetail> {
    return FolderDetail.from(asObj(await this.c.send('open_worktree_folder',
      { 'path': path, 'sourceFolderId': sourceFolderId })))
  }

  // ---- terminal ----

  async defaultShell(): Promise<string | undefined> {
    try {
      const o = asObj(await this.c.call('get_system_terminal_settings'))
      const s = str(o, 'default_shell')
      return s.length > 0 ? s : undefined
    } catch (e) {
      return undefined
    }
  }

  async terminalSpawn(workingDir: string, terminalId: string, shell?: string): Promise<string> {
    const r = await this.c.send('terminal_spawn',
      body({ 'workingDir': workingDir, 'shell': shell, 'terminalId': terminalId }))
    return typeof r === 'string' ? r as string : terminalId
  }

  async terminalWrite(terminalId: string, data: string): Promise<void> {
    await this.c.send('terminal_write', { 'terminalId': terminalId, 'data': data })
  }

  async terminalResize(terminalId: string, cols: number, rows: number): Promise<void> {
    await this.c.send('terminal_resize', { 'terminalId': terminalId, 'cols': cols, 'rows': rows })
  }

  async terminalKill(terminalId: string): Promise<void> {
    try {
      await this.c.send('terminal_kill', { 'terminalId': terminalId })
    } catch (e) {
      // Already gone.
    }
  }

  async terminalSnapshot(terminalId: string): Promise<JObj> {
    return asObj(await this.c.call('terminal_snapshot', { 'terminalId': terminalId }))
  }

  // ---- machines ----

  async machines(): Promise<Machine[]> {
    const o = asObj(await this.c.call('list_machines', undefined, Timeouts.PROBE))
    return arr(o, 'machines').map((v: Object) => Machine.from(v))
  }

  async probeMachine(id: string, sshUser?: string): Promise<JObj> {
    return asObj(await this.c.send('probe_machine', body({ 'machineId': id, 'sshUser': sshUser }), Timeouts.PROBE))
  }

  async saveManualMachine(input: JObj): Promise<void> {
    await this.c.send('save_manual_machine', { 'input': input }, Timeouts.PROBE)
  }

  async deleteManualMachine(id: string): Promise<void> {
    await this.c.send('delete_manual_machine', { 'machineId': id })
  }

  // ---- academic ----

  async academicSettings(): Promise<JObj> {
    return asObj(await this.c.call('academic_settings_get'))
  }

  async academicLibrary(): Promise<JObj> {
    return asObj(await this.c.call('academic_library', undefined, Timeouts.PROBE))
  }

  async academicSelect(itemKey: string): Promise<JObj> {
    return asObj(await this.c.send('academic_select', { 'itemKey': itemKey }, Timeouts.PROBE))
  }

  async academicPaper(paperId: string): Promise<JObj> {
    return asObj(await this.c.call('academic_paper_get', { 'paperId': paperId }))
  }

  async academicImport(identifier: string, collectionKey: string): Promise<void> {
    await this.c.send('academic_import', { 'identifier': identifier, 'collectionKey': collectionKey },
      Timeouts.PROBE)
  }

  async academicPrepare(paperId: string): Promise<void> {
    await this.c.send('academic_prepare', { 'paperId': paperId }, Timeouts.PROBE)
  }

  async academicCancel(paperId: string): Promise<void> {
    await this.c.send('academic_cancel', { 'paperId': paperId })
  }

  async conversationPaper(conversationId: number): Promise<JObj | null> {
    try {
      const r = await this.c.call('academic_conversation_paper', { 'conversationId': conversationId })
      return r === null ? null : asObj(r)
    } catch (e) {
      return null
    }
  }

  // ---- settings ----

  async barkSettings(): Promise<JObj> {
    return asObj(await this.c.call('get_bark_notification_settings', { 'deviceId': deviceIdOf() }))
  }

  async setBarkSettings(s: JObj): Promise<void> {
    await this.c.send('set_bark_notification_settings', { 'deviceId': deviceIdOf(), 'settings': s })
  }

  async testBark(): Promise<void> {
    await this.c.send('test_bark_notification', { 'deviceId': deviceIdOf() })
  }

  async rawGet(command: string): Promise<JObj> {
    return asObj(await this.c.call(command))
  }

  async rawSet(command: string, settings: JObj): Promise<void> {
    await this.c.send(command, { 'settings': settings })
  }
}

let deviceIdProvider: () => string = () => ''

export function setDeviceIdProvider(f: () => string): void {
  deviceIdProvider = f
}

function deviceIdOf(): string {
  return deviceIdProvider()
}

function localized(m: JObj, lang: string, d: string): string {
  const keys = Object.keys(m)
  if (keys.length === 0) {
    return d
  }
  const exact = str(m, lang)
  if (exact.length > 0) {
    return exact
  }
  const prefix = lang.split('-')[0]
  for (const k of keys) {
    if (k.startsWith(prefix)) {
      return str(m, k)
    }
  }
  return str(m, 'en', str(m, keys[0], d))
}

export { bool, strArr }
