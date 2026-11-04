## Lookup of HTML named character references and numeric references.
##
## `entityToRune` converts an entity body (`"amp"`, `"Uuml"`, `"#65"`,
## `"#x41"`) to a `Rune`, or `Rune(0)` when it is unknown. `entityToUtf8`
## returns the UTF-8 text, or `""` when it is unknown. Names are
## case-sensitive and do not include the leading `&` or the trailing `;`.
##
## Both procs accept a `string` and an `openArray[char]` view. View
## overload avoids copying when the caller already has a slice.
##
## The checked-in table reproduces the values shipped before the generated
## lookup. See `tools/gen_entitydata.nims` for the data source and for the
## differences from the current spec.
##
## Data and lookup
## ===============
##
## `buildEntityTables` turns the checked-in table into immutable tables
## at compile time: a 4,096-slot open-addressed table, a concatenated name
## pool, the distinct code-point values, and a 256-entry associated-values
## table. The lookup uses a gperf-style hash over the length and the first,
## second and last byte, with linear probing and a full name comparison.
##
## Numeric forms
## =============
##
## Decimal and hexadecimal forms are parsed directly from the input view on
## Nim 2.x. The Nim 1.6 fallback copies the short numeric slice. The grammar
## matches the previous implementation: underscores are allowed, hex accepts
## optional `0x` and `#` prefixes, signs are not accepted where the old code
## rejected them, and the full input must be consumed. Values outside
## `0 .. 0x10FFFF` (including overflow) become `Rune(0)`. Numeric zero is
## also `Rune(0)`, matching the old API.
##
## The tables are immutable, so lookup is thread-safe. `entityToUtf8`
## allocates its result string.

import std/[macros, parseutils, tables, unicode]
import ./entitydata {.all.}

const
  EntitySlotCount = 4096
    ## Power of two; keeps the load factor at 0.50.
  EntitySlotMask = EntitySlotCount - 1
  EntityEmptySlot = 0xFFFF_FFFF'u32
    ## No entry uses all bits set.
  EntityOffsetBits = 15
    ## Name-pool offsets stay below 32 KiB.
  EntityLengthBits = 5
    ## The longest name is 31 bytes.
  EntityValueBits = 12
    ## There are 1,448 distinct code points.
  EntityMaxCodePoint = 0x10FFFF
  EntityAssoSeed = 0x75BC_D15'u32
    ## Fixed so generated tables stay reproducible.
  EntityAssoMultiplier = 1_664_525'u32
  EntityAssoIncrement = 1_013_904_223'u32
  EntityHashMultiplier = 0x9E37_79B1'u32
    ## Mixes the length into the tabulation hash.

static:
  # Keep probe chains short. 0.6 leaves headroom for the complete
  # two-code-point set.
  doAssert entityTable.len <= EntitySlotCount * 3 div 5,
    "entity table load exceeds 0.6; increase EntitySlotCount"

func nameHash(entity: openArray[char]; asso: openArray[uint32]): uint32 =
  ## Hashes the length and the first, second and last byte of `entity`.
  ## Requires `entity.len >= 2`.
  result = uint32(entity.len) * EntityHashMultiplier
  result += asso[int(uint8(entity[0]))]
  result += asso[int(uint8(entity[1]))]
  result += asso[int(uint8(entity[entity.high]))]

macro buildEntityTables(data: static[openArray[(string, uint32)]]): untyped =
  ## Builds `(pool, slots, values, asso)` from `data`.
  var asso = newSeq[uint32](256)
  var state = EntityAssoSeed
  for i in 0 ..< asso.len:
    state = state * EntityAssoMultiplier + EntityAssoIncrement
    asso[i] = state

  var slots = newSeq[uint32](EntitySlotCount)
  for i in 0 ..< slots.len:
    slots[i] = EntityEmptySlot

  var
    pool: string
    values: seq[uint32]
    valueIds = initTable[uint32, int]()

  for (name, value) in data:
    let
      offset = pool.len
      length = name.len
    doAssert length >= 2, "entity names are at least two bytes"
    doAssert offset < (1 shl EntityOffsetBits), "entity pool overflow"
    doAssert length <= (1 shl EntityLengthBits) - 1, "entity name too long"

    var valueId: int
    if value in valueIds:
      valueId = valueIds[value]
    else:
      valueId = values.len
      valueIds[value] = valueId
      values.add value
    doAssert valueId < (1 shl EntityValueBits), "too many entity values"

    pool.add name
    let packed = uint32(offset) or
                 (uint32(length) shl EntityOffsetBits) or
                 (uint32(valueId) shl (EntityOffsetBits + EntityLengthBits))
    var slot = int(nameHash(name, asso) and uint32(EntitySlotMask))
    while slots[slot] != EntityEmptySlot:
      slot = (slot + 1) and EntitySlotMask
    slots[slot] = packed

  var slotLiterals = newNimNode(nnkBracket)
  for slot in slots:
    slotLiterals.add newLit(slot)
  var valueLiterals = newNimNode(nnkBracket)
  for value in values:
    valueLiterals.add newLit(value)
  var assoLiterals = newNimNode(nnkBracket)
  for value in asso:
    assoLiterals.add newLit(value)

  result = newNimNode(nnkTupleConstr)
  result.add newColonExpr(ident"pool", newLit(pool))
  result.add newColonExpr(ident"slots", slotLiterals)
  result.add newColonExpr(ident"values", valueLiterals)
  result.add newColonExpr(ident"asso", assoLiterals)

const
  entityTables = buildEntityTables(entityTable)
  EntityPool = entityTables.pool
  EntitySlots = entityTables.slots
  EntityValues = entityTables.values
  EntityAsso = entityTables.asso

func poolEquals(entity: openArray[char]; offset, length: int): bool =
  ## Compares `entity` with a name in `EntityPool`.
  when nimvm:
    for i in 0 ..< length:
      if entity[i] != EntityPool[offset + i]: return false
    true
  else:
    when defined(js):
      for i in 0 ..< length:
        if entity[i] != EntityPool[offset + i]: return false
      true
    else:
      equalMem(unsafeAddr entity[0],
               cast[pointer](cast[uint](EntityPool.cstring) + uint(offset)),
               length)

func numericToRune(entity: openArray[char]): Rune =
  ## Decodes `#decimal` and `#xhex` with the historical grammar.
  ## `entity.len >= 2` and `entity[0] == '#'` are guaranteed by the caller.
  var value = 0
  case entity[1]
  of '0'..'9':
    when (NimMajor, NimMinor) >= (2, 0):
      let consumed = parseSaturatedNatural(
        entity.toOpenArray(1, entity.high), value)
      if consumed != entity.len - 1 or consumed == 0:
        value = 0
    else:
      # Nim 1.6's parseutils has no openArray overloads.
      var text = newString(entity.len - 1)
      for i in 0 ..< text.len: text[i] = entity[i + 1]
      try:
        let consumed = parseutils.parseInt(text, value)
        if consumed != text.len or consumed == 0: value = 0
      except ValueError:
        value = 0
  of 'x', 'X':
    if entity.len <= 2: return Rune(0)
    when (NimMajor, NimMinor) >= (2, 0):
      let consumed = parseHex(entity.toOpenArray(2, entity.high), value)
      if consumed != entity.len - 2 or consumed == 0:
        value = 0
    else:
      var text = newString(entity.len - 2)
      for i in 0 ..< text.len: text[i] = entity[i + 2]
      try:
        let consumed = parseutils.parseHex(text, value)
        if consumed != text.len or consumed == 0: value = 0
      except ValueError:
        value = 0
  else:
    return Rune(0)
  if value notin 0 .. EntityMaxCodePoint:
    value = 0
  Rune(value)

func entityToRune*(entity: openArray[char]): Rune {.raises: [].} =
  ## Converts an entity body to a `Rune`. Returns `Rune(0)` when unknown.
  ##
  ## See the `string` overload for the accepted forms.
  runnableExamples:
    import std/unicode
    let buffer = "&amp;"
    doAssert entityToRune(buffer.toOpenArray(1, 3)) == Rune('&')

  if entity.len < 2: return Rune(0)
  if entity[0] == '#':
    return numericToRune(entity)

  var slot = int(nameHash(entity, EntityAsso) and uint32(EntitySlotMask))
  while true:
    let packed = EntitySlots[slot]
    if packed == EntityEmptySlot:
      return Rune(0)
    let
      offset = int(packed and ((1'u32 shl EntityOffsetBits) - 1))
      length = int((packed shr EntityOffsetBits) and
                   ((1'u32 shl EntityLengthBits) - 1))
      valueId = int((packed shr (EntityOffsetBits + EntityLengthBits)) and
                    ((1'u32 shl EntityValueBits) - 1))
    if length == entity.len and poolEquals(entity, offset, length):
      return Rune(EntityValues[valueId])
    slot = (slot + 1) and EntitySlotMask

func entityToRune*(entity: string): Rune {.raises: [].} =
  ## Converts an entity body to a `Rune`. Returns `Rune(0)` when unknown.
  ##
  ## `entity` does not include the leading `&` or the trailing `;`. Numeric
  ## forms (`"#65"`, `"#x41"`) are supported.
  runnableExamples:
    import std/unicode
    doAssert entityToRune("") == Rune(0)
    doAssert entityToRune("a") == Rune(0)
    doAssert entityToRune("gt") == ">".runeAt(0)
    doAssert entityToRune("Uuml") == "Ü".runeAt(0)
    doAssert entityToRune("quest") == "?".runeAt(0)
    doAssert entityToRune("#x0003F") == "?".runeAt(0)

  if entity.len == 0: return Rune(0)
  entityToRune(entity.toOpenArray(0, entity.high))

func entityToUtf8*(entity: openArray[char]): string {.raises: [].} =
  ## Converts an entity body to UTF-8. Returns `""` when unknown.
  runnableExamples:
    let buffer = "&gt;"
    doAssert entityToUtf8(buffer.toOpenArray(1, 2)) == ">"

  let rune = entityToRune(entity)
  if rune.ord <= 0: "" else: toUTF8(rune)

func entityToUtf8*(entity: string): string {.raises: [].} =
  ## Converts an entity body to UTF-8. Returns `""` when unknown.
  ##
  ## `entity` does not include the leading `&` or the trailing `;`. Numeric
  ## forms (`"#65"`, `"#x41"`) are supported.
  runnableExamples:
    const sigma = "Σ"
    doAssert entityToUtf8("") == ""
    doAssert entityToUtf8("a") == ""
    doAssert entityToUtf8("gt") == ">"
    doAssert entityToUtf8("Uuml") == "Ü"
    doAssert entityToUtf8("quest") == "?"
    doAssert entityToUtf8("#63") == "?"
    doAssert entityToUtf8("Sigma") == sigma
    doAssert entityToUtf8("#931") == sigma
    doAssert entityToUtf8("#0931") == sigma
    doAssert entityToUtf8("#x3A3") == sigma
    doAssert entityToUtf8("#x03A3") == sigma
    doAssert entityToUtf8("#x3a3") == sigma
    doAssert entityToUtf8("#X3a3") == sigma

  if entity.len == 0: return ""
  entityToUtf8(entity.toOpenArray(0, entity.high))
