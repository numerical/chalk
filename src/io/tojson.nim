## Turn a set of metadata key-value pairs into a JSON chalk object.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.

import tables, options, strformat, strutils, std/json, nimutils
import ../types, ../config

const
  comfyItemSep = ", " # also used in extract.nim
  kvPairJFmt   = "{comma}{keyJson} : {valJson}" # also extract.nim
  jSonObjFmt   = "{ $# }"
  jsonArrFmt   = "[ $# ]"

proc foundToJson*(self: ChalkDict): string

proc strValToJson*(s: string): string =
  # %* from the json module; this basically does any escaping
  # we need, which gives us a JsonNode object, that we then convert
  # back to a string, with necessary quotes intact.
  return $( %* s)

# This version of the function takes a chalk dictionary object,
# and is called on any nested / embedded objects; it reads from
# the dict paramter, instead of the `newFields` item found in
# the chalk object.
#
# Use the one below is for insertion.
proc foundToJson*(self: ChalkDict): string =
  var comma = ""

  for fullKey in getOrderedKeys():
    var outputKey = fullKey

    if fullKey notin self:
      continue

    let
      keyJson = strValToJson(outputKey)
      valJson = boxToJson(self[fullKey])

    result = result & kvPairJFmt.fmt()
    comma = comfyItemSep

  result = jSonObjFmt % [result]

proc createdToJson*(obj: ChalkObj, ptrOnly = false): string =
  var comma = ""

  for fullKey in getOrderedKeys():
    var outputKey = fullKey

    # If this key is set, but ptrOnly is false, then we are
    # outputting the "full" chalk, in which case we do not
    # write this field out.
    if outputKey == "CHALK_PTR" and not ptrOnly:
      continue

    let spec = getKeySpec(fullKey).get()

    if not obj.newFields.contains(fullKey):
      continue

    # Skip outputting this key if "skip" is set in the key's existing
    # configuration.
    if spec.getSkip():
      continue

    # If chalk pointers are set up, and we're currently outputting
    # a pointer, then we only output if the config has the in_ref
    # field set.
    if ptrOnly and not spec.getInPtr():
      continue

    let
      keyJson = strValToJson(outputKey)
      valJson = boxToJson(obj.newFields[fullKey])

    result = result & kvPairJFmt.fmt()
    comma = comfyItemSep

  result = jSonObjFmt % [result]
