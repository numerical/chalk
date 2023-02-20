## Defines most of the types used throughout the chalk code base,
## except the config-file related types, which are auto-generated by
## con4m, and live in configs/con4mconfig.nim (and are included
## through config.nim)
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.

# At compile time, this will generate c4autoconf if the file doesn't exist,
# or if the spec file has a newer timestamp.  We do this before importing it.
static:
  discard staticexec("if test \\! c4autoconf.nim -nt configs/chalk.c42spec; " &
                     "then con4m spec configs/chalk.c42spec --language=nim " &
                     "--output-file=c4autoconf.nim; fi")

import c4autoconf
import streams, tables, nimutils

type
  ChalkDict* = TableRef[string, Box] ## \
     ## Representation of the abstract chalk's fields. If the chalk
     ## was read from a file, this will include any embeds / nests.
     ## If, however, it is a "new" chalk, then any embeds or
     ## chalks that were there when we first loaded the file
     ## will end up in the FileOfInterest object.

  FileFlags* = enum
    BigEndian, Arch64Bit, SkipWrite, StopScan

  ChalkPoint* = ref object
    ## The ChalkPoints object encodes all info known about a single point
    ## for a chalk, such as whether there's currently a chalk object
    ## there.
    chalkFields*:  Option[ChalkDict] ## The chalk fields found at a point.
    startOffset*: int  ## When we're inserting chalk, where does it go?
    endOffset*:   int  ## When we're inserting, where does the file resume?
    present*:     bool ## Flag to indicate when there's magic at the location.
    valid*:       bool

  ChalkObj* = ref object
    ## The chalk point info for a single artifact.
    fullpath*:  string      ## The path to the file we've hit on the walk.
    toplevel*:  string      ## The toplevel path under which we found this file.
    stream*:    FileStream  ## The open file.
    newFields*: ChalkDict   ## What we're adding during insertion.
    primary*:   ChalkPoint  ## This represents the location of a chalk's
                            ## insertion, and also holds any chalk fields
                            ## extracted from this position.
    exclude*:   seq[string] ## Extra files to exclude from the scan.
    flags*:     set[FileFlags]
    embeds*:    seq[(string, ChalkPoint)]
    err*:       seq[string]

  Plugin* = ref object of RootObj
    name*:       string
    configInfo*: PluginSpec

  Codec* = ref object of Plugin
    chalks*:      seq[ChalkObj]
    magic*:      string
    searchPath*: seq[string]

  KeyInfo* = TableRef[string, Box]

proc chalkHasExisting*(chalk: ChalkObj): bool {.inline.} =
  return chalk.primary.valid

proc chalkIsEmpty*(chalk: ChalkObj): bool {.inline.} =
  return if (chalk.embeds.len() > 0) or chalk.chalkHasExisting():
           false
         else:
           true

# For use in binary JSON encoding.
const
  binTypeNull*    = 0'u8
  binTypeString*  = 1'u8
  binTypeInteger* = 2'u8
  binTypeBool*    = 3'u8
  binTypeArray*   = 5'u8
  binTypeObj*     = 6'u8
