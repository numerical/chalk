## Conceptually, this is where ALL information about the configuration
## state lives.  A lot of our calls for accessing configuration state
## are auto-generated by this file though, and in c4autoconf.nim).
##
## This module does also handle loading configurations, including
## built-in ones and external ones.
##
## It also captures some environmental bits used by other modules.
## For instance, we collect some information about the build
## environment here.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.

import c4autoconf
export c4autoconf # This is conceptually part of our API.

import options, tables, strutils, strformat, algorithm, os, json, streams
import con4m, con4m/st, nimutils, nimutils/logging, types
import macros except error
export logging

proc comment(s: string): string =
  let lines = s.split("\n")
  result    = ""
  for line in lines:
    result &= "# " & line & "\n"

const
  versionStr  = staticexec("cat ../chalk.nimble | grep ^version")
  commitID    = staticexec("git rev-parse HEAD")
  archStr     = staticexec("uname -m")
  osStr       = staticexec("uname -o")

  # Some string constants used in multiple places.
  magicUTF8*         = "dadfedabbadabbed"
  tmpFilePrefix*     = "chalk"
  tmpFileSuffix*     = "-file.tmp"
  chalkC42Spec       = staticRead("configs/chalk.c42spec")
  chalkSchema*       = staticRead("configs/schema.c4m")
  baseFName          = "configs/baseconfig.c4m"
  defCfgFname        = "configs/defaultconfig.c4m"
  baseConfig*        = staticRead(baseFname)
  defaultConfig*     = staticRead(defCfgFname) & comment(baseConfig)
  defaultKeyPriority = 50

var
  chalkCon4mBuiltins: seq[(string, BuiltinFn, string)]
  ctxChalkConf*:      ConfigState
  chalkConfig*:       ChalkConfig   # Type from the con4m macro.
  con4mCallbacks:     seq[(string, string)] = @[]
  commandName:        string
  `canSelfInject?`:   bool                  = true
  builtinKeys:        seq[string]           = @[]
  systemKeys:         seq[string]           = @[]
  codecKeys:          seq[string]           = @[]

let
  (c42Obj*, c42Ctx*) = c42Spec(chalkC42Spec, "<embedded spec>").get()

# These two procs are needed externally to test new conf files when loading.
proc getCon4mBuiltins*(): seq[(string, BuiltinFn, string)] =
  return chalkCon4mBuiltins

proc getCon4mCallbacks*(): seq[(string, string)] =
  return con4mCallbacks

proc registerCon4mCallback*(con4mName: string, con4mType: string) =
  con4mCallbacks.add((con4mName, con4mType))

proc setChalkCon4mBuiltIns*(fns: seq[(string, BuiltinFn, string)]) {.inline.} =
  # Set from builtins.nim; instead of a cross-dependency, we let it
  # call us to set.
  chalkCon4mBuiltins = fns

macro declareChalkExeVersion(): untyped =
  return parseStmt("const " & versionStr)

proc getChalkExeVersion*(): string =
  declareChalkExeVersion()
  return version

proc getChalkCommitID*(): string =
  return commitID

proc getBinaryOS*():     string = osStr
proc getBinaryArch*():   string = archStr
proc getChalkPlatform*(): string = osStr & " " & archStr

proc setCommandName*(str: string) =
  commandName = str

proc getCommandName*(): string =
  return commandName

proc setNoSelfInjection*() =
  `canSelfInject?` = false

proc canSelfInject*(): bool =
  return `canSelfInject?`

proc getSelfInjecting*(): bool =
  return commandName == "confload"

template hookCheck(fieldname: untyped) =
  let s = astToStr(fieldName)

  if sinkConfData.`needs fieldName`:
    if not sinkopts.contains(s):
      warn("Sink config '" & sinkconf & "' is missing field '" & s &
           "', which is required by sink '" & sinkname &
           "' (config not installed)")


proc checkHooks*(sinkname:     string,
                 sinkconf:     string,
                 sinkConfData: SinkSpec,
                 sinkopts:     StringTable) =
    hookCheck(secret)
    hookCheck(uid)
    hookCheck(filename)
    hookCheck(uri)
    hookCheck(region)
    hookCheck(headers)
    hookCheck(cacheid)
    hookCheck(aux)

template dryRun*(s: string) =
  if chalkConfig.dryRun:
    publish("dry-run", s)

when not defined(release):
  template chalkDebug*(s: string) =
    const
      pre  = "\e[1;35m"
      post = "\e[0m"
    let
      msg = pre & "DEBUG: " & post & s & "\n"

    publish("debug", msg)
else:
  template chalkDebug*(s: string) = discard


proc setConfigPath*(val: seq[string]) =
  discard ctxChalkConf.setOverride("config_path", some(pack(val)))
  chalkConfig.configPath = val

proc setConfigFileName*(val: string) =
  discard ctxChalkConf.setOverride("config_filename", some(pack(val)))
  chalkConfig.configFileName = val

proc setConfigFile*(val: string) =
  let (head, tail) = val.splitPath()

  setConfigPath(@[head])
  setConfigFileName(tail)

proc setColor*(val: bool) =
  discard ctxChalkConf.setOverride("color", some(pack(val)))
  setShowColors(val)
  chalkConfig.color = some(val)

proc setConsoleLogLevel*(val: string) =
  discard ctxChalkConf.setOverride("log_level", some(pack(val)))
  setLogLevel(val)
  chalkConfig.logLevel = val

proc setDryRun*(val: bool) =
  discard ctxChalkConf.setOverride("dry_run", some(pack(val)))
  chalkConfig.dryRun = val

proc setPublishDefaults*(val: bool) =
  discard ctxChalkConf.setOverride("publish_defaults", some(pack(val)))
  chalkConfig.publishDefaults = val

proc setArtifactSearchPath*(val: seq[string]) =
  if len(val) == 0:
    return

  chalkConfig.artifactSearchPath = @[]

  for item in val:
    chalkConfig.artifactSearchPath.add(item.resolvePath())

  discard ctxChalkConf.setOverride("artifact_search_path", some(pack(val)))

proc setRecursive*(val: bool) =
  discard ctxChalkConf.setOverride("recursive", some(pack(val)))
  chalkConfig.recursive = val

proc setContainerImageId*(s: string) =
  discard ctxChalkConf.setOverride("container_image_id", some(pack(s)))
  chalkConfig.containerImageId = s

proc setContainerImageName*(s: string) =
  discard ctxChalkConf.setOverride("container_image_name", some(pack(s)))
  chalkConfig.containerImageId = s

proc setValue*(spec: KeySpec, value: Option[Box]) =
  discard spec.getAttrScope().setOverride("value", value)
  spec.value = value

proc getAllKeys*(): seq[string] =
  result = @[]

  for key, val in chalkConfig.keys:
    result.add(key)

proc getRequiredKeys*(): seq[string] =
  result = @[]

  for key, val in chalkConfig.keys:
    if val.required:
      result.add(key)

proc getKeySpec*(name: string): Option[KeySpec] =
  if name in chalkConfig.keys:
    return some(chalkConfig.keys[name])

proc orderKeys*(keys: openarray[string]): seq[string] =
  var list: seq[(int, string)] = @[]

  result = @[]

  for key in keys:
    try:
      let spec = getKeySpec(key).get()
      if spec.getStandard():
        list.add((spec.outputOrder, key))
      else:
        list.add((defaultKeyPriority, key))
    except:
      warn(fmt"Unknown key found in extraction: {key}")
      list.add((defaultKeyPriority, key))

  list.sort()

  for (_, key) in list:
    result.add(key)

proc getOrderedKeys*(): seq[string] =
  return orderKeys(getAllKeys())

proc getCustomKeys*(): seq[string] =
  result = @[]

  for key, val in chalkConfig.keys:
    if val.since.isNone():
      result.add(key)

proc getPluginConfig*(name: string): Option[PluginSpec] =
  if name in chalkConfig.plugins:
    return some(chalkConfig.plugins[name])

proc getSinkConfig*(hook: string): Option[SinkSpec] =
  if chalkConfig.sinks.contains(hook):
    return some(chalkConfig.sinks[hook])
  return none(SinkSpec)

proc getOutputPointers*(): bool =
  let contents = chalkConfig.keys["CHALK_PTR"]

  if contents.getValue().isSome() and not contents.getSkip():
    return true

  return false

proc isBuiltinKey*(name: string): bool =
  return name in builtinKeys

proc isSystemKey*(name: string): bool =
  return name in systemKeys

proc isCodecKey*(name: string): bool =
  return name in codecKeys

# Do last-minute sanity-checking so we can give better error messages
# more easily.  This function currently runs once for each config
# loading, to do any sanity checking.  Could probably do more with it.
# A lot of what's currently here should eventually move to
# auto-generated bits in the con4m spec, though.

proc postProcessConfig() =
  # Actually, not validation, but get this done early.

  if chalkConfig.color.isSome():
    setShowColors(chalkConfig.color.get())

  setLogLevel(chalkConfig.logLevel)

  # Take any paths and turn them into absolute paths.
  for i in 0 ..< len(chalkConfig.artifactSearchPath):
    chalkConfig.artifactSearchPath[i] =
      chalkConfig.artifactSearchPath[i].resolvePath()

  for i in 0 ..< len(chalkConfig.configPath):
    chalkConfig.configPath[i] = chalkConfig.configPath[i].resolvePath()

  # Make sure the sinks specified are all sinks we haveimplementations
  # for; this should always be true in the base config, but is nice
  # to have the check for development.

  when not defined(release):
    for sinkname, _ in chalkConfig.sinks:
      if getSink(sinkname).isNone():
        warn(fmt"Config declared sink '{sinkname}', but no " &
          "implementation exists")


proc loadBaseConfiguration*() =
  ## This function loads the built-in configuration, which is split
  ## into two con4m files, the 'schema' for metadata, and the default
  ## I/O configuration.

  # For our internal configurations, if we mess up, we want to see
  # all the debug info.  We'll turn that off later though.
  setCon4mVerbosity(c4vMax)

  let
    (x, ok) = firstRun(contents       = chalkSchema,
                       filename       = "<builtin-schema>",
                       spec           = c42Obj,
                       addBuiltins    = true,
                       customFuncs    = chalkCon4mBuiltins,
                       callbacks      = con4mCallbacks,
                       evalCtx        = c42Ctx)
  if not ok: quit(1)
  ctxChalkConf = x

  # We make the base config available and then load it again
  # because the subscribe() unsubscribe() funcs use it. We
  # should prob change that.
  chalkConfig = ctxChalkConf.attrs.loadChalkConfig()
  postProcessConfig()
  if not ctxChalkConf.stackConfig(baseConfig,
                                  "<compile_location>/src/" & baseFname,
                                   c42Ctx): quit(1)

  chalkConfig = ctxChalkConf.attrs.loadChalkConfig()
  postProcessConfig()
  setCon4mVerbosity(c4vShowLoc)


proc loadEmbeddedConfig*(selfChalkOpt: Option[ChalkDict]): bool =
  var
    confString:     string

  if selfChalkOpt.isNone():
    confString = defaultConfig
  else:
    let selfChalk = selfChalkOpt.get()

    # We extracted a CHALK object from our own executable.  Check for an
    # X_CHALK_CONFIG key, and if there is one, run that configuration
    # file, before loading any on-disk configuration file.
    if not selfChalk.contains("X_CHALK_CONFIG"):
      trace("Embedded self-CHALK does not contain a configuration.")
      confString = defaultConfig
    else:
      confString = unpack[string](selfChalk["X_CHALK_CONFIG"])

  try:
    let res = ctxChalkConf.stackConfig(confString,
                                       "<embedded configuration>",
                                       c42Ctx)
  except:
    if getCommandName() == "setconf":
      return true
    else:
      error("Embedded configuration is invalid. Use 'setconf' command to fix")
      return false

  chalkConfig = ctxChalkConf.attrs.loadChalkConfig()
  postProcessConfig()
  trace("Loaded embedded configuration file")

  var c4errLevel =  if chalkConfig.con4mPinpoint: c4vShowLoc else: c4vBasic

  if chalkConfig.con4mTraces:
    c4errLevel = if c4errLevel == c4vBasic: c4vTrace else: c4vMax

  setCon4mVerbosity(c4errLevel)

  return true

proc loadUserConfigFile*(commandName: string,
                         selfChalk:    Option[ChalkDict]): Option[string] =
  var
    path     = chalkConfig.getConfigPath()
    filename = chalkConfig.getConfigFileName() # the base file name.
    fname:     string              # configPath / baseFileName
    loaded:    bool   = false
    contents:  string = ""

  for dir in path:
    fname = dir.joinPath(filename)
    if fname.fileExists():
      break
    trace(fmt"No configuration file found in {dir}.")

  if fname != "":
    info(fmt"Loading config file: {fname}")
    try:
      var
        fd  = newFileStream(fname)
        res = ctxChalkConf.stackConfig(fd, fname)

      if not res:
        error(fmt"{fname}: invalid configuration not loaded.")
        return none(string)
      else:
        fd.setPosition(0)
        contents = fd.readAll()
        loaded = true

    except Con4mError: # config file didn't load:
      info(fmt"{fname}: config file not loaded.")
      if chalkConfig.ignoreBrokenConf:
        return none(string)
      trace("ignore_broken_conf is false: terminating.")
      quit()

  chalkConfig = ctxChalkConf.attrs.loadChalkConfig()
  postProcessConfig()

  if loaded:
    trace(fmt"Loaded configuration file: {fname}")
    return some(contents)

  else:
    trace("No user config file loaded.")
    return none(string)
