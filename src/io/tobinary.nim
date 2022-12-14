import ../resources
import ../types
import ../config

import con4m

import strformat
import strutils
import tables

proc u32ToStr*(i: uint32): string =
  result = newStringOfCap(sizeof(uint32)+1)
  let arr = cast[array[4, char]](i)

  for ch in arr:
    result.add(ch)

proc u64ToStr*(i: uint64): string =
  result = newStringOfCap(sizeof(uint64)+1)
  let arr = cast[array[8, char]](i)

  for ch in arr:
    result.add(ch)

proc binEncodeItem(self: Box): string

proc binEncodeStr(s: string): string

proc binEncodeStr(s: string): string =
  return binStrItemFmt.fmt()

proc binEncodeInt(i: uint64): string =
  return binIntItemFmt.fmt()

proc binEncodeBool(b: bool): string =
  if b: return binTrue
  else: return binFalse

proc binEncodeArr(arr: seq[Box]): string =
  result = binArrStartFmt.fmt()

  for item in arr:
    result = result & binEncodeItem(item)

proc binEncodeObj(self: SamiDict): string =
  result = binObjHdr.fmt()

  for outputKey in self.keys():
    let val = self[outputKey]
    result = kvPairBinFmt.fmt()

proc binEncodeItem(self: Box): string =
  case self.kind
  of TypeBool: return binEncodeBool(unbox[bool](self))
  of TypeInt: return binEncodeInt(unbox[uint64](self))
  of TypeString:
    return binEncodeStr(unbox[string](self))
  of TypeDict:
    return binEncodeObj(unboxDict[string, Box](self))
  of TypeList:
    return binEncodeArr(unboxList[Box](self))
  else:
    unreachable

proc createdToBinary*(sami: SamiObj): string =
  var fieldCount = 0

  # Count how many fields we will write.  Ignore .json fields
  for key, _ in sami.newFields:
    if "." in key:
      let parts = key.split(".")
      if len(parts) != 2 or parts[1] != "binary":
        continue
    fieldCount += 1

  result = magicBin & u32ToStr(uint32(fieldCount))

  for fullKey in getOrderedKeys():
    var outputKey = fullKey

    if "." in fullKey:
      let parts = fullKey.split(".")
      if len(parts) != 2 or parts[1] != "binary":
        continue
      outputKey = parts[0]

    if not sami.newFields.contains(fullKey):
      continue

    let val = sami.newFields[fullKey]
    result = kvPairBinFmt.fmt()

