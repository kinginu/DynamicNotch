#!/usr/bin/env python3
"""Lint the app's Swift sources against the English strings table.

Scans the Swift files compiled into the app (DynamicNotchApp/Sources, including FanControlGlue/,
DynamicNotchApp/App and FanControl/Sources/FanControlUI if present) for string
literals in localized positions:

  - String(localized: "…"), AttributedString(localized: "…"), NSLocalizedString("…"),
    LocalizedStringKey("…"), LocalizedStringResource("…"), `let k: LocalizedStringKey = "…"`;
  - the unlabeled first argument of SwiftUI views/modifiers that take a LocalizedStringKey
    (Text, Button, Label, Toggle, Picker, Section, Menu, TextField, Stepper, LabeledContent, …,
    .help, .accessibilityLabel, .navigationTitle, .alert, …), including both branches of a
    ternary (`Text(on ? "On" : "Off")`);
  - arguments of the project's own functions / initializers / memberwise inits whose parameter
    or stored property is declared as LocalizedStringKey (discovered from the sources).

Interpolated literals ("\\(n) items") are matched against keys with format specifiers
("%lld items"), the way SwiftUI and String.LocalizationValue build the lookup key.

Reports (paths are repo-relative, lines 1-based):
  missing   a localized literal with no entry in the table           (error)
  format    a specifier problem: key/value specifiers differ; a positional key (%1$@) reached
            through interpolation (which only produces %@/%lld, so the lookup misses); an
            interpolation whose obvious type disagrees with the key (String into %lld …);
            String(format:) argument count ≠ specifier count; a specifier in a non-interpolated
            SwiftUI literal (shown verbatim)                         (error)
  stale     Localizable.strings differs from what merge-strings.py would generate (error)
  indirect  a key never used in a localized position but present as a plain literal somewhere,
            e.g. a widget name passed to LocalizedStringKey(widget.name) (info)
  unused    a key that appears in no Swift literal at all            (warning)

Usage (from DynamicNotchApp/):
    python3 -I Support/lint-strings.py              # exit 1 on missing/format/stale
    python3 -I Support/lint-strings.py --strict     # unused keys also fail
    python3 -I Support/lint-strings.py --indirect   # also list indirect keys
Static analysis only: keys built at run time are reported as indirect/unused, and literals
returned from computed properties typed LocalizedStringKey are not seen as localized.
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ROOT = os.path.dirname(APP)

# Compiled into the app target: localized lookups resolve against Localization/en.lproj.
APP_SOURCE_DIRS = ["DynamicNotchApp/Sources", "DynamicNotchApp/App", "FanControl/Sources/FanControlUI"]
# Scanned only for plain literals (keys that reach NSLocalizedString(variable) indirectly,
# e.g. SensorCatalog labels in FanControlCore).
REFERENCE_DIRS = ["FanControl/Sources"]

# SwiftUI initializers / functions whose unlabeled first argument is a LocalizedStringKey
# (or that forward a literal to one).
FIRST_ARG_CALLEES = {
    "Text", "Button", "Label", "Toggle", "Picker", "Section", "Menu", "TextField", "SecureField",
    "Stepper", "LabeledContent", "GroupBox", "DisclosureGroup", "Link", "ContentUnavailableView",
    "NavigationLink", "ProgressView", "ControlGroup", "Tab", "DatePicker", "ColorPicker",
    "ShareLink", "TableColumn", "CommandMenu", "Window", "WindowGroup", "MenuBarExtra", "Slider",
    "LocalizedStringKey", "LocalizedStringResource", "NSLocalizedString",
    ".help", ".accessibilityLabel", ".accessibilityHint", ".accessibilityValue",
    ".navigationTitle", ".navigationSubtitle", ".badge", ".alert", ".confirmationDialog",
}
# (callee, label) pairs that take a localized literal.
LABELED_CALLEES = {
    ("String", "localized"), ("AttributedString", "localized"),
    (".searchable", "prompt"), (".accessibilityAction", "named"),
}
# Callees where a literal containing a specifier but no interpolation is displayed verbatim.
SWIFTUI_VERBATIM_RISK = FIRST_ARG_CALLEES - {"LocalizedStringResource", "NSLocalizedString"}

LSK_TYPES = {"LocalizedStringKey", "LocalizedStringResource"}
TYPE_DECL = {"struct", "class", "enum", "extension", "actor", "protocol"}

# printf-style specifiers as they appear in keys (%@, %lld, %1$@, %.1f, %%). The space and '
# flags are left out on purpose: "20% or less" is prose, not "% o".
SPEC_RE = re.compile(r"%(?:(\d+)\$)?[-+#0]*(?:\d+)?(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp])|%%")


def load_generator():
    spec = importlib.util.spec_from_file_location("merge_strings", os.path.join(HERE, "merge-strings.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------------------------
# A small Swift lexer: identifiers, punctuation, string literals (with interpolations lexed
# recursively), comments skipped.

class Tok:
    __slots__ = ("kind", "text", "line", "parts")

    def __init__(self, kind, text, line, parts=None):
        self.kind, self.text, self.line, self.parts = kind, text, line, parts

    def __repr__(self):
        return f"{self.kind}:{self.text!r}@{self.line}"


class Interp:
    """An interpolation segment: its tokens (one argument list, without the parentheses)."""
    __slots__ = ("tokens",)

    def __init__(self, tokens):
        self.tokens = tokens


_SIMPLE_ESC = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}
_ID_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUM_RE = re.compile(r"[0-9][0-9A-Za-z_.]*")


class Lexer:
    def __init__(self, src, path):
        self.s, self.path, self.i, self.line = src, path, 0, 1

    def error(self, msg):
        raise SyntaxError(f"{self.path}:{self.line}: {msg}")

    def lex(self, stop_on_close=False):
        """Lex tokens; with stop_on_close, stop at the unmatched ')' (consumed)."""
        s, toks, depth = self.s, [], 0
        n = len(s)
        while self.i < n:
            c = s[self.i]
            if c == "\n":
                self.line += 1
                self.i += 1
            elif c.isspace():
                self.i += 1
            elif s.startswith("//", self.i):
                j = s.find("\n", self.i)
                self.i = n if j < 0 else j
            elif s.startswith("/*", self.i):
                self.skip_block_comment()
            elif c == '"' or (c == "#" and re.match(r'#+"', s[self.i:self.i + 8])):
                toks.append(self.string())
            elif c == "`":
                j = s.find("`", self.i + 1)
                toks.append(Tok("id", s[self.i + 1:j], self.line))
                self.i = j + 1
            elif _ID_RE.match(s, self.i):
                m = _ID_RE.match(s, self.i)
                toks.append(Tok("id", m.group(0), self.line))
                self.i = m.end()
            elif c.isdigit():
                m = _NUM_RE.match(s, self.i)
                toks.append(Tok("num", m.group(0), self.line))
                self.i = m.end()
            else:
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    if depth == 0 and stop_on_close and c == ")":
                        self.i += 1
                        return toks
                    depth -= 1
                toks.append(Tok("p", c, self.line))
                self.i += 1
        if stop_on_close:
            self.error("unterminated interpolation")
        return toks

    def skip_block_comment(self):
        s, depth = self.s, 0
        while self.i < len(s):
            if s.startswith("/*", self.i):
                depth += 1
                self.i += 2
            elif s.startswith("*/", self.i):
                depth -= 1
                self.i += 2
                if depth == 0:
                    return
            else:
                if s[self.i] == "\n":
                    self.line += 1
                self.i += 1
        self.error("unterminated comment")

    def string(self):
        s, start_line = self.s, self.line
        hashes = 0
        while s[self.i] == "#":
            hashes += 1
            self.i += 1
        multiline = s.startswith('"""', self.i)
        self.i += 3 if multiline else 1
        close = ('"""' if multiline else '"') + "#" * hashes
        esc = "\\" + "#" * hashes
        parts, buf = [], []
        while True:
            if self.i >= len(s):
                self.error("unterminated string literal")
            if s.startswith(close, self.i):
                self.i += len(close)
                break
            c = s[self.i]
            if c == "\n":
                if not multiline:
                    self.error("newline in string literal")
                self.line += 1
            if s.startswith(esc, self.i):
                self.i += len(esc)
                e = s[self.i]
                if e == "(":
                    self.i += 1
                    if buf:
                        parts.append("".join(buf))
                        buf = []
                    parts.append(Interp(self.lex(stop_on_close=True)))
                    continue
                if e == "u" and s[self.i + 1] == "{":
                    j = s.index("}", self.i)
                    buf.append(chr(int(s[self.i + 2:j], 16)))
                    self.i = j + 1
                    continue
                if e == "\n" and multiline:  # line continuation
                    self.line += 1
                    self.i += 1
                    continue
                buf.append(_SIMPLE_ESC.get(e, e))
                self.i += 1
                continue
            buf.append(c)
            self.i += 1
        if buf:
            parts.append("".join(buf))
        if multiline:
            parts = dedent_multiline(parts)
        return Tok("str", None, start_line, parts)


def dedent_multiline(parts):
    """Best-effort Swift multi-line literal semantics: drop the first newline, the last line's
    indentation (the closing delimiter's) from every line, and the final newline."""
    text = "".join(p if isinstance(p, str) else "\x01" for p in parts)
    lines = text.split("\n")
    if lines and lines[0].strip() == "":
        lines = lines[1:]
    indent = lines[-1] if lines and lines[-1].strip() == "" else ""
    if lines and lines[-1].strip() == "":
        lines = lines[:-1]
    lines = [ln[len(indent):] if ln.startswith(indent) else ln for ln in lines]
    joined, interps, out, k = "\n".join(lines), [p for p in parts if isinstance(p, Interp)], [], 0
    for seg in joined.split("\x01"):
        if seg:
            out.append(seg)
        if k < len(interps):
            out.append(interps[k])
            k += 1
    while k < len(interps):
        out.append(interps[k])
        k += 1
    return [p for p in out if not (isinstance(p, str) and p == "")] or []


# ---------------------------------------------------------------------------------------------
# Literal analysis

SLOT = "\x00"


def lit_text(tok):
    """(text, slots): text with SLOT for each interpolation; slots = [Interp, …]."""
    out, slots = [], []
    for p in tok.parts:
        if isinstance(p, Interp):
            out.append(SLOT)
            slots.append(p)
        else:
            out.append(p)
    return "".join(out), slots


def key_template(key):
    """Key -> (template, [spec, …]) with SLOT per specifier and '%%' -> '%'."""
    specs, out, pos = [], [], 0
    for m in SPEC_RE.finditer(key):
        out.append(key[pos:m.start()])
        if m.group(0) == "%%":
            out.append("%")
        else:
            out.append(SLOT)
            specs.append(m)
        pos = m.end()
    out.append(key[pos:])
    return "".join(out), specs


def spec_class(m):
    conv = m.group(3)
    if conv == "@":
        return "object"
    if conv in "dDiuUxXoOcC":
        return "int"
    if conv in "fFeEgGaA":
        return "float"
    return "other"


def spec_signature(s):
    return sorted(m.group(0) for m in SPEC_RE.finditer(s) if m.group(0) != "%%")


def interp_class(interp):
    """Guess the interpolated value's class from obvious syntax, or None."""
    toks = interp.tokens
    if not toks:
        return None
    # \(x, specifier: "%.1f") / \(x, format: …) / \(x, style: …)
    for k in range(len(toks) - 2):
        if toks[k].kind == "p" and toks[k].text == "," and toks[k + 1].kind == "id" and toks[k + 2].text == ":":
            label = toks[k + 1].text
            if label == "specifier" and k + 3 < len(toks) and toks[k + 3].kind == "str":
                m = SPEC_RE.search("".join(p for p in toks[k + 3].parts if isinstance(p, str)))
                return spec_class(m) if m else None
            if label in ("format", "style", "formatter"):
                return "object"
            return None
    if len(toks) == 1 and toks[0].kind == "str":
        return "object"
    first = toks[0].text if toks[0].kind == "id" else None
    if first == "String" and len(toks) > 1 and toks[1].text == "(":
        return "object"
    if first in ("Int", "Int64", "Int32", "UInt") and len(toks) > 1 and toks[1].text == "(":
        return "int"
    if first in ("Double", "Float", "CGFloat") and len(toks) > 1 and toks[1].text == "(":
        return "float"
    # trailing member: x.count, x.formatted(…), x.description
    j = len(toks) - 1
    if toks[j].text == ")":
        depth = 0
        while j >= 0:
            if toks[j].text == ")":
                depth += 1
            elif toks[j].text == "(":
                depth -= 1
                if depth == 0:
                    break
            j -= 1
        j -= 1
    if j >= 1 and toks[j].kind == "id" and toks[j - 1].text == ".":
        member = toks[j].text
        if member == "count":
            return "int"
        if member in ("formatted", "description", "uppercased", "lowercased", "capitalized",
                      "localizedCapitalized", "localizedUppercase", "localizedDescription"):
            return "object"
    return None


def enclosing_call(toks, i):
    """For toks[i], return (opener_idx, callee, arg_index, label, arg_start) or None."""
    depth, arg_index, arg_start, j = 0, 0, None, i - 1
    while j >= 0:
        t = toks[j]
        if t.kind == "p":
            if t.text in ")]}":
                depth += 1
            elif t.text in "([{":
                if depth == 0:
                    if arg_start is None:
                        arg_start = j + 1
                    if t.text != "(":
                        return None
                    break
                depth -= 1
            elif t.text == "," and depth == 0:
                if arg_start is None:
                    arg_start = j + 1
                arg_index += 1
            elif t.text == ";" and depth == 0:
                return None
        j -= 1
    if j < 0:
        return None
    callee = None
    if j >= 1 and toks[j - 1].kind == "id":
        callee = toks[j - 1].text
        if j >= 2 and toks[j - 2].text == ".":
            callee = "." + callee  # member call or modifier: .help(…), x.alert(…)
    label = None
    if arg_start is not None and arg_start + 1 < len(toks) and toks[arg_start].kind == "id" \
            and toks[arg_start + 1].text == ":" and arg_start + 1 < i:
        label = toks[arg_start].text
    return j, callee, arg_index, label, arg_start


def arg_end(toks, start):
    depth, k = 0, start
    while k < len(toks):
        t = toks[k]
        if t.kind == "p":
            if t.text in "([{":
                depth += 1
            elif t.text in ")]}":
                if depth == 0:
                    return k
                depth -= 1
            elif t.text == "," and depth == 0:
                return k
        k += 1
    return k


def is_direct_value(toks, i, arg_start, label):
    """True if toks[i] is the whole argument, or a branch of a top-level ternary in it."""
    start = arg_start + 2 if label else arg_start
    end = arg_end(toks, start)
    seg = toks[start:end]
    if len(seg) == 1:
        return True
    texts = [t.text if t.kind == "p" else None for t in seg]
    pos = i - start
    # nil-coalescing (a ?? "b"), concatenation, member access on the literal → String context
    for k in range(len(seg) - 1):
        if texts[k] == "?" and texts[k + 1] == "?":
            return False
    if "+" in texts or (pos + 1 < len(seg) and texts[pos + 1] in (".", "(")):
        return False
    if "?" not in texts:
        return False
    q = texts.index("?")
    if pos <= q:
        return False
    before, after = texts[pos - 1], (texts[pos + 1] if pos + 1 < len(seg) else None)
    return before in ("?", ":") and after in (None, ":")


class Usage:
    __slots__ = ("path", "line", "text", "slots", "callee", "localized", "fmt_args")

    def __init__(self, path, line, text, slots, callee, localized, fmt_args=None):
        self.path, self.line, self.text, self.slots = path, line, text, slots
        self.callee, self.localized, self.fmt_args = callee, localized, fmt_args

    @property
    def where(self):
        return f"{self.path}:{self.line}"


def discover_lsk_params(files_tokens):
    """Find the project's own APIs that take LocalizedStringKey.
    Returns (by_position {(callee, index)}, by_label {(callee, label)})."""
    by_pos, by_label = set(), set()

    def is_lsk(toks, k):
        return k < len(toks) and toks[k].kind == "id" and toks[k].text in LSK_TYPES

    for toks in files_tokens:
        type_stack, pending, depth = [], None, 0
        for k, t in enumerate(toks):
            if t.kind == "id" and t.text in TYPE_DECL and k + 1 < len(toks) and toks[k + 1].kind == "id":
                pending = toks[k + 1].text
            elif t.kind == "p" and t.text == "{":
                depth += 1
                if pending:
                    type_stack.append((pending, depth))
                    pending = None
            elif t.kind == "p" and t.text == "}":
                if type_stack and type_stack[-1][1] == depth:
                    type_stack.pop()
                depth -= 1
            # stored property directly in a type body: var/let name: LocalizedStringKey
            if t.kind == "id" and t.text in ("var", "let") and type_stack and type_stack[-1][1] == depth \
                    and k + 3 < len(toks) and toks[k + 1].kind == "id" and toks[k + 2].text == ":" \
                    and is_lsk(toks, k + 3):
                # computed properties ({ … } after the type) are not memberwise-init parameters
                nxt = toks[k + 4] if k + 4 < len(toks) else None
                nxt2 = toks[k + 5] if k + 5 < len(toks) else None
                computed = nxt is not None and nxt.text == "{" or (nxt is not None and nxt.text == "?" and nxt2 is not None and nxt2.text == "{")
                if not computed:
                    by_label.add((type_stack[-1][0], toks[k + 1].text))
            # func name(…) / init(…)
            if t.kind == "id" and t.text in ("func", "init") and k + 1 < len(toks):
                if t.text == "func":
                    if toks[k + 1].kind != "id":
                        continue
                    name, p = toks[k + 1].text, k + 2
                else:
                    if not type_stack:
                        continue
                    name, p = type_stack[-1][0], k + 1
                    if p < len(toks) and toks[p].text in ("?", "!"):
                        p += 1
                if p < len(toks) and toks[p].text == "<":  # generics
                    d = 0
                    while p < len(toks):
                        if toks[p].text == "<":
                            d += 1
                        elif toks[p].text == ">":
                            d -= 1
                            if d == 0:
                                p += 1
                                break
                        p += 1
                if p >= len(toks) or toks[p].text != "(":
                    continue
                for index, (start, stop) in enumerate(call_args(toks, p)):
                    seg = toks[start:stop]
                    colon = next((q for q, x in enumerate(seg) if x.text == ":"), None)
                    if colon is not None and colon + 1 < len(seg) and seg[colon + 1].text in LSK_TYPES:
                        names = [x.text for x in seg[:colon] if x.kind == "id"]
                        ext = names[0] if names else None
                        if ext == "_" or ext is None:
                            by_pos.add((name, index))
                        else:
                            by_label.add((name, ext))
    return by_pos, by_label


def scan_stream(toks, path, out, ctx):
    for i, t in enumerate(toks):
        if t.kind != "str":
            continue
        text, slots = lit_text(t)
        for s in slots:
            scan_stream(s.tokens, path, out, ctx)
        localized, callee, fmt_args = False, None, None
        prev = toks[i - 1] if i > 0 else None
        prev2 = toks[i - 2] if i > 1 else None
        if prev is not None and prev.text == "=" and prev2 is not None and (
                prev2.text in LSK_TYPES or (prev2.text == "?" and i > 2 and toks[i - 3].text in LSK_TYPES)):
            localized, callee = True, prev2.text if prev2.text in LSK_TYPES else toks[i - 3].text
        else:
            enc = enclosing_call(toks, i)
            if enc:
                opener, callee, index, label, arg_start = enc
                bare = callee.lstrip(".") if callee else None
                if label is None and index == 0 and callee in FIRST_ARG_CALLEES:
                    localized = is_direct_value(toks, i, arg_start, None)
                elif (callee, label) in LABELED_CALLEES:
                    localized = is_direct_value(toks, i, arg_start, label)
                    if localized and "table" in call_labels(toks, opener):
                        localized = False  # String(localized:table:) — another table, not ours
                elif bare and ((label is None and (bare, index) in ctx["by_pos"])
                               or (label is not None and (bare, label) in ctx["by_label"])):
                    localized = is_direct_value(toks, i, arg_start, label)
                if localized and callee in ("NSLocalizedString", "String") and not slots:
                    fmt_args = format_arg_count(toks, opener)
        out.append(Usage(path, t.line, text, slots, callee, localized, fmt_args))


def call_args(toks, opener):
    """[(start, end)] token ranges of the arguments of the call whose '(' is toks[opener]."""
    out, k = [], opener + 1
    if k < len(toks) and toks[k].text == ")":
        return out
    while k < len(toks):
        e = arg_end(toks, k)
        out.append((k, e))
        if e >= len(toks) or toks[e].text != ",":
            break
        k = e + 1
    return out


def call_labels(toks, opener):
    return {toks[a].text for a, e in call_args(toks, opener)
            if e - a >= 2 and toks[a].kind == "id" and toks[a + 1].text == ":"}


def format_arg_count(toks, opener):
    """If the call whose '(' is toks[opener] is the `format:` argument of String(format:…),
    return the number of format arguments passed after it, else None."""
    enc = enclosing_call(toks, opener - 1)
    if not enc:
        return None
    o, callee, _, label, _ = enc
    if callee != "String" or label != "format":
        return None
    return len(call_args(toks, o)) - 1


def iter_swift(dirs):
    for d in dirs:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(x for x in dirnames if x not in (".build", "Tests"))
            for f in sorted(filenames):
                if f.endswith(".swift"):
                    yield os.path.join(dirpath, f)


def lex_file(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    return Lexer(src, os.path.relpath(path, ROOT)).lex()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Lint Swift string usage against Localizable.strings.")
    ap.add_argument("--strict", action="store_true", help="unused keys are errors too")
    ap.add_argument("--indirect", action="store_true", help="list keys used only indirectly")
    args = ap.parse_args(argv)

    gen = load_generator()
    try:
        entries, origins = gen.collect()
    except gen.StringsError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    stale = False
    try:
        with open(gen.OUT_PATH, encoding="utf-8") as f:
            stale = f.read() != gen.render(entries)
    except OSError:
        stale = True

    app_files = list(dict.fromkeys(iter_swift(APP_SOURCE_DIRS)))
    ref_files = [p for p in dict.fromkeys(iter_swift(REFERENCE_DIRS)) if p not in app_files]
    app_tokens = {p: lex_file(p) for p in app_files}
    ref_tokens = {p: lex_file(p) for p in ref_files}
    by_pos, by_label = discover_lsk_params(app_tokens.values())
    ctx = {"by_pos": by_pos, "by_label": by_label}

    usages = []
    for p, toks in list(app_tokens.items()) + list(ref_tokens.items()):
        local = []
        scan_stream(toks, os.path.relpath(p, ROOT), local, ctx)
        if p in ref_tokens:
            for u in local:
                u.localized = False
        usages.extend(local)

    templates = {}
    for k in entries:
        tpl, specs = key_template(k)
        if specs:
            templates.setdefault(tpl, []).append((k, specs))

    def resolve(u):
        """Return (matched keys, problems)."""
        if not u.slots:
            return ([u.text] if u.text in entries else []), []
        cands = templates.get(u.text, [])
        problems = []
        for key, specs in cands:
            if any(m.group(1) for m in specs):
                problems.append(f"interpolation looks up a non-positional key, but the table has {key!r}")
            for slot, m in zip(u.slots, specs):
                got = interp_class(slot)
                want = spec_class(m)
                if got and want != "other" and got != want:
                    problems.append(f"{key!r}: {m.group(0)} is fed an interpolated {got} value")
        return [k for k, _ in cands], problems

    missing, fmt_problems, used = [], [], {}
    plain_refs = {}
    for u in usages:
        keys, problems = resolve(u)
        if u.localized:
            if not keys and re.search(r"[A-Za-z]", u.text.replace(SLOT, "")):
                missing.append(u)
            for pr in problems:
                fmt_problems.append((u.where, pr))
            for k in keys:
                used.setdefault(k, u)
            if not u.slots and u.callee in SWIFTUI_VERBATIM_RISK and spec_signature(u.text):
                fmt_problems.append((u.where, f"{u.text!r} has a format specifier but no interpolation; "
                                              f"{u.callee} shows it verbatim"))
            if u.fmt_args is not None:
                specs = [m for m in SPEC_RE.finditer(u.text) if m.group(0) != "%%"]
                need = max([int(m.group(1)) for m in specs if m.group(1)] + [0]) or len(specs)
                if need != u.fmt_args:
                    fmt_problems.append((u.where, f"{u.text!r} needs {need} argument(s), "
                                                  f"String(format:) passes {u.fmt_args}"))
        else:
            for k in keys:
                plain_refs.setdefault(k, u)
    for k, v in entries.items():
        if spec_signature(k) != spec_signature(v):
            fmt_problems.append((", ".join(origins[k]), f"key {k!r} and value {v!r} have different specifiers"))

    indirect = sorted((k, plain_refs[k]) for k in entries if k not in used and k in plain_refs)
    unused = sorted(k for k in entries if k not in used and k not in plain_refs)

    def shown(text):
        return text.replace(SLOT, "\\(…)")

    def section(title, rows):
        print(f"\n== {title} ({len(rows)})")
        for r in rows:
            print(f"  {r}")

    n_loc = sum(1 for u in usages if u.localized)
    print(f"{len(entries)} keys; {len(app_files)} app Swift files, {len(ref_files)} reference files; "
          f"{n_loc} localized literals, {len(used)} keys used directly")
    if stale:
        print(f"\n== stale: {gen.rel(gen.OUT_PATH)} is out of date; run python3 -I Support/merge-strings.py")
    section("missing: localized literal without a key",
            [f"{u.where}: {shown(u.text)!r}" for u in
             sorted(missing, key=lambda u: (u.path, u.line))])
    section("format: specifier problems", [f"{w}: {p}" for w, p in sorted(set(fmt_problems))])
    if args.indirect:
        section("indirect: key only seen as a plain literal (dynamic lookup)",
                [f"{k!r} — {u.where}" for k, u in indirect])
    else:
        print(f"\n== indirect: {len(indirect)} keys only seen as plain literals (dynamic lookups); "
              f"list them with --indirect")
    section("unused: key in no Swift literal", [f"{k!r} ({', '.join(origins[k])})" for k in unused])

    failed = stale or missing or fmt_problems or (args.strict and unused)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
