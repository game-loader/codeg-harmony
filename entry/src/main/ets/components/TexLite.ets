/**
 * Minimal TeX → styled text runs, used when the MathJax image is not available.
 * It handles what agents actually write: sub/superscripts, Greek, common
 * operators, \frac, \sqrt, accents, \mathbb/\mathcal/\mathbf/\text and spacing.
 */
export class TexRun {
  text: string = ''
  /** 0 = baseline, -1 = subscript, 1 = superscript */
  level: number = 0
  italic: boolean = false
}

const SYMBOLS: Record<string, string> = {
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ϵ', 'varepsilon': 'ε', 'zeta': 'ζ',
  'eta': 'η', 'theta': 'θ', 'vartheta': 'ϑ', 'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ', 'nu': 'ν',
  'xi': 'ξ', 'pi': 'π', 'varpi': 'ϖ', 'rho': 'ρ', 'varrho': 'ϱ', 'sigma': 'σ', 'varsigma': 'ς', 'tau': 'τ',
  'upsilon': 'υ', 'phi': 'ϕ', 'varphi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ', 'Pi': 'Π', 'Sigma': 'Σ',
  'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
  'cdot': '·', 'cdots': '⋯', 'ldots': '…', 'dots': '…', 'vdots': '⋮', 'ddots': '⋱', 'times': '×', 'div': '÷',
  'pm': '±', 'mp': '∓', 'ast': '∗', 'star': '⋆', 'circ': '∘', 'bullet': '•', 'oplus': '⊕', 'otimes': '⊗',
  'le': '≤', 'leq': '≤', 'ge': '≥', 'geq': '≥', 'ne': '≠', 'neq': '≠', 'approx': '≈', 'sim': '∼',
  'simeq': '≃', 'cong': '≅', 'equiv': '≡', 'propto': '∝', 'll': '≪', 'gg': '≫', 'prec': '≺', 'succ': '≻',
  'in': '∈', 'notin': '∉', 'ni': '∋', 'subset': '⊂', 'subseteq': '⊆', 'supset': '⊃', 'supseteq': '⊇',
  'cup': '∪', 'cap': '∩', 'setminus': '∖', 'emptyset': '∅', 'varnothing': '∅', 'forall': '∀', 'exists': '∃',
  'nexists': '∄', 'neg': '¬', 'lnot': '¬', 'land': '∧', 'wedge': '∧', 'lor': '∨', 'vee': '∨',
  'to': '→', 'rightarrow': '→', 'leftarrow': '←', 'gets': '←', 'leftrightarrow': '↔', 'mapsto': '↦',
  'Rightarrow': '⇒', 'Leftarrow': '⇐', 'Leftrightarrow': '⇔', 'implies': '⟹', 'iff': '⟺',
  'Longrightarrow': '⟹', 'Longleftarrow': '⟸', 'Longleftrightarrow': '⟺', 'longrightarrow': '⟶',
  'uparrow': '↑', 'downarrow': '↓', 'therefore': '∴', 'because': '∵',
  'sum': '∑', 'prod': '∏', 'coprod': '∐', 'int': '∫', 'iint': '∬', 'iiint': '∭', 'oint': '∮',
  'partial': '∂', 'nabla': '∇', 'infty': '∞', 'hbar': 'ℏ', 'ell': 'ℓ', 'Re': 'ℜ', 'Im': 'ℑ', 'aleph': 'ℵ',
  'angle': '∠', 'perp': '⊥', 'parallel': '∥', 'mid': '∣', 'nmid': '∤', 'top': '⊤', 'bot': '⊥',
  'langle': '⟨', 'rangle': '⟩', 'lceil': '⌈', 'rceil': '⌉', 'lfloor': '⌊', 'rfloor': '⌋', 'vert': '|',
  'Vert': '‖', 'lvert': '|', 'rvert': '|', 'lVert': '‖', 'rVert': '‖', 'prime': '′', 'degree': '°',
  'quad': ' ', 'qquad': '  ', ',': ' ', ';': ' ', ':': ' ', '!': '', ' ': ' ',
  '{': '{', '}': '}', '%': '%', '$': '$', '&': '&', '#': '#', '_': '_', '|': '‖', 'backslash': '\\'
}

/** Rendered upright, like \max or \log. */
const OPERATORS: string[] = ['max', 'min', 'arg', 'argmax', 'argmin', 'log', 'ln', 'exp', 'sin', 'cos', 'tan',
  'sec', 'csc', 'cot', 'sinh', 'cosh', 'tanh', 'lim', 'sup', 'inf', 'det', 'dim', 'ker', 'deg', 'gcd', 'Pr',
  'mod', 'bmod', 'tr', 'Tr', 'diag', 'rank', 'sgn', 'softmax']

const ACCENTS: Record<string, string> = {
  'hat': '̂', 'widehat': '̂', 'bar': '̄', 'overline': '̅', 'tilde': '̃',
  'widetilde': '̃', 'vec': '⃗', 'dot': '̇', 'ddot': '̈', 'check': '̌',
  'acute': '́', 'grave': '̀', 'breve': '̆', 'underline': '̲'
}

/** Ignored wrappers whose argument is shown as is. */
const PASSTHROUGH: string[] = ['mathrm', 'mathit', 'mathsf', 'mathtt', 'textrm', 'textit', 'textbf', 'mathbf',
  'boldsymbol', 'bm', 'text', 'textsf', 'texttt', 'operatorname', 'mbox', 'boxed', 'displaystyle',
  'textstyle', 'underbrace', 'overbrace', 'color', 'textcolor', 'cancel', 'mathbin', 'mathrel', 'mathop']

const SIZING: string[] = ['left', 'right', 'big', 'Big', 'bigg', 'Bigg', 'bigl', 'bigr', 'Bigl', 'Bigr',
  'biggl', 'biggr', 'middle', 'limits', 'nolimits']

function mapAlphabet(s: string, upper: number, lower: number, digit: number, fixes: Record<string, string>): string {
  let out = ''
  for (const ch of s) {
    if (fixes[ch] !== undefined) {
      out += fixes[ch]
    } else if (ch >= 'A' && ch <= 'Z' && upper > 0) {
      out += String.fromCodePoint(upper + ch.charCodeAt(0) - 65)
    } else if (ch >= 'a' && ch <= 'z' && lower > 0) {
      out += String.fromCodePoint(lower + ch.charCodeAt(0) - 97)
    } else if (ch >= '0' && ch <= '9' && digit > 0) {
      out += String.fromCodePoint(digit + ch.charCodeAt(0) - 48)
    } else {
      out += ch
    }
  }
  return out
}

const BB_FIX: Record<string, string> = { 'C': 'ℂ', 'H': 'ℍ', 'N': 'ℕ', 'P': 'ℙ', 'Q': 'ℚ', 'R': 'ℝ', 'Z': 'ℤ' }
const CAL_FIX: Record<string, string> = {
  'B': 'ℬ', 'E': 'ℰ', 'F': 'ℱ', 'H': 'ℋ', 'I': 'ℐ', 'L': 'ℒ', 'M': 'ℳ', 'R': 'ℛ'
}
const FRAK_FIX: Record<string, string> = { 'C': 'ℭ', 'H': 'ℌ', 'I': 'ℑ', 'R': 'ℜ', 'Z': 'ℨ' }

class Parser {
  src: string
  pos: number = 0
  out: TexRun[] = []

  constructor(src: string) {
    this.src = src
  }

  emit(text: string, level: number, italic: boolean): void {
    if (text.length === 0) {
      return
    }
    const last = this.out.length > 0 ? this.out[this.out.length - 1] : null
    if (last !== null && last.level === level && last.italic === italic) {
      last.text += text
      return
    }
    const r = new TexRun()
    r.text = text
    r.level = level
    r.italic = italic
    this.out.push(r)
  }

  /** Reads `{...}` (balanced) or one token; returns raw source. */
  readArg(): string {
    this.skipSpaces()
    if (this.pos >= this.src.length) {
      return ''
    }
    const c = this.src[this.pos]
    if (c === '{') {
      let depth = 0
      const start = this.pos + 1
      for (; this.pos < this.src.length; this.pos++) {
        const ch = this.src[this.pos]
        if (ch === '\\') {
          this.pos++
          continue
        }
        if (ch === '{') {
          depth++
        } else if (ch === '}') {
          depth--
          if (depth === 0) {
            this.pos++
            return this.src.substring(start, this.pos - 1)
          }
        }
      }
      return this.src.substring(start)
    }
    if (c === '\\') {
      const m = new RegExp('^\\\\([a-zA-Z]+|.)').exec(this.src.substring(this.pos))
      const tok = m !== null ? m[0] : '\\'
      this.pos += tok.length
      return tok
    }
    this.pos++
    return c
  }

  readOptional(): void {
    this.skipSpaces()
    if (this.src[this.pos] === '[') {
      const end = this.src.indexOf(']', this.pos)
      this.pos = end > 0 ? end + 1 : this.src.length
    }
  }

  skipSpaces(): void {
    while (this.pos < this.src.length && this.src[this.pos] === ' ') {
      this.pos++
    }
  }

  /** Renders a nested fragment as plain text (used inside accents and fractions). */
  flat(s: string): string {
    return texToRuns(s).map((r: TexRun) => r.text).join('')
  }

  sub(s: string, level: number): void {
    for (const r of texToRuns(s)) {
      this.emit(r.text, level !== 0 ? level : r.level, r.italic)
    }
  }

  parse(level: number): void {
    while (this.pos < this.src.length) {
      const c = this.src[this.pos]
      if (c === '_' || c === '^') {
        this.pos++
        let arg = this.readArg()
        // `_\text{out}` / `^\mathrm{T}`: the argument is the command plus its own argument.
        if (arg.startsWith('\\') && (PASSTHROUGH.includes(arg.substring(1)) || ACCENTS[arg.substring(1)] !== undefined ||
          ['mathbb', 'mathcal', 'mathscr', 'mathfrak', 'sqrt', 'frac'].includes(arg.substring(1)))) {
          const name = arg.substring(1)
          arg = name === 'frac' ? `${arg}{${this.readArg()}}{${this.readArg()}}` : `${arg}{${this.readArg()}}`
        }
        this.sub(arg, c === '_' ? -1 : 1)
        continue
      }
      if (c === '{' || c === '}') {
        this.pos++
        continue
      }
      if (c === '~') {
        this.emit(' ', level, false)
        this.pos++
        continue
      }
      if (c === '&') {
        this.emit('  ', level, false)
        this.pos++
        continue
      }
      if (c === '\\') {
        const m = new RegExp('^\\\\([a-zA-Z]+\\*?|.)').exec(this.src.substring(this.pos))
        if (m === null) {
          this.pos++
          continue
        }
        this.pos += m[0].length
        this.command(m[1].replace('*', ''), level)
        continue
      }
      if (c === "'") {
        this.emit('′', level, false)
        this.pos++
        continue
      }
      const isLetter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      this.emit(c === '-' ? '−' : c, level, isLetter)
      this.pos++
    }
  }

  command(name: string, level: number): void {
    if (name === '\\') {
      this.emit('  ', level, false)
      return
    }
    if (SYMBOLS[name] !== undefined) {
      this.emit(SYMBOLS[name], level, false)
      return
    }
    if (OPERATORS.includes(name)) {
      this.emit(name === 'bmod' ? ' mod ' : name, level, false)
      return
    }
    if (SIZING.includes(name)) {
      this.skipSpaces()
      if (this.src[this.pos] === '.') {
        this.pos++
      }
      return
    }
    if (name === 'frac' || name === 'dfrac' || name === 'tfrac' || name === 'cfrac') {
      const a = this.flat(this.readArg())
      const b = this.flat(this.readArg())
      const wrap = (x: string) => x.length > 1 && new RegExp('[+−\\-*/ ·×=]').test(x) ? `(${x})` : x
      this.emit(`${wrap(a)}/${wrap(b)}`, level, false)
      return
    }
    if (name === 'binom') {
      const a = this.flat(this.readArg())
      const b = this.flat(this.readArg())
      this.emit(`C(${a}, ${b})`, level, false)
      return
    }
    if (name === 'sqrt') {
      this.readOptional()
      const a = this.flat(this.readArg())
      this.emit(a.length > 1 ? `√(${a})` : `√${a}`, level, false)
      return
    }
    if (ACCENTS[name] !== undefined) {
      const a = this.flat(this.readArg())
      // Combine on a single character; otherwise fall back to a postfix mark.
      if (Array.from(a).length === 1) {
        this.emit(a + ACCENTS[name], level, true)
      } else {
        this.emit(name === 'hat' || name === 'widehat' ? `${a}^` : name === 'bar' || name === 'overline' ?
          `‾${a}` : a, level, false)
      }
      return
    }
    if (name === 'mathbb') {
      this.emit(mapAlphabet(this.flat(this.readArg()), 0x1D538, 0x1D552, 0x1D7D8, BB_FIX), level, false)
      return
    }
    if (name === 'mathcal' || name === 'mathscr') {
      this.emit(mapAlphabet(this.flat(this.readArg()), 0x1D49C, 0, 0, CAL_FIX), level, false)
      return
    }
    if (name === 'mathfrak') {
      this.emit(mapAlphabet(this.flat(this.readArg()), 0x1D504, 0x1D51E, 0, FRAK_FIX), level, false)
      return
    }
    if (name === 'begin' || name === 'end') {
      this.readArg()
      return
    }
    if (name === 'color' || name === 'textcolor') {
      this.readArg()
      if (name === 'textcolor') {
        this.sub(this.readArg(), level)
      }
      return
    }
    if (PASSTHROUGH.includes(name)) {
      const arg = this.readArg()
      const textual = name.startsWith('text') || name === 'mbox' || name === 'operatorname' || name === 'mathrm'
      if (textual) {
        this.emit(arg, level, false)
      } else {
        this.sub(arg, level)
      }
      return
    }
    // Unknown command: show its name so nothing silently disappears.
    this.emit(name, level, false)
  }
}

/**
 * Agents write `n_new` meaning n_{new}; strict TeX would subscript only `n`.
 * Brace multi-letter subscripts/superscripts that are not commands.
 */
export function normalizeTex(tex: string): string {
  // Only lowercase words of 3+ letters (new, out, max, prev): `^TA` in `\alpha^TA\alpha`
  // is a product of single-letter matrices and must keep TeX's one-token rule.
  return tex.replace(new RegExp('([_^])([a-z][a-z]{2,})(?![A-Za-z])', 'g'), (m: string, op: string, word: string,
    offset: number, whole: string) => {
    return offset > 0 && whole[offset - 1] === '\\' ? m : `${op}{${word}}`
  })
}

export function texToRuns(tex: string): TexRun[] {
  const p = new Parser(tex.trim())
  p.parse(0)
  return p.out
}
