discard """
  matrix: "--mm:arc; --mm:refc"
  targets: "c"
"""

# Deeply nested HTML is flattened instead of exhausting the stack, and the
# public parse/load procs do not have the broad `Exception` effect.

import ../../src/htmlparser
import std/[strutils, streams, assertions, xmltree]

proc htmlFromString(s: string): XmlNode {.raises: [IOError, OSError, ValueError].} =
  parseHtml(s)

proc htmlFromStream(s: Stream): XmlNode {.raises: [IOError, OSError, ValueError].} =
  parseHtml(s)

proc htmlCollecting(s: Stream, errors: var seq[string]): XmlNode {.raises: [IOError, OSError, ValueError].} =
  parseHtml(s, "input", errors)

proc htmlFromFile(path: string): XmlNode {.raises: [IOError, OSError, ValueError].} =
  loadHtml(path)

proc htmlCollectingFromFile(path: string, errors: var seq[string]): XmlNode {.raises: [IOError, OSError, ValueError].} =
  loadHtml(path, errors)

const n = 500_000

block: # deeply nested document
  var errors: seq[string] = @[]
  let h = parseHtml(newStringStream("<div>".repeat(n) & "x"),
                    "deep.html", errors)

  var depth = 0
  var it = h
  while it.kind == xnElement and it.len > 0:
    inc depth
    it = it[0]
  doAssert depth <= htmlMaxDepth + 1, $depth
  doAssert errors.len < 2 * htmlMaxDepth

block: # depth below the limit is unaffected
  var errors: seq[string] = @[]
  let ok = "<div>".repeat(100) & "x" & "</div>".repeat(100)
  var x = parseHtml(newStringStream(ok), "ok.html", errors)
  doAssert errors.len == 0
  for i in 1 ..< 100: x = x[0]
  doAssert x.innerText == "x"
