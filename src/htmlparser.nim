#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## .. note:: In order to use this module, run `nimble install htmlparser`.
##
## **NOTE**: The behaviour might change in future versions as it is not
## clear what "*wild* HTML the real world uses" really implies.
##
## It can be used to parse a wild HTML document and output it as valid XHTML
## document (well, if you are lucky):
##   ```Nim
##   echo loadHtml("mydirty.html")
##   ```
##
## Every tag in the resulting tree is in lower case.
##
## **Note:** The resulting `XmlNode` already uses the `clientData` field,
## so it cannot be used by clients of this library.
##
## Example: Transforming hyperlinks
## ================================
##
## This code demonstrates how you can iterate over all the tags in an HTML file
## and write back the modified version. In this case we look for hyperlinks
## ending with the extension `.rst` and convert them to `.html`.
##
##   ```Nim test
##   import std/xmltree  # To use '$' for XmlNode
##   import std/strtabs  # To access XmlAttributes
##   import std/os       # To use splitFile
##   import std/strutils # To use cmpIgnoreCase
##
##   proc transformHyperlinks() =
##     let html = loadHtml("input.html")
##
##     for a in html.findAll("a"):
##       if a.attrs.hasKey "href":
##         let (dir, filename, ext) = splitFile(a.attrs["href"])
##         if cmpIgnoreCase(ext, ".rst") == 0:
##           a.attrs["href"] = dir / filename & ".html"
##
##     writeFile("output.html", $html)
##   ```

import std/[strutils, streams, parsexml, xmltree, unicode, strtabs]
import ./htmlparser/entitylookup
export entityToRune, entityToUtf8

when defined(nimPreviewSlimSystem):
  import std/syncio

type
  HtmlTag* = enum  ## list of all supported HTML tags; order will always be
                   ## alphabetically
    tagUnknown,    ## unknown HTML element
    tagA,          ## the HTML `a` element
    tagAbbr,       ## the deprecated HTML `abbr` element
    tagAcronym,    ## the HTML `acronym` element
    tagAddress,    ## the HTML `address` element
    tagApplet,     ## the deprecated HTML `applet` element
    tagArea,       ## the HTML `area` element
    tagArticle,    ## the HTML `article` element
    tagAside,      ## the HTML `aside` element
    tagAudio,      ## the HTML `audio` element
    tagB,          ## the HTML `b` element
    tagBase,       ## the HTML `base` element
    tagBdi,        ## the HTML `bdi` element
    tagBdo,        ## the deprecated HTML `dbo` element
    tagBasefont,   ## the deprecated HTML `basefont` element
    tagBig,        ## the HTML `big` element
    tagBlockquote, ## the HTML `blockquote` element
    tagBody,       ## the HTML `body` element
    tagBr,         ## the HTML `br` element
    tagButton,     ## the HTML `button` element
    tagCanvas,     ## the HTML `canvas` element
    tagCaption,    ## the HTML `caption` element
    tagCenter,     ## the deprecated HTML `center` element
    tagCite,       ## the HTML `cite` element
    tagCode,       ## the HTML `code` element
    tagCol,        ## the HTML `col` element
    tagColgroup,   ## the HTML `colgroup` element
    tagCommand,    ## the HTML `command` element
    tagDatalist,   ## the HTML `datalist` element
    tagDd,         ## the HTML `dd` element
    tagDel,        ## the HTML `del` element
    tagDetails,    ## the HTML `details` element
    tagDfn,        ## the HTML `dfn` element
    tagDialog,     ## the HTML `dialog` element
    tagDiv,        ## the HTML `div` element
    tagDir,        ## the deprecated HTLM `dir` element
    tagDl,         ## the HTML `dl` element
    tagDt,         ## the HTML `dt` element
    tagEm,         ## the HTML `em` element
    tagEmbed,      ## the HTML `embed` element
    tagFieldset,   ## the HTML `fieldset` element
    tagFigcaption, ## the HTML `figcaption` element
    tagFigure,     ## the HTML `figure` element
    tagFont,       ## the deprecated HTML `font` element
    tagFooter,     ## the HTML `footer` element
    tagForm,       ## the HTML `form` element
    tagFrame,      ## the HTML `frame` element
    tagFrameset,   ## the deprecated HTML `frameset` element
    tagH1,         ## the HTML `h1` element
    tagH2,         ## the HTML `h2` element
    tagH3,         ## the HTML `h3` element
    tagH4,         ## the HTML `h4` element
    tagH5,         ## the HTML `h5` element
    tagH6,         ## the HTML `h6` element
    tagHead,       ## the HTML `head` element
    tagHeader,     ## the HTML `header` element
    tagHgroup,     ## the HTML `hgroup` element
    tagHtml,       ## the HTML `html` element
    tagHr,         ## the HTML `hr` element
    tagI,          ## the HTML `i` element
    tagIframe,     ## the deprecated HTML `iframe` element
    tagImg,        ## the HTML `img` element
    tagInput,      ## the HTML `input` element
    tagIns,        ## the HTML `ins` element
    tagIsindex,    ## the deprecated HTML `isindex` element
    tagKbd,        ## the HTML `kbd` element
    tagKeygen,     ## the HTML `keygen` element
    tagLabel,      ## the HTML `label` element
    tagLegend,     ## the HTML `legend` element
    tagLi,         ## the HTML `li` element
    tagLink,       ## the HTML `link` element
    tagMap,        ## the HTML `map` element
    tagMark,       ## the HTML `mark` element
    tagMenu,       ## the deprecated HTML `menu` element
    tagMeta,       ## the HTML `meta` element
    tagMeter,      ## the HTML `meter` element
    tagNav,        ## the HTML `nav` element
    tagNobr,       ## the deprecated HTML `nobr` element
    tagNoframes,   ## the deprecated HTML `noframes` element
    tagNoscript,   ## the HTML `noscript` element
    tagObject,     ## the HTML `object` element
    tagOl,         ## the HTML `ol` element
    tagOptgroup,   ## the HTML `optgroup` element
    tagOption,     ## the HTML `option` element
    tagOutput,     ## the HTML `output` element
    tagP,          ## the HTML `p` element
    tagParam,      ## the HTML `param` element
    tagPre,        ## the HTML `pre` element
    tagProgress,   ## the HTML `progress` element
    tagQ,          ## the HTML `q` element
    tagRp,         ## the HTML `rp` element
    tagRt,         ## the HTML `rt` element
    tagRuby,       ## the HTML `ruby` element
    tagS,          ## the deprecated HTML `s` element
    tagSamp,       ## the HTML `samp` element
    tagScript,     ## the HTML `script` element
    tagSection,    ## the HTML `section` element
    tagSelect,     ## the HTML `select` element
    tagSmall,      ## the HTML `small` element
    tagSource,     ## the HTML `source` element
    tagSpan,       ## the HTML `span` element
    tagStrike,     ## the deprecated HTML `strike` element
    tagStrong,     ## the HTML `strong` element
    tagStyle,      ## the HTML `style` element
    tagSub,        ## the HTML `sub` element
    tagSummary,    ## the HTML `summary` element
    tagSup,        ## the HTML `sup` element
    tagTable,      ## the HTML `table` element
    tagTbody,      ## the HTML `tbody` element
    tagTd,         ## the HTML `td` element
    tagTextarea,   ## the HTML `textarea` element
    tagTfoot,      ## the HTML `tfoot` element
    tagTh,         ## the HTML `th` element
    tagThead,      ## the HTML `thead` element
    tagTime,       ## the HTML `time` element
    tagTitle,      ## the HTML `title` element
    tagTr,         ## the HTML `tr` element
    tagTrack,      ## the HTML `track` element
    tagTt,         ## the HTML `tt` element
    tagU,          ## the deprecated HTML `u` element
    tagUl,         ## the HTML `ul` element
    tagVar,        ## the HTML `var` element
    tagVideo,      ## the HTML `video` element
    tagWbr         ## the HTML `wbr` element

const
  tagToStr* = [
    "a", "abbr", "acronym", "address", "applet", "area", "article",
    "aside", "audio",
    "b", "base", "basefont", "bdi", "bdo", "big", "blockquote", "body",
    "br", "button", "canvas", "caption", "center", "cite", "code",
    "col", "colgroup", "command",
    "datalist", "dd", "del", "details", "dfn", "dialog", "div",
    "dir", "dl", "dt", "em", "embed", "fieldset",
    "figcaption", "figure", "font", "footer",
    "form", "frame", "frameset", "h1", "h2", "h3",
    "h4", "h5", "h6", "head", "header", "hgroup", "html", "hr",
    "i", "iframe", "img", "input", "ins", "isindex",
    "kbd", "keygen", "label", "legend", "li", "link", "map", "mark",
    "menu", "meta", "meter", "nav", "nobr", "noframes", "noscript",
    "object", "ol",
    "optgroup", "option", "output", "p", "param", "pre", "progress", "q",
    "rp", "rt", "ruby", "s", "samp", "script", "section", "select", "small",
    "source", "span", "strike", "strong", "style",
    "sub", "summary", "sup", "table",
    "tbody", "td", "textarea", "tfoot", "th", "thead", "time",
    "title", "tr", "track", "tt", "u", "ul", "var", "video", "wbr"]
  InlineTags* = {tagA, tagAbbr, tagAcronym, tagApplet, tagB, tagBasefont,
    tagBdo, tagBig, tagBr, tagButton, tagCite, tagCode, tagDel, tagDfn,
    tagEm, tagFont, tagI, tagImg, tagIns, tagInput, tagIframe, tagKbd,
    tagLabel, tagMap, tagObject, tagQ, tagSamp, tagScript, tagSelect,
    tagSmall, tagSpan, tagStrong, tagSub, tagSup, tagTextarea, tagTt,
    tagVar, tagApplet, tagBasefont, tagFont, tagIframe, tagU, tagS,
    tagStrike, tagWbr}
  BlockTags* = {tagAddress, tagBlockquote, tagCenter, tagDel, tagDir, tagDiv,
    tagDl, tagFieldset, tagForm, tagH1, tagH2, tagH3, tagH4,
    tagH5, tagH6, tagHr, tagIns, tagIsindex, tagMenu, tagNoframes, tagNoscript,
    tagOl, tagP, tagPre, tagTable, tagUl, tagCenter, tagDir, tagIsindex,
    tagMenu, tagNoframes}
  SingleTags* = {tagArea, tagBase, tagBasefont,
    tagBr, tagCol, tagFrame, tagHr, tagImg, tagIsindex,
    tagLink, tagMeta, tagParam, tagWbr, tagSource}

proc allLower(s: string): bool =
  for c in s:
    if c < 'a' or c > 'z': return false
  return true

proc toHtmlTag(s: string): HtmlTag =
  case s
  of "a": tagA
  of "abbr": tagAbbr
  of "acronym": tagAcronym
  of "address": tagAddress
  of "applet": tagApplet
  of "area": tagArea
  of "article": tagArticle
  of "aside": tagAside
  of "audio": tagAudio
  of "b": tagB
  of "base": tagBase
  of "basefont": tagBasefont
  of "bdi": tagBdi
  of "bdo": tagBdo
  of "big": tagBig
  of "blockquote": tagBlockquote
  of "body": tagBody
  of "br": tagBr
  of "button": tagButton
  of "canvas": tagCanvas
  of "caption": tagCaption
  of "center": tagCenter
  of "cite": tagCite
  of "code": tagCode
  of "col": tagCol
  of "colgroup": tagColgroup
  of "command": tagCommand
  of "datalist": tagDatalist
  of "dd": tagDd
  of "del": tagDel
  of "details": tagDetails
  of "dfn": tagDfn
  of "dialog": tagDialog
  of "div": tagDiv
  of "dir": tagDir
  of "dl": tagDl
  of "dt": tagDt
  of "em": tagEm
  of "embed": tagEmbed
  of "fieldset": tagFieldset
  of "figcaption": tagFigcaption
  of "figure": tagFigure
  of "font": tagFont
  of "footer": tagFooter
  of "form": tagForm
  of "frame": tagFrame
  of "frameset": tagFrameset
  of "h1": tagH1
  of "h2": tagH2
  of "h3": tagH3
  of "h4": tagH4
  of "h5": tagH5
  of "h6": tagH6
  of "head": tagHead
  of "header": tagHeader
  of "hgroup": tagHgroup
  of "html": tagHtml
  of "hr": tagHr
  of "i": tagI
  of "iframe": tagIframe
  of "img": tagImg
  of "input": tagInput
  of "ins": tagIns
  of "isindex": tagIsindex
  of "kbd": tagKbd
  of "keygen": tagKeygen
  of "label": tagLabel
  of "legend": tagLegend
  of "li": tagLi
  of "link": tagLink
  of "map": tagMap
  of "mark": tagMark
  of "menu": tagMenu
  of "meta": tagMeta
  of "meter": tagMeter
  of "nav": tagNav
  of "nobr": tagNobr
  of "noframes": tagNoframes
  of "noscript": tagNoscript
  of "object": tagObject
  of "ol": tagOl
  of "optgroup": tagOptgroup
  of "option": tagOption
  of "output": tagOutput
  of "p": tagP
  of "param": tagParam
  of "pre": tagPre
  of "progress": tagProgress
  of "q": tagQ
  of "rp": tagRp
  of "rt": tagRt
  of "ruby": tagRuby
  of "s": tagS
  of "samp": tagSamp
  of "script": tagScript
  of "section": tagSection
  of "select": tagSelect
  of "small": tagSmall
  of "source": tagSource
  of "span": tagSpan
  of "strike": tagStrike
  of "strong": tagStrong
  of "style": tagStyle
  of "sub": tagSub
  of "summary": tagSummary
  of "sup": tagSup
  of "table": tagTable
  of "tbody": tagTbody
  of "td": tagTd
  of "textarea": tagTextarea
  of "tfoot": tagTfoot
  of "th": tagTh
  of "thead": tagThead
  of "time": tagTime
  of "title": tagTitle
  of "tr": tagTr
  of "track": tagTrack
  of "tt": tagTt
  of "u": tagU
  of "ul": tagUl
  of "var": tagVar
  of "video": tagVideo
  of "wbr": tagWbr
  else: tagUnknown


proc htmlTag*(n: XmlNode): HtmlTag =
  ## Gets `n`'s tag as a `HtmlTag`.
  if n.clientData == 0:
    n.clientData = toHtmlTag(n.tag).ord
  result = HtmlTag(n.clientData)

proc htmlTag*(s: string): HtmlTag =
  ## Converts `s` to a `HtmlTag`. If `s` is no HTML tag, `tagUnknown` is
  ## returned.
  let s = if allLower(s): s else: toLowerAscii(s)
  result = toHtmlTag(s)

proc runeToEntity*(rune: Rune): string =
  ## converts a Rune to its numeric HTML entity equivalent.
  runnableExamples:
    import std/unicode
    doAssert runeToEntity(Rune(0)) == ""
    doAssert runeToEntity(Rune(-1)) == ""
    doAssert runeToEntity("Ü".runeAt(0)) == "#220"
    doAssert runeToEntity("∈".runeAt(0)) == "#8712"
  if rune.ord <= 0: result = ""
  else: result = '#' & $rune.ord

proc addNode(father, son: XmlNode) =
  if son != nil: add(father, son)

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode {.gcsafe.}

proc expected(x: var XmlParser, n: XmlNode): string =
  result = errorMsg(x, "</" & n.tag & "> expected")

template elemName(x: untyped): untyped = rawData(x)

template adderr(x: untyped) =
  errors.add(x)

proc untilElementEnd(x: var XmlParser, result: XmlNode,
                     errors: var seq[string]) =
  # we parsed e.g. `<br>` and don't really expect a `</br>`:
  if result.htmlTag in SingleTags:
    if x.kind != xmlElementEnd or cmpIgnoreCase(x.elemName, result.tag) != 0:
      return
  while true:
    case x.kind
    of xmlElementStart, xmlElementOpen:
      case result.htmlTag
      of tagP, tagInput, tagOption:
        # some tags are common to have no `</end>`, like `<li>` but
        # allow `<p>` in `<dd>`, `<dt>` and `<li>` in next case
        if htmlTag(x.elemName) in {tagLi, tagP, tagDt, tagDd, tagInput,
                                   tagOption}:
          adderr(expected(x, result))
          break
      of tagDd, tagDt, tagLi:
        if htmlTag(x.elemName) in {tagLi, tagDt, tagDd, tagInput,
                                   tagOption}:
          adderr(expected(x, result))
          break
      of tagTd, tagTh:
        if htmlTag(x.elemName) in {tagTr, tagTd, tagTh, tagTfoot, tagThead}:
          adderr(expected(x, result))
          break
      of tagTr:
        if htmlTag(x.elemName) == tagTr:
          adderr(expected(x, result))
          break
      of tagOptgroup:
        if htmlTag(x.elemName) in {tagOption, tagOptgroup}:
          adderr(expected(x, result))
          break
      else: discard
      result.addNode(parse(x, errors))
    of xmlElementEnd:
      if cmpIgnoreCase(x.elemName, result.tag) != 0:
        #echo "5; expected: ", result.htmltag, " ", x.elemName
        adderr(expected(x, result))
        # this seems to do better match error corrections in browsers:
        while x.kind in {xmlElementEnd, xmlWhitespace}:
          if x.kind == xmlElementEnd and cmpIgnoreCase(x.elemName,
              result.tag) == 0:
            break
          next(x)
      next(x)
      break
    of xmlEof:
      adderr(expected(x, result))
      break
    else:
      result.addNode(parse(x, errors))

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode =
  case x.kind
  of xmlComment:
    result = newComment(x.rawData)
    next(x)
  of xmlCharData, xmlWhitespace:
    result = newText(x.rawData)
    next(x)
  of xmlPI, xmlSpecial:
    # we just ignore processing instructions for now
    next(x)
  of xmlError:
    adderr(errorMsg(x))
    next(x)
  of xmlElementStart:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    untilElementEnd(x, result, errors)
  of xmlElementEnd:
    adderr(errorMsg(x, "unexpected ending tag: " & x.elemName))
  of xmlElementOpen:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    result.attrs = newStringTable()
    while true:
      case x.kind
      of xmlAttribute:
        result.attrs[x.rawData] = x.rawData2
        next(x)
      of xmlElementClose:
        next(x)
        break
      of xmlError:
        adderr(errorMsg(x))
        next(x)
        break
      else:
        adderr(errorMsg(x, "'>' expected"))
        next(x)
        break
    untilElementEnd(x, result, errors)
  of xmlAttribute, xmlElementClose:
    adderr(errorMsg(x, "<some_tag> expected"))
    next(x)
  of xmlCData:
    result = newCData(x.rawData)
    next(x)
  of xmlEntity:
    var u = entityToUtf8(x.rawData)
    if u.len != 0: result = newText(u)
    next(x)
  of xmlEof: discard

proc parseHtml*(s: Stream, filename: string,
                errors: var seq[string]): XmlNode =
  ## Parses the XML from stream `s` and returns a `XmlNode`. Every
  ## occurred parsing error is added to the `errors` sequence.
  var x: XmlParser
  open(x, s, filename, {reportComments, reportWhitespace, allowUnquotedAttribs,
    allowEmptyAttribs})
  next(x)
  # skip the DOCTYPE:
  if x.kind == xmlSpecial: next(x)

  result = newElement("document")
  result.addNode(parse(x, errors))
  #if x.kind != xmlEof:
  #  adderr(errorMsg(x, "EOF expected"))
  while x.kind != xmlEof:
    var oldPos = x.bufpos # little hack to see if we made any progress
    result.addNode(parse(x, errors))
    if x.bufpos == oldPos:
      # force progress!
      next(x)
  close(x)
  if result.len == 1:
    result = result[0]

proc parseHtml*(s: Stream): XmlNode =
  ## Parses the HTML from stream `s` and returns a `XmlNode`. All parsing
  ## errors are ignored.
  var errors: seq[string] = @[]
  result = parseHtml(s, "unknown_html_doc", errors)

proc parseHtml*(html: string): XmlNode =
  ## Parses the HTML from string `html` and returns a `XmlNode`. All parsing
  ## errors are ignored.
  parseHtml(newStringStream(html))

proc loadHtml*(path: string, errors: var seq[string]): XmlNode =
  ## Loads and parses HTML from file specified by `path`, and returns
  ## a `XmlNode`. Every occurred parsing error is added to
  ## the `errors` sequence.
  var s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "Unable to read file: " & path)
  result = parseHtml(s, path, errors)

proc loadHtml*(path: string): XmlNode =
  ## Loads and parses HTML from file specified by `path`, and returns
  ## a `XmlNode`. All parsing errors are ignored.
  var errors: seq[string] = @[]
  result = loadHtml(path, errors)

when not defined(testing) and isMainModule:
  import os

  var errors: seq[string] = @[]
  var x = loadHtml(paramStr(1), errors)
  for e in items(errors): echo e

  var f: File
  if open(f, "test.txt", fmWrite):
    f.write($x)
    f.close()
  else:
    quit("cannot write test.txt")
