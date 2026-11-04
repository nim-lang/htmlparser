discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
  output: "ok"
"""
import std/[strutils, streams, unicode, xmltree]
import ../../src/htmlparser
import ../../src/htmlparser/entitydata {.all.}

func reference(name: string): Rune =
  ## Independent oracle: `entityTable` is sorted by name.
  var lo = 0
  var hi = entityTable.high
  while lo <= hi:
    let mid = (lo + hi) div 2
    let c = cmp(entityTable[mid][0], name)
    if c == 0: return Rune(entityTable[mid][1])
    elif c < 0: lo = mid + 1
    else: hi = mid - 1
  Rune(0)

func legacyNumeric(entity: string): Rune =
  ## The pre-rewrite numeric parser, kept as a behavioral oracle.
  if entity.len < 2: return Rune(0)
  if entity[0] == '#':
    var value = 0
    case entity[1]
    of '0'..'9':
      try: value = parseInt(entity[1..^1])
      except ValueError: discard
    of 'x', 'X':
      try: value = parseHexInt(entity[2..^1])
      except ValueError: discard
    else: discard
    if value notin 0..0x10FFFF: value = 0
    return Rune(value)
  Rune(0)

func matches(input: string; value: uint32): bool =
  ## Checks both overloads against a code point.
  let rune = Rune(value)
  entityToRune(input) == rune and
    entityToRune(input.toOpenArray(0, input.high)) == rune

func matchesUtf8(input: string; value: uint32): bool =
  let text = if value == 0: "" else: toUTF8(Rune(value))
  entityToUtf8(input) == text and
    entityToUtf8(input.toOpenArray(0, input.high)) == text

block named:
  for (name, value) in entityTable:
    doAssert matches(name, value), name
    doAssert matchesUtf8(name, value), name
    doAssert entityToRune(name) == reference(name), name

const numeric = [
  ("#65", 65'u32), ("#065", 65'u32),
  ("#x41", 65'u32), ("#X41", 65'u32), ("#x0003F", 63'u32),
  ("#9", 9'u32), ("#0", 0'u32), ("#x0", 0'u32), ("#x", 0'u32),
  ("#", 0'u32), ("#x110000", 0'u32), ("#1114112", 0'u32),
  ("#xD800", 0xD800'u32), ("#x10FFFF", 0x10FFFF'u32),
  # Grammar quirks preserved from strutils.parseInt/parseHexInt.
  ("#1_", 1'u32), ("#1__2", 12'u32), ("#x4_1", 65'u32),
  ("#x_41", 65'u32), ("#x0x41", 65'u32), ("#x#41", 65'u32),
  ("#+1", 0'u32), ("#-1", 0'u32), ("# 1", 0'u32), ("#1 ", 0'u32),
  ("#x+41", 0'u32), ("#x41G", 0'u32)]

for (input, value) in numeric:
  doAssert matches(input, value), input
  doAssert matchesUtf8(input, value), input
  doAssert entityToRune(input) == legacyNumeric(input), input

block legacyNumeric:
  ## Compare all small numeric values against the old parser.
  for i in 0 .. 0x2000:
    for form in ["#" & $i, "#" & align($i, 6, '0'),
                 "#x" & toHex(i, 1), "#X" & toHex(i, 1).toUpperAscii]:
      let expected = legacyNumeric(form)
      doAssert matches(form, uint32(expected.ord)), form
      doAssert entityToRune(form) == expected, form
  for form in ["#2147483648", "#999999999999999999999",
               "#xFFFFFFFF", "#xFFFFFFFFFFFFFFFF",
               "#x10000000000000000", "#x0x41", "#x#41",
               "#1_", "#1__2", "#x4_1", "#x_41"]:
    doAssert entityToRune(form) == legacyNumeric(form), form

block parser:
  let tree = parseHtml(newStringStream("<p>&amp;&#65;&#x42;&Uuml;</p>"))
  doAssert tree.innerText == "&ABÜ"

block unknown:
  for s in ["", "a", "ampx", "AMP;", "notanentity", "Uum", "\0", "ä"]:
    doAssert entityToRune(s) == Rune(0), s
    doAssert entityToUtf8(s) == "", s

block api:
  ## The historical `htmlparser` symbols remain exported.
  let rune: proc(entity: string): Rune {.raises: [].} = entityToRune
  let utf8: proc(entity: string): string {.raises: [].} = entityToUtf8
  doAssert rune("amp") == Rune(38)
  doAssert utf8("amp") == "&"

static:
  # The lookup must also evaluate in the compiler VM.
  doAssert entityToRune("amp") == Rune(38)
  doAssert entityToRune("#65") == Rune(65)
  doAssert entityToUtf8("amp") == "&"

echo "ok"
