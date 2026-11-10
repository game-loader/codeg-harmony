import { L } from './I18n'

class AgentMeta {
  name: string
  color: string
  glyph: string

  constructor(name: string, color: string, glyph: string) {
    this.name = name
    this.color = color
    this.glyph = glyph
  }
}

const META: Map<string, AgentMeta> = new Map([
  ['claude_code', new AgentMeta('Claude Code', '#D97757', 'C')],
  ['codex', new AgentMeta('Codex', '#10A37F', 'X')],
  ['open_code', new AgentMeta('OpenCode', '#3B82F6', 'O')],
  ['gemini', new AgentMeta('Gemini', '#4285F4', 'G')],
  ['open_claw', new AgentMeta('OpenClaw', '#E11D48', 'W')],
  ['cline', new AgentMeta('Cline', '#8B5CF6', 'L')],
  ['hermes', new AgentMeta('Hermes', '#F59E0B', 'H')],
  ['code_buddy', new AgentMeta('CodeBuddy', '#06B6D4', 'B')],
  ['kimi_code', new AgentMeta('Kimi Code', '#111827', 'K')],
  ['pi', new AgentMeta('Pi', '#84CC16', 'π')],
  ['grok', new AgentMeta('Grok', '#374151', 'R')],
  ['cursor', new AgentMeta('Cursor', '#0F172A', 'U')],
  ['deepseek', new AgentMeta('DeepSeek', '#4D6BFE', 'D')],
  ['qoder', new AgentMeta('Qoder', '#22C55E', 'Q')],
  ['antigravity', new AgentMeta('Antigravity', '#A855F7', 'A')]
])

export function agentName(t: string): string {
  const m = META.get(t)
  if (m !== undefined) {
    return m.name
  }
  return t.length > 0 ? t : L('Agent', '智能体')
}

export function agentColor(t: string): string {
  return META.get(t)?.color ?? '#6366F1'
}

export function agentGlyph(t: string): string {
  return META.get(t)?.glyph ?? (t.length > 0 ? t.substring(0, 1).toUpperCase() : '?')
}

export function statusLabel(s: string): string {
  switch (s) {
    case 'in_progress':
      return L('Running', '进行中')
    case 'pending_review':
      return L('Review', '待审阅')
    case 'completed':
      return L('Done', '已完成')
    case 'cancelled':
      return L('Cancelled', '已取消')
    default:
      return s
  }
}

export function statusColor(s: string): ResourceColor {
  switch (s) {
    case 'in_progress':
      return $r('app.color.accent')
    case 'pending_review':
      return $r('app.color.warning')
    case 'completed':
      return $r('app.color.success')
    default:
      return $r('app.color.text3')
  }
}

export const STATUSES: string[] = ['in_progress', 'pending_review', 'completed', 'cancelled']
