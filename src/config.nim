import strformat
import strutils
import con4m
import con4m/st # TODO: fix so not needed
import con4m/eval # TODO whole lot of no
# TODO: these should be automaticly exported by con4m
import tables
import algorithm
import os
import streams
import sugar

include errors

const baseConfig = """
sami_version := "0.2.0"
ascii_magic := "dadfedabbadabbed"

key _MAGIC json {
    required: true
    missing_action: "abort"
    system: true
    squash: true
    type: "string"
    value: ascii_magic
    standard: true
    since: "0.1.0"
    output_order: 0
}

key SAMI_ID {
    required: true
    missing_action: "error"
    system: true
    squash: false
    type: "integer"
    standard: true
    since: "0.1.0"
    output_order: 1
}

key SAMI_VERSION {
    required: true
    missing_action: "error"
    system: true
    type: "string"
    value: sami_version
    standard: true
    since: "0.1.0"
    output_order: 2
}

key TIMESTAMP {
    required: true
    missing_action: "error"
    system: true
    type: "integer"
    since: "0.1.0"
    output_order: 3
    standard: true
}

key EARLIEST_VERSION {
    type: "string"
    since: "0.1.0"
    system: true
    value: sami_version
    output_order: 4
    standard: true
}

key ORIGIN_URI {
    type: "string"
    missing_action: "warn"
    since: "0.1.0"
    standard: true
}

key ARTIFACT_VERSION {
    type: "string"
    since: "0.1.0"
    standard: true
}

key ARTIFACT_FILES {
    type: "[string]"
    since: "0.1.0"
    standard: true
}

key IAM_USERNAME {
    must_force: true
    type: "string"
    since: "0.1.0"
    standard: true
}

key IAM_UID {
    must_force: true
    type: "integer"
    since: "0.1.0"
    standard: true
}

key BUILD_URI {
    type: "string"
    since: "0.1.0"
    standard: true
}

key STORE_URI {
    type: "string"
    since: "0.1.0"
    standard: true
}

key BRANCH {
    type: "string"
    since: "0.1.0"
    standard: true
}

key SRC_URI {
    type: "string"
    since: "0.1.0"
    standard: true
}

key REPO_ORIGIN {
    type: "string"
    system: false
    since: "0.1.0"
    standard: true
}

key HASH {
    type: "string"
    since: "0.1.0"
    codec: true
    standard: true
}

key HASH_FILES {
    type: "[string]"
    since: "0.1.0"
    codec: true
    standard: true
}

key COMMIT_ID {
    type: "string"
    since: "0.1.0"
    standard: true
}

key JOB_ID {
    type: "string"
    since: "0.1.0"
    standard: true
}

key SRC_PATH {
    type: "string"
    since: "0.1.0"
    codec: true
    standard: true
}

key FILE_NAME {
    type: "string"
    since: "0.1.0"
    codec: true
    standard: true
}

key CODE_OWNERS {
    type: "string"
    since: "0.1.0"
    standard: true
}

key BUILD_OWNERS {
    type: "string"
    since: "0.1.0"
    standard: true
}

key OLD_SAMI {
    type: "sami"
    since: "0.1.0"
    standard: true
    output_order: 996
}

key EMBEDS {
    type: "[(string, sami)]"
    standard: true
    output_order: 997
    since: "0.1.0"
}

key SBOMS {
    type: "{string, string}"
    since: "0.1.0"
    standard: true
    output_order: 998
}


key ERR_INFO {
    type: "[string]"
    standard: true
    since: "0.1.0"
    system: true
    standard: true
    output_order: 999
}

key SIGNATURE {
    type: "{string : string}"
    since: "0.1.0"
    standard: true
    output_order: 1000
}

# Doesn't do any keys other than the codec defaults, which are:
# SRC_PATH, FILE_NAME, HASH, HASH_FILES
plugin elf {
    codec: true
    keys: []
}

plugin shebang {
    codec: true
    keys: []
}

# Probably should add file time of artifact, date of branch
# and any tag associated.
plugin "vctl-git" {
    keys: ["COMMIT_ID", "BRANCH", "ORIGIN_URI"]
}

plugin authors {
    keys: ["CODE_OWNERS"]
}

plugin "github-codeowners" {
    keys: ["CODE_OWNERS"]
}

# This plugin is the only thing allowed to set these keys. However, it
# should run last to make sureit knows what other fields are being set
# before deciding how to handle the OLD_SAMI field.  Thus, the setting
# to 32-bit maxint (though should consider using the whole 64-bits).

plugin system {
    keys: ["TIMESTAMP", "SAMI_ID", "OLD_SAMI"]
    priority: 2147483647
}

# This plugin takes values from the conf file. By default, these
# are of the lowest priority of anything that can conflict.
# This will set SAMI_VERSION, EARLIEST_VERSION and _MAGIC.
plugin conffile {
    keys: ["*"]
    priority: 2147483646
}

output stdout {
}

output local_file {
}

output s3 {
}

extractor_handles: ["stdout", "what", "is", "going", "on"]
injector_handles: []

"""

## This variable represents the current config.  The con4m
## macro will also inject a variable with more config state, which we
## will use for config file layering.
## TODO: Add a field to the global or a section to configure
## logging options.
var samiConfig =  con4m(Sami, baseconfig):
  attr(config_path,
       [string],
       @[".", "~"],
       doc = "The path to search for other config files. " &
       "This can be specified at the command-line with an early flag."
  )
  attr(config_filename,
       string,
       "sami.conf",
       doc = "The config filename; also can be set from the command line")
  attr(default_command, string,
       required = false,
       doc = "When this command runs, if no command is provided, " &
             "which one runs?")
  attr(color, bool, false, doc = "Do you want ansi output?")
  attr(log_level, string, "warn")
  attr(dry_run, bool, false)
  attr(artifact_search_path, [string], @["."])
  attr(recursive, bool, true)
  attr(extractor_handles, [string], defaultVal = @["stdout"])
  attr(injector_handles, [string], defaultVal = @["stdout"])
  section(key, allowedSubSections = @["*", "*.json", "*.binary"]):
    attr(required,
         bool,
         defaultVal = false,
         doc = "When true, fail to WRITE a SAMI if no value is found " &
           "for the key via any allowed plugin.")
    attr(missing_action,
         string,
         defaultVal = "warn",
         doc = "What to do if, when READING a SAMI, we do not see this key")
    attr(system, bool,
         defaultVal = false,
         doc = "these fields CANNOT be customzied in any way;" &
               "the system sets them outside the scope of the plugin system.")
    attr(squash,
         bool,
         doc = "If there's an existing SAMI we are incorporating, " &
         "remove this key in the old SAMI if squash is true when possible",
         defaultVal = true,
         lockOnWrite = true)
    attr(standard,
         bool,
         defaultVal = false,
         doc = "These fields are part of the draft SAMI standard, " &
               "meaning they are NOT custom fields.  If you set " &
               "this to 'true' and it's not actually standard, your " &
               "key is never getting written!")
    attr(must_force,
         bool,
         defaultVal = false,
         doc = "If this is true, the key only will be turned on if " &
              "a command-line flag was passed to force adding this flag.")
    attr(skip,
         bool,
         defaultVal = false,
         doc = "If not required by the spec, skip writing this key," &
               " even if its value could be computed. Will also be " &
               "skipped if found in a nested SAMI")
    attr(output_order,
         int,
         defaultVal = 500,
         doc = "Lower numbers go first. Each provided value must be unique.")
    attr(since,
         string,
         required = false,
         doc = "When did this get added to the spec (if it's a spec key)")
    attr(type, string, lockOnWrite = true, required = true)
    attr(value,
         @x,
         doc = "This is the value set when the 'conffile' plugin runs. " &
           "The conffile plugin can handle any key, but you can still " &
           "configure it to set priority ordering, so you have fine-" &
           "grained control over when the conf file takes precedence " &
           "over the other plugins.",
         required = false)
    attr(docstring,
         string,
         required = false,
         doc = "documentation for the key.")
    attr(codec,
         bool,
         defaultVal = false,
         doc = "If true, then this key is settable by plugins marked codec.")
  section(plugin, allowedSubSections = @["*"]):
    attr(priority,
         int,
         required = true,
         defaultVal = 50,
         doc = "Vs other plugins, where should this run?  Lower goes first")
    attr(codec,
         bool,
         required = true,
         defaultVal = false,
         lockOnWrite = true)
    attr(enabled, bool, defaultVal = true, doc = "Turn off this plugin.")
    attr(command,
         string,
         required = false)
    attr(keys,
         [string],
         required = true,
         lockOnWrite = true)
    attr(overrides,
         {string: int}, required = false)
    attr(ignore,
         [string],
         required = false)
    attr(docstring,
         string,
         required = false)
  section(output, allowedSubSections = @["*"]):
    attr(secret,
         string,
         required = false)
    attr(filename,
         string,
         required = false)
    attr(dst_uri,
         string,
         required = false)
    attr(command,
         [string],
         required = false)

#         doc = "Is this plugin a codec?")
#         doc = "The list of keys this codec can serve")
#         doc = "List of keys whose priorities should be changed from the " &
#          "default value this plugin has")
#         doc = "Keys that the user does NOT want this plugin to handle")
#         doc = "Description of plugin")
#         doc = "Plugin is not linked, but called via an external command to return JSON"
# TODO: possibly a reverse squash

const allowedCmds = ["inject", "extract", "defaults"]
const validLogLevels = ["none", "error", "warn", "info", "trace"]


type SamiOutputHandler* = (string, SamiOutputSection) -> bool


proc getOutputConfig*(): TableRef[string, SamiOutputSection] =
  return samiConfig.output

proc getOutputSecret*(s: SamiOutputSection): Option[string] =
  return s.secret
  
proc getOutputFilename*(s: SamiOutputSection): Option[string] =
  return s.filename
  
proc getOutputDstUri*(s: SamiOutputSection): Option[string] =
  return s.dst_uri
  
proc getOutputCommand*(s: SamiOutputSection): Option[seq[string]] =
  return s.command

proc getConfigErrors*(): Option[seq[string]] =
  if ctxSamiConf.errors.len() != 0:
    return some(ctxSamiConf.errors)

proc getConfigPath*(): seq[string] =
  return samiConfig.configPath

proc setConfigPath*(val: seq[string]) =
  discard ctxSamiConf.setOverride("config_path", boxList(val))
  samiConfig.configPath = val

proc getConfigFileName*(): string =
  return samiConfig.configFileName

proc setConfigFileName*(val: string) =
  discard ctxSamiConf.setOverride("config_filename", box(val))
  samiConfig.configFileName = val

proc getDefaultCommand*(): Option[string] =
  return samiConfig.defaultCommand

# not needed.
# proc setDefaultCommand*(val: string) =
#   samiConfig.defaultCommand = some(val)

proc getColor*(): bool =
  return samiConfig.color

proc setColor*(val: bool) =
  discard ctxSamiConf.setOverride("color", box(val))
  samiConfig.color = val

proc getLogLevel*(): string =
  return samiConfig.logLevel

proc setLogLevel*(val: string) =
  discard ctxSamiConf.setOverride("log_level", box(val))
  samiConfig.logLevel = val

proc getDryRun*(): bool =
  return samiConfig.dryRun

proc setDryRun*(val: bool) =
  discard ctxSamiConf.setOverride("dry_run", box(val))
  samiConfig.dryRun = val

proc getArtifactSearchPath*(): seq[string] =
  return samiConfig.artifactSearchPath

proc setArtifactSearchPath*(val: seq[string]) =
  discard ctxSamiConf.setOverride("artifact_search_path", boxList(val))
  samiConfig.artifactSearchPath = val

proc getRecursive*(): bool =
  return samiConfig.recursive

proc setRecursive*(val: bool) =
  discard ctxSamiConf.setOverride("recursive", box(val))
  samiConfig.recursive = val

proc getExtractorHandles*(): seq[string] =
  return samiConfig.extractorHandles

proc getInjectorHandles*(): seq[string] =
  return samiConfig.injectorHandles

proc getAllKeys*(): seq[string] =
  result = @[]

  for key, val in samiConfig.key:
    result.add(key)


proc getKeySpec*(name: string): Option[SamiKeySection] =
  if name in samiConfig.key:
    return some(samiConfig.key[name])

proc getOrderedKeys*(): seq[string] =
  let keys = getAllKeys()

  var list: seq[(int, string)] = @[]

  for key in keys:
    let spec = getKeySpec(key).get()
    list.add((spec.outputOrder, key))

  list.sort()

  for (priority, key) in list:
    result.add(key)

proc getCustomKeys*(name: string): seq[string] =
  result = @[]

  for key, val in samiConfig.key:
    if not val.system:
      result.add(key)

proc getPluginConfig*(name: string): Option[SamiPluginSection] =
  if name in samiConfig.plugin:
    return some(samiConfig.plugin[name])

proc getRequired*(key: SamiKeySection): bool =
  return key.required

proc getMissingAction*(key: SamiKeySection): string =
  return key.missingAction

proc getSystem*(key: SamiKeySection): bool =
  return key.system

proc getSquash*(key: SamiKeySection): bool =
  return key.squash

proc getStandard*(key: SamiKeySection): bool =
  return key.standard

proc getMustForce*(key: SamiKeySection): bool =
  return key.mustForce

proc getSkip*(key: SamiKeySection): bool =
  return key.skip

proc getOutputOrder*(key: SamiKeySection): int =
  return key.outputOrder

proc getSince*(key: SamiKeySection): Option[string] =
  return key.since

proc getType*(key: SamiKeySection): string =
  return key.`type`

proc getValue*(key: SamiKeySection): Option[Box] =
  return key.value

proc getDocString*(key: SamiKeySection): Option[string] =
  return key.docString

proc getPriority*(plugin: SamiPluginSection): int =
  return plugin.priority

proc getCodec*(plugin: SamiPluginSection): bool =
  return plugin.codec

proc getEnabled*(plugin: SamiPluginSection): bool =
  return plugin.enabled

proc getKeys*(plugin: SamiPluginSection): seq[string] =
  return plugin.keys

proc getOverrides*(plugin: SamiPluginSection):
                 Option[TableRef[string, int]] =
  return plugin.overrides

proc getIgnore*(plugin: SamiPluginSection): Option[seq[string]] =
  return plugin.ignore

proc getDocString*(plugin: SamiPluginSection): Option[string] =
  return plugin.docstring

proc getCommand*(plugin: SamiPluginSection): Option[string] =
  return plugin.command

proc getCommandPlugins*(): seq[(string, string)] =
  for name, plugin in samiConfig.plugin:
    if (not plugin.command.isSome()) or (not plugin.enabled):
      continue
    result.add((name, plugin.command.get()))

proc `$`*(plugin: SamiPluginSection): string =
  var overrideStr, ignoreStr: string

  let optO = plugin.getOverrides()

  if optO.isNone():
    overrideStr = "<none>"
  else:
    var l: seq[string]
    for key, val in optO.get():
      l.add(fmt"{key} : {val}")
    overrideStr = l.join(", ")

  let optI = plugin.getIgnore()

  if optI.isNone():
    ignoreStr = "<none>"
  else:
    ignoreStr = optI.get().join(", ")


  return fmt"""  default priority:   {plugin.getPriority()}
  is codec:              {plugin.getCodec()}
  is enabled:            {plugin.getEnabled()}
  keys handled:          {plugin.getKeys().join(", ")}
  priority overrides:    {overrideStr}
  ignore:                {ignoreStr}
  doc string:            {getOrElse(plugin.docstring, "<none>")}
  external impl command: {plugin.command}

"""

proc valueToString(b: Box): string =
  # TODO: expand out complex types.
  case b.kind:
  of TypeInt:
    return $(unbox[int](b))
  of TypeFloat:
    return $(unbox[float](b))
  of TypeBool:
    return $(unbox[bool](b))
  of TypeString:
    return unbox[string](b)
  of TypeList:
    return "<somelist>"
  of TypeDict:
    return "<some dict>"
  else:
    return "??"

proc `$`*(key: SamiKeySection): string =
  var valstr = "<none>"

  if key.value.isSome():
    valstr = valueToString(key.value.get())

  return fmt"""  standard:           {key.standard}
  required:           {key.required}
  missing action:     {key.missingAction}
  system:             {key.system}
  squash:             {key.squash}  
  force required:     {key.mustForce}
  skip:               {key.skip}
  first spec version: {getOrElse(key.since, "<none>")}
  output order:       {key.outputOrder}
  content type:       {key.`type`}
  value:              {valstr}
  doc string:         {getOrElse(key.docstring, "<none>")}
"""

proc `$`*(c: SamiConfig): string =
  var configKeys, configPlugins: seq[string]

  for key, val in c.key:
    configKeys.add($(key))
    configKeys.add($(val))

  for plugin, val in c.plugin:
    configPlugins.add($(plugin))
    configPlugins.add($(val))

  return fmt"""config search path:        {c.configPath.join(":")}
config filename:           {c.configFilename}
config default command:    {getOrElse(samiConfig.defaultCommand, "<none>")}
color:                     {c.color}
log level:                 {c.logLevel}
dry run:                   {c.dryRun}
artifact search path:      {c.artifactSearchPath.join(":")}
recursive artifact search: {c.recursive}
extractors loaded:         {c.extractorHandles}
injectors loaded:          {c.injectorHandles}
Configured SAMI keys:
{configKeys.join("\n")}

Configured Plugins:
{configPlugins.join("\n")}
"""

proc showConfig*() =
  echo $samiConfig

proc lockBuiltinKeys*() =
  for key in getAllKeys():
    let
      prefix = "key." & key
      std = getConfigVar(ctxSamiConf, prefix & ".standard").get()
      sys = getConfigVar(ctxSamiConf, prefix & ".system").get()

    if unbox[bool](std):
      discard ctxSamiConf.lockConfigVar(prefix & ".required")
      discard ctxSamiConf.lockConfigVar(prefix & ".system")
      discard ctxSamiConf.lockConfigVar(prefix & ".type")
      discard ctxSamiConf.lockConfigVar(prefix & ".standard")
      discard ctxSamiConf.lockConfigVar(prefix & ".since")
      discard ctxSamiConf.lockConfigVar(prefix & ".output_order")

    if unbox[bool](sys):
      discard ctxSamiConf.lockConfigVar(prefix & ".missing_action")
      discard ctxSamiConf.lockConfigVar(prefix & ".value")

# This should eventually move to evaluation callbacks.  They can give
# better error messages more easily.
# TODO: should also validate that all plugin keys are spec'd.
proc doAdditionalValidation*() =
  if samiConfig.defaultCommand.isSome() and
    not (samiConfig.defaultCommand.get() in allowedCmds):
    warn(fmt"Default command {samiConfig.defaultCommand.get()} " &
          "not recognized (ignored)")

    # This dance needs to be automated by con4m.  Note that we are
    # only making a copy of the entry here, so after we edit we need
    # to re-set it.
    var entry = ctxSamiConf.st.entries["default_command"]
    entry.value = none(Box)
    ctxSamiConf.st.entries["default_command"] = entry
    samiConfig.defaultCommand = none(string)

  if not (samiConfig.logLevel in validLogLevels):
    warn(fmt"Log level {samiConfig.logLevel} not recognized. " &
         "Defaulting to 'warn'")
    var entry = ctxSamiConf.st.entries["log_level"]
    entry.value = some(box("warn"))
    ctxSamiConf.st.entries["log_level"] = entry
    samiConfig.logLevel = "warn"

  # Now, lock a bunch of fields.
  lockBuiltinKeys()


proc loadUserConfigFile*() =
  let
    path = getConfigPath()
    filename = getConfigFileName()
  var fname: string = ""
  var f: FileStream

  for dir in path:
    fname = dir.joinPath(filename)
    if fname.fileExists():
      break

  if fname != "":
    let res = ctxSamiConf.stackConfig(fname)
    if res.isNone():
      error(fmt"{filename}: invalid configuration not loaded.")
      
      if ctxSamiConf.errors.len() != 0:
        for err in ctxSamiConf.errors:
          error(err)
          
      quit()

  samiConfig = ctxSamiConf.loadSamiConfig()
  doAdditionalValidation()

