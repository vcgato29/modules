#!/bin/sh
# \
type tclsh 1>/dev/null 2>&1 && exec tclsh "$0" "$@"
# \
[ -x /usr/local/bin/tclsh ] && exec /usr/local/bin/tclsh "$0" "$@"
# \
[ -x /usr/bin/tclsh ] && exec /usr/bin/tclsh "$0" "$@"
# \
[ -x /bin/tclsh ] && exec /bin/tclsh "$0" "$@"
# \
echo "FATAL: module: Could not find tclsh in \$PATH or in standard directories" >&2; exit 1

########################################################################
# This is a pure TCL implementation of the module command
# to initialize the module environment, either
# - one of the scripts from the init directory should be sourced, or just
# - eval `/some-path/tclsh modulecmd.tcl MYSHELL autoinit`
# in both cases the path to tclsh is remembered and used furtheron
########################################################################
#
# Some Global Variables.....
#
set MODULES_CURRENT_VERSION 1.647
set g_debug 0 ;# Set to 1 to enable debugging
set error_count 0 ;# Start with 0 errors
set g_autoInit 0
set g_force 1 ;# Path element reference counting if == 0
set CSH_LIMIT 4000 ;# Workaround for commandline limits in csh
set flag_default_dir 1 ;# Report default directories
set flag_default_mf 1 ;# Report default modulefiles and version alias

# Used to tell if a machine is running Windows or not
proc isWin {} {
   global tcl_platform

   if { $tcl_platform(platform) eq "windows" } {
      return 1
   } else {
      return 0
   }
}

#
# Set Default Path separator
#
if { [isWin] } {
   set g_def_separator "\;"
} else {
   set g_def_separator ":"
}

# Dynamic columns
set DEF_COLUMNS 80 ;# Default size of columns for formatting
if {[catch {exec stty size} stty_size] == 0 && $stty_size ne ""} {
   set DEF_COLUMNS [lindex $stty_size 1]
}

# Use MODULECONTACT variable to set your support email address
if {[info exists env(MODULECONTACT)]} {
   set contact $env(MODULECONTACT)
} else {
   # Or change this to your support email address...
   set contact "root@localhost"
}

# Set some directories to ignore when looking for modules.
set ignoreDir(CVS) 1
set ignoreDir(RCS) 1
set ignoreDir(SCCS) 1
set ignoreDir(.svn) 1
set ignoreDir(.git) 1

global g_shellType
global g_shell

set show_oneperline 0 ;# Gets set if you do module list/avail -t
set show_modtimes 0 ;# Gets set if you do module list/avail -l
set show_filter "" ;# Gets set if you do module avail -d or -L

proc raiseErrorCount {} {
   global error_count
   incr error_count
}

proc renderError {} {
   global g_shellType error_count g_debug

   if {$g_debug} {
      report "Error: $error_count error(s) detected."
   }

   if {[info exists g_shellType]} {
      switch -- $g_shellType {
         csh {
            puts stdout "/bin/false;"
         }
         sh {
            puts stdout "/bin/false;"
         }
         fish {
            puts stdout "/bin/false;"
         }
         tcl {
            puts stdout "exec /bin/false;"
         }
         cmd {
            # nothing needed, reserved for future cygwin, MKS, etc
         }
         perl {
            puts stdout "die \"modulefile.tcl: $error_count error(s)\
               detected!\\n\""
         }
         python {
            puts stdout "raise RuntimeError(\
               'modulefile.tcl: $error_count error(s) detected!')"
         }
         lisp {
            puts stdout "(error \"modulefile.tcl:\
               $error_count error(s) detected!\")"
         }
      }
   }
}

#
# Debug, Info, Warnings and Error message handling.
#
proc reportDebug {message {nonewline ""}} {
   global g_debug

   if {$g_debug} {
      report "DEBUG $message" "$nonewline"
   }
}

proc reportWarning {message {nonewline ""}} {
   report "WARNING: $message" "$nonewline"
}

proc reportError {message {nonewline ""}} {
   raiseErrorCount
   report "ERROR: $message" "$nonewline"
}

proc reportErrorAndExit {message} {
   raiseErrorCount
   renderError
   error "$message"
}

proc reportInternalBug {message} {
   global contact

   raiseErrorCount
   report "Module ERROR: $message\nPlease contact: $contact"
}

proc report {message {nonewline ""}} {
   if {$nonewline ne ""} {
      puts -nonewline stderr "$message"
   } else {
      puts stderr "$message"
   }
}

########################################################################
# Use a slave TCL interpreter to execute modulefiles
#

proc unset-env {var} {
   global env

   if {[info exists env($var)]} {
      reportDebug "unset-env:  $var"
      unset env($var)
   }
}

proc execute-modulefile {modfile {help ""}} {
   global g_debug
   global ModulesCurrentModulefile

   set ModulesCurrentModulefile $modfile

   reportDebug "execute-modulefile:  Starting $modfile"
   set slave __[currentModuleName]
   if {![interp exists $slave]} {
      interp create $slave
      interp alias $slave setenv {} setenv
      interp alias $slave unsetenv {} unsetenv
      interp alias $slave getenv {} getenv
      interp alias $slave system {} system
      interp alias $slave append-path {} append-path
      interp alias $slave prepend-path {} prepend-path
      interp alias $slave remove-path {} remove-path
      interp alias $slave prereq {} prereq
      interp alias $slave conflict {} conflict
      interp alias $slave is-loaded {} is-loaded
      interp alias $slave module {} module
      interp alias $slave module-info {} module-info
      interp alias $slave module-whatis {} module-whatis
      interp alias $slave set-alias {} set-alias
      interp alias $slave unset-alias {} unset-alias
      interp alias $slave uname {} uname
      interp alias $slave x-resource {} x-resource
      interp alias $slave module-version {} module-version
      interp alias $slave module-alias {} module-alias
      interp alias $slave reportInternalBug {} reportInternalBug
      interp alias $slave reportWarning {} reportWarning
      interp alias $slave reportError {} reportError
      interp alias $slave raiseErrorCount {} raiseErrorCount
      interp alias $slave report {} report
      interp alias $slave isWin {} isWin

      interp eval $slave {global ModulesCurrentModulefile g_debug}
      interp eval $slave [list "set" "ModulesCurrentModulefile" $modfile]
      interp eval $slave [list "set" "g_debug" $g_debug]
      interp eval $slave [list "set" "help" $help]

   }
   set errorVal [interp eval $slave {
      if {$g_debug} {
         report "Sourcing $ModulesCurrentModulefile"
      }
      set sourceFailed [catch {source $ModulesCurrentModulefile} errorMsg]
      if {$help ne ""} {
         if {[info procs "ModulesHelp"] eq "ModulesHelp"} {
            ModulesHelp
         } else {
            reportWarning "Unable to find ModulesHelp in\
               $ModulesCurrentModulefile."
         }
         set sourceFailed 0
      }
         if {[module-info mode "display"] \
         && [info procs "ModulesDisplay"] eq "ModulesDisplay"} {
            ModulesDisplay
         }
      if {$sourceFailed} {
         if {$errorMsg eq "" && $errorInfo eq ""} {
            raiseErrorCount
            unset errorMsg
            return 1
         }\
         elseif [regexp "^WARNING" $errorMsg] {
            raiseErrorCount
            report $errorMsg
            return 1
         } else {
            global errorInfo

            reportInternalBug "Occurred in file\
               $ModulesCurrentModulefile:$errorInfo"
            exit 1
         }
      } else {
         unset errorMsg
         return 0
      }
   }]

   interp delete $slave
   reportDebug "Exiting $modfile"
   return $errorVal
}

# Smaller subset than main module load... This function runs modulerc and
# .version files
proc execute-modulerc {modfile} {
   global g_rcfilesSourced
   global g_debug g_moduleDefault
   global ModulesCurrentModulefile

   reportDebug "execute-modulerc: $modfile"

   set ModulesCurrentModulefile $modfile

   if {![checkValidModule $modfile]} {
      reportInternalBug "Magic cookie '#%Module' missing in '$modfile'"
      return ""
   }

   set modname [file dirname [currentModuleName]]

   if {![info exists g_rcfilesSourced($modfile)]} {
      reportDebug "execute-modulerc: sourcing rc $modfile"
      set slave __.modulerc
      if {![interp exists $slave]} {
         interp create $slave
         interp alias $slave uname {} uname
         interp alias $slave system {} system
         interp alias $slave module-version {} module-version
         interp alias $slave module-alias {} module-alias
         interp alias $slave module {} module
         interp alias $slave reportInternalBug {} reportInternalBug

         interp eval $slave {global ModulesCurrentModulefile g_debug}
         interp eval $slave [list "global" "ModulesVersion"]
         interp eval $slave [list "set" "ModulesCurrentModulefile" $modfile]
         interp eval $slave [list "set" "g_debug" $g_debug]
         interp eval $slave {set ModulesVersion {}}
      }
      set ModulesVersion [interp eval $slave {
         if [catch {source $ModulesCurrentModulefile} errorMsg] {
            global errorInfo

            reportInternalBug "Occurred in file\
               $ModulesCurrentModulefile:$errorInfo"
            exit 1
         }\
         elseif [info exists ModulesVersion] {
            return $ModulesVersion
         } else {
            return {}
         }
      }]

      interp delete $slave

      if {[file tail $modfile] eq ".version" && $ModulesVersion ne ""} {
         # only set g_moduleDefault if .version file,
         # otherwise any modulerc settings ala "module-version /xxx default"
         #  would get overwritten
         set g_moduleDefault($modname) $ModulesVersion
         reportDebug "execute-version: Setting g_moduleDefault($modname)\
            $ModulesVersion"
      }

      # Keep track of rc files we already sourced so we don't run them again
      set g_rcfilesSourced($modfile) $ModulesVersion
   }
   return $g_rcfilesSourced($modfile)
}


########################################################################
# commands run from inside a module file
#
set ModulesCurrentModulefile {}

proc module-info {what {more {}}} {
   global g_shellType g_shell tcl_platform

   set mode [currentMode]

   reportDebug "module-info: $what $more  mode=$mode"

   switch -- $what {
      "mode" {
         if {$more ne ""} {
            if {$mode eq $more} {
               return 1
            } else {
               return 0
            }
         } else {
            return $mode
         }
      }
      "name" -
      "specified" {
         return [currentModuleName]
      }
      "shell" {
         return $g_shell
      }
      "flags" {
         return 0
      }
      "shelltype" {
         return $g_shellType
      }
      "user" {
         return $tcl_platform(user)
      }
      "alias" {
         set ret [resolveModuleVersionOrAlias $more "alias"]
         if {$ret ne $more} {
            return $ret
         } else {
            return {}
         }
      }
      "trace" {
         return {}
      }
      "tracepat" {
         return {}
      }
      "type" {
         return "Tcl"
      }
      "symbols" {
         return [join [getVersAliasList $more] ":"]
      }
      "version" {
         lassign [getModuleNameVersion $more] mod
         return [resolveModuleVersionOrAlias $mod]
      }
      default {
         error "module-info $what not supported"
         return {}
      }
   }
}

proc module-whatis {message} {
   global g_whatis

   set mode [currentMode]

   reportDebug "module-whatis: $message  mode=$mode"

   if {$mode eq "display"} {
      report "module-whatis\t$message"
   }\
   elseif {$mode eq "whatis"} {
      set g_whatis $message
   }
   return {}
}

# Determine with a name provided as argument the corresponding module name,
# version and name/version. Module name is guessed from current module name
# when shorthand version notation is used. Both name and version are guessed
# from current module if name provided is empty
proc getModuleNameVersion {{name {}}} {
   set curmod [currentModuleName]
   set curmodname [file dirname $curmod]
   set curmodversion [file tail $curmod]

   if {$name eq ""} {
      set name $curmodname
      set version $curmodversion
   # check for shorthand version notation like "/version" or "./version"
   } elseif {[regexp {^\.?\/(.*)$} $name match version]} {
      # if we cannot distinguish a module name, raise error when
      # shorthand version notation is used
      global ModulesCurrentModulefile
      if {$ModulesCurrentModulefile ne $curmod} {
         # name is the name of current module directory
         set name $curmodname
      } else {
         reportError "Invalid modulename '$name' found"
         return {}
      }
   } else {
      set version [file tail $name]
      if {$name eq $version} {
         set version ""
      } else {
         set name [file dirname $name]
         # clear version if default
         if {$version eq "default"} {
            set version ""
         }
      }
      # name may correspond to last part of current module
      # if so name is replaced by current module name
      if {[file tail $curmodname] eq $name} {
         set name $curmodname
      }
   }

   if {$version eq ""} {
      set mod $name
   } else {
      set mod $name/$version
   }

   return [list $mod $name $version]
}

# Specifies a default or alias version for a module that points to an 
# existing module version Note that aliases defaults are stored by the
# short module name (not the full path) so aliases and defaults from one
# directory will apply to modules of the same name found in other
# directories.
proc module-version {args} {
   global g_moduleVersion g_versionHash
   global g_moduleDefault
   global ModulesCurrentModulefile

   reportDebug "module-version: executing module-version $args"
   lassign [getModuleNameVersion [lindex $args 0]] mod modname modversion

   foreach version [lrange $args 1 end] {
      if {[string match $version "default"]} {
         # If we see more than one default for the same module, just
         # keep the first
         if {![info exists g_moduleDefault($modname)]} {
            set g_moduleDefault($modname) $modversion
            reportDebug "module-version: default $modname = $modversion"
         }
      } else {
         set aliasversion "$modname/$version"
         reportDebug "module-version: alias $aliasversion = $mod"

         if {![info exists g_moduleVersion($aliasversion)]} {
            set g_moduleVersion($aliasversion) $mod

            # don't add duplicates
            if {![info exists g_versionHash($mod)] ||\
               [lsearch -exact $g_versionHash($mod) $version] < 0} {
               lappend g_versionHash($mod) $version
            }
         } else {
            reportWarning "Duplicate version symbol '$version' found"
         }
      }
   }

   if {[string match [currentMode] "display"]} {
      report "module-version\t$args"
   }
   return {}
}

proc module-alias {args} {
   global g_moduleAlias g_aliasHash

   lassign [getModuleNameVersion [lindex $args 0]] alias
   lassign [getModuleNameVersion [lindex $args 1]] mod

   reportDebug "module-alias: $alias = $mod"

   set g_moduleAlias($alias) $mod
   set g_aliasHash($mod) $alias

   if {[string match [currentMode] "display"]} {
      report "module-alias\t$args"
   }

   return {}
}

proc module {command args} {
   set mode [currentMode]

   # guess if called from top level
   set topcall [expr {[info level] == 1}]
   if {$topcall} {
      set msgprefix ""
   } else {
      set msgprefix "module: "
   }

   switch -regexp -- $command {
      {^(add|lo)} {
         if {[llength $args] == 0} {
            set errormsg "Unexpected number of args for 'load' command"
         } else {
            if {$topcall || $mode eq "load"} {
               eval cmdModuleLoad $args
            }\
            elseif {$mode eq "unload"} {
               eval cmdModuleUnload $args
            }\
            elseif {$mode eq "display"} {
               report "module load\t$args"
            }
            set needrender 1
         }
      }
      {^(rm|unlo)} {
         if {[llength $args] == 0} {
            set errormsg "Unexpected number of args for 'unload' command"
         } else {
            if {$topcall || $mode eq "load"} {
               eval cmdModuleUnload $args
            }\
            elseif {$mode eq "unload"} {
               eval cmdModuleUnload $args
            }\
            elseif {$mode eq "display"} {
               report "module unload\t$args"
            }
            set needrender 1
         }
      }
      {^rel} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'reload' command"
         } else {
            cmdModuleReload
            set needrender 1
         }
      }
      {^use$} {
         eval cmdModuleUse $args
         set needrender 1
      }
      {^unuse$} {
         eval cmdModuleUnuse $args
         set needrender 1
      }
      {^source$} {
         if {[llength $args] == 0} {
            set errormsg "Unexpected number of args for 'source' command"
         } else {
            eval cmdModuleSource $args
            set needrender 1
         }
      }
      {^sw} {
         if {[llength $args] == 0 || [llength $args] > 2} {
            set errormsg "Unexpected number of args for 'switch' command"
         } else {
            eval cmdModuleSwitch $args
            set needrender 1
         }
      }
      {^(di|show)} {
         if {[llength $args] == 0} {
            set errormsg "Unexpected number of args for 'show' command"
         } else {
            foreach arg $args {
               eval cmdModuleDisplay $arg
            }
            set needrender 1
         }
      }
      {^av} {
         if {$args ne ""} {
            foreach arg $args {
               cmdModuleAvail $arg
            }
         } else {
            cmdModuleAvail

            # Not sure if this should be a part of cmdModuleAvail or not
            cmdModuleAliases
         }
      }
      {^al} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'aliases' command"
         } else {
            cmdModuleAliases
         }
      }
      {^path$} {
         if {[llength $args] != 1} {
            set errormsg "Unexpected number of args for 'path' command"
         } else {
            eval cmdModulePath $args
            set needrender 1
         }
      }
      {^paths$} {
         if {[llength $args] != 1} {
            set errormsg "Unexpected number of args for 'paths' command"
         } else {
            eval cmdModulePaths $args
            set needrender 1
         }
      }
      {^li} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'list' command"
         } else {
            cmdModuleList
         }
      }
      {^wh} {
         if {$args ne ""} {
            foreach arg $args {
               cmdModuleWhatIs $arg
            }
         } else {
            cmdModuleWhatIs
         }
      }
      {^(apropos|search|keyword)$} {
         if {[llength $args] > 1} {
            set errormsg "Unexpected number of args for '$command' command"
         } else {
            eval cmdModuleApropos $args
         }
      }
      {^pu} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'purge' command"
         } else {
            eval cmdModulePurge
            set needrender 1
         }
      }
      {^save$} {
         if {[llength $args] > 1} {
            set errormsg "Unexpected number of args for 'save' command"
         } else {
            eval cmdModuleSave $args
         }
      }
      {^restore$} {
         if {[llength $args] > 1} {
            set errormsg "Unexpected number of args for 'restore' command"
         } else {
            eval cmdModuleRestore $args
            set needrender 1
         }
      }
      {^saverm$} {
         if {[llength $args] > 1} {
            set errormsg "Unexpected number of args for 'saverm' command"
         } else {
            eval cmdModuleSaverm $args
         }
      }
      {^saveshow$} {
         if {[llength $args] > 1} {
            set errormsg "Unexpected number of args for 'saveshow' command"
         } else {
            eval cmdModuleSaveshow $args
         }
      }
      {^savelist$} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'savelist' command"
         } else {
            cmdModuleSavelist
         }
      }
      {^init(add|lo)$} {
         if {[llength $args] != 1} {
            set errormsg "Unexpected number of args for 'initadd' command"
         } else {
            eval cmdModuleInit add $args
         }
      }
      {^initprepend$} {
         if {[llength $args] != 1} {
            set errormsg "Unexpected number of args for 'initprepend' command"
         } else {
            eval cmdModuleInit prepend $args
         }
      }
      {^initswitch$} {
         if {[llength $args] != 2} {
            set errormsg "Unexpected number of args for 'initswitch' command"
         } else {
            eval cmdModuleInit switch $args
         }
      }
      {^init(rm|unlo)$} {
         if {[llength $args] != 1} {
            set errormsg "Unexpected number of args for 'initrm' command"
         } else {
            eval cmdModuleInit rm $args
         }
      }
      {^initlist$} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'initlist' command"
         } else {
            eval cmdModuleInit list $args
         }
      }
      {^initclear$} {
         if {[llength $args] != 0} {
            set errormsg "Unexpected number of args for 'initclear' command"
         } else {
            eval cmdModuleInit clear $args
         }
      }
      {^debug$} {
         if {$topcall} {
            if {[llength $args] != 0} {
               set errormsg "Unexpected number of args for 'debug' command"
            } else {
               eval cmdModuleDebug
            }
         } else {
            # debug cannot be called elsewhere than from top level
            set errormsg "${msgprefix}Command '$command' not supported"
         }
      }
      {^autoinit$} {
         if {$topcall} {
            if {[llength $args] != 0} {
               set errormsg "Unexpected number of args for 'autoinit' command"
            } else {
               cmdModuleAutoinit
               set needrender 1
            }
         } else {
            # autoinit cannot be called elsewhere than from top level
            set errormsg "${msgprefix}Command '$command' not supported"
         }
      }
      {^($|help)} {
         if {$topcall} {
            eval cmdModuleHelp $args
            if {[llength $args] != 0} {
               set needrender 1
            }
         } else {
            # help cannot be called elsewhere than from top level
            set errormsg "${msgprefix}Command '$command' not supported"
         }
      }
      . {
         set errormsg "${msgprefix}Invalid command '$command'"
      }
   }

   # if an error need to be raised, proceed differently depending of
   # call level: if called from top level render errors then raise error
   # elsewhere call is made from a modulefile or modulerc and error
   # will be managed from execute-modulefile or execute-modulerc
   if {[info exists errormsg]} {
      if {$topcall} {
         reportErrorAndExit "$errormsg\nTry 'module --help'\
            for more information."
      } else {
         error "$errormsg"
      }
   # if called from top level render settings if any
   } elseif {$topcall && [info exists needrender]} {
      renderSettings
   }

   return {}
}

proc setenv {var val} {
   global g_stateEnvVars env

   set mode [currentMode]

   reportDebug "setenv: ($var,$val) mode = $mode"

   if {$mode eq "load"} {
      set env($var) $val
      set g_stateEnvVars($var) "new"
   }\
   elseif {$mode eq "unload"} {
      # Don't unset-env here ... it breaks modulefiles
      # that use env(var) is later in the modulefile
      #unset-env $var
      set g_stateEnvVars($var) "del"
   }\
   elseif {$mode eq "display"} {
      # Let display set the variable for later use in the display
      # but don't commit it to the env
      set env($var) $val
      set g_stateEnvVars($var) "nop"
      report "setenv\t\t$var\t$val"
   }
   return {}
}

proc getenv {var} {
   set mode [currentMode]

   reportDebug "getenv: ($var) mode = $mode"

   if {$mode eq "load" || $mode eq "unload"} {
      if {[info exists env($var)]} {
         return $::env($var)
      } else {
         return "_UNDEFINED_"
      }
   }\
   elseif {$mode eq "display"} {
      return "\$$var"
   }
   return {}
}

proc unsetenv {var {val {}}} {
   global g_stateEnvVars env

   set mode [currentMode]

   reportDebug "unsetenv: ($var,$val) mode = $mode"

   if {$mode eq "load"} {
      if {[info exists env($var)]} {
         unset-env $var
      }
      set g_stateEnvVars($var) "del"
   }\
   elseif {$mode eq "unload"} {
      if {$val ne ""} {
         set env($var) $val
         set g_stateEnvVars($var) "new"
      }
   }\
   elseif {$mode eq "display"} {
      report "unsetenv\t\t$var"
   }
   return {}
}

########################################################################
# path fiddling
#
proc getReferenceCountArray {var separator} {
   global env g_force g_def_separator g_debug

   reportDebug "getReferenceCountArray: ($var, $separator)"

   set sharevar "${var}_modshare"
   set modshareok 1
   if {[info exists env($sharevar)]} {
      if {[info exists env($var)]} {
         set modsharelist [split $env($sharevar) $g_def_separator]
         set temp [expr {[llength $modsharelist] % 2}]

         if {$temp == 0} {
            array set countarr $modsharelist

            # sanity check the modshare list
            array set fixers {}
            array set usagearr {}

            foreach dir [split $env($var) $separator] {
               set usagearr($dir) 1
            }
            foreach path [array names countarr] {
               if {! [info exists usagearr($path)]} {
                  unset countarr($path)
                  set fixers($path) 1
               }
            }

            foreach path [array names usagearr] {
               if {! [info exists countarr($path)]} {
                  set countarr($path) 999999999
               }
            }

            if {! $g_force} {
               if {[array size fixers]} {
                  reportWarning "\$$var does not agree with\
                     \$${var}_modshare counter. The following\
                     directories' usage counters were adjusted to match.\
                     Note that this may mean that module unloading may\
                     not work correctly."
                  foreach dir [array names fixers] {
                     report " $dir" -nonewline
                  }
                  report ""
               }
            }
         } else {
            # sharevar was corrupted, odd number of elements.
            set modshareok 0
         }
      } else {
         reportWarning "$sharevar exists ( $env($sharevar) ), but $var\
            doesn't. Environment is corrupted."
         set modshareok 0
      }
   } else {
      set modshareok 0
   }

   if {$modshareok == 0 && [info exists env($var)]} {
      array set countarr {}
      foreach dir [split $env($var) $separator] {
         set countarr($dir) 1
      }
   }
   return [array get countarr]
}


proc unload-path {var path separator} {
   global g_stateEnvVars env g_force g_def_separator

   array set countarr [getReferenceCountArray $var $separator]

   reportDebug "unload-path: ($var, $path, $separator)"

   # Don't worry about dealing with this variable if it is already scheduled
   #  for deletion
   if {[info exists g_stateEnvVars($var)] && $g_stateEnvVars($var) eq "del"} {
      return {}
   }

   foreach dir [split $path $separator] {
      set doit 0

      if {[info exists countarr($dir)]} {
         incr countarr($dir) -1
         if {$countarr($dir) <= 0} {
            set doit 1
            unset countarr($dir)
         }
      } else {
         set doit 1
      }

      if {$doit || $g_force} {
         if {[info exists env($var)]} {
            set dirs [split $env($var) $separator]
            set newpath ""
            foreach elem $dirs {
               if {$elem ne $dir} {
                  lappend newpath $elem
               }
            }
            if {$newpath eq ""} {
               unset-env $var
               set g_stateEnvVars($var) "del"
            } else {
               set env($var) [join $newpath $separator]
               set g_stateEnvVars($var) "new"
            }
         }
      }
   }

   set sharevar "${var}_modshare"
   if {[array size countarr] > 0} {
      set env($sharevar) [join [array get countarr] $g_def_separator]
      set g_stateEnvVars($sharevar) "new"
   } else {
      unset-env $sharevar
      set g_stateEnvVars($sharevar) "del"
   }
   return {}
}

proc add-path {var path pos separator} {
   global env g_stateEnvVars g_def_separator

   reportDebug "add-path: ($var, $path, $separator)"

   set sharevar "${var}_modshare"
   array set countarr [getReferenceCountArray $var $separator]

   if {$pos eq "prepend"} {
      set pathelems [lreverse [split $path $separator]]
   } else {
      set pathelems [split $path $separator]
   }
   foreach dir $pathelems {
      if {[info exists countarr($dir)]} {
         # already see $dir in $var"
         incr countarr($dir)
      } else {
         if {[info exists env($var)] && $env($var) ne ""} {
            if {$pos eq "prepend"} {
               set env($var) "$dir$separator$env($var)"
            }\
            elseif {$pos eq "append"} {
               set env($var) "$env($var)$separator$dir"
            } else {
               error "add-path doesn't support $pos"
            }
         } else {
            set env($var) "$dir"
         }
         set countarr($dir) 1
      }
      reportDebug "add-path: env($var) = $env($var)"
   }

   set env($sharevar) [join [array get countarr] $g_def_separator]
   set g_stateEnvVars($var) "new"
   set g_stateEnvVars($sharevar) "new"
   return {}
}

proc prepend-path {var path args} {
   global g_def_separator

   set mode [currentMode]

   reportDebug "prepend-path: ($var, $path, $args) mode=$mode"

   if {($var eq "--delim") || ($var eq "-d") || ($var eq "-delim")} {
      set separator $path
      set var [lindex $args 0]
      set path [lindex $args 1]
   } else {
      set separator $g_def_separator
   }

   if {$mode eq "load"} {
      add-path $var $path "prepend" $separator
   }\
   elseif {$mode eq "unload"} {
      unload-path $var $path $separator
   }\
   elseif {$mode eq "display"} {
      report "prepend-path\t$var\t$path"
   }

   return {}
}


proc append-path {var path args} {
   global g_def_separator

   set mode [currentMode]

   reportDebug "append-path: ($var, $path, $args) mode=$mode"

   if {($var eq "--delim") || ($var eq "-d") || ($var eq "-delim")} {
      set separator $path
      set var [lindex $args 0]
      set path [lindex $args 1]
   } else {
      set separator $g_def_separator
   }

   if {$mode eq "load"} {
      add-path $var $path "append" $separator
   }\
   elseif {$mode eq "unload"} {
      unload-path $var $path $separator
   }\
   elseif {$mode eq "display"} {
      report "append-path\t$var\t$path"
   }

   return {}
}

proc remove-path {var path args} {
   global g_def_separator

   set mode [currentMode]

   reportDebug "remove-path: ($var, $path, $args) mode=$mode"

   if {($var eq "--delim") || ($var eq "-d") || ($var eq "-delim")} {
      set separator $path
      set var [lindex $args 0]
      set path [lindex $args 1]
   } else {
      set separator $g_def_separator
   }

   if {$mode eq "load"} {
      unload-path $var $path $separator
   }\
   elseif {$mode eq "display"} {
      report "remove-path\t$var\t$path"
   }
   return {}
}

proc set-alias {alias what} {
   global g_Aliases g_stateAliases
   set mode [currentMode]

   reportDebug "set-alias: ($alias, $what) mode=$mode"
   if {$mode eq "load"} {
      set g_Aliases($alias) $what
      set g_stateAliases($alias) "new"
   }\
   elseif {$mode eq "unload"} {
      set g_Aliases($alias) {}
      set g_stateAliases($alias) "del"
   }\
   elseif {$mode eq "display"} {
      report "set-alias\t$alias\t$what"
   }

   return {}
}

proc unset-alias {alias} {
   global g_Aliases g_stateAliases

   set mode [currentMode]

   reportDebug "unset-alias: ($alias) mode=$mode"
   if {$mode eq "load"} {
      set g_Aliases($alias) {}
      set g_stateAliases($alias) "del"
   }\
   elseif {$mode eq "display"} {
      report "unset-alias\t$alias"
   }

   return {}
}

proc is-loaded {modulelist} {
   reportDebug "is-loaded: $modulelist"

   if {[llength $modulelist] > 0} {
      set loadedmodlist [getLoadedModuleList]
      if {[llength $loadedmodlist] > 0} {
         foreach arg $modulelist {
            set arg "$arg/"
            foreach mod $loadedmodlist {
               set mod "$mod/"
               if {[string first $arg $mod] == 0} {
                  return 1
               }
            }
         }
         return 0
      } else {
         return 0
      }
   }
   return 1
}

proc conflict {args} {
   set mode [currentMode]
   set currentModule [currentModuleName]

   reportDebug "conflict: ($args) mode = $mode"

   if {$mode eq "load"} {
      foreach mod $args {
         # If the current module is already loaded, we can proceed
         if {![is-loaded $currentModule]} {
            # otherwise if the conflict module is loaded, we cannot
            if {[is-loaded $mod]} {
               set errMsg "WARNING: $currentModule cannot be loaded due\
                  to a conflict."
               set errMsg "$errMsg\nHINT: Might try \"module unload\
                  $mod\" first."
               error $errMsg
            }
         }
      }
   }\
   elseif {$mode eq "display"} {
      report "conflict\t$args"
   }

   return {}
}

proc prereq {args} {
   set mode [currentMode]
   set currentModule [currentModuleName]

   reportDebug "prereq: ($args) mode = $mode"

   if {$mode eq "load"} {
      if {![is-loaded $args]} {
         set errMsg "WARNING: $currentModule cannot be loaded due to\
             missing prereq."
         # adapt error message when multiple modules are specified
         if {[llength $args] > 1} {
            set errMsg "$errMsg\nHINT: at least one of the following\
               modules must be loaded first: $args"
         } else {
            set errMsg "$errMsg\nHINT: the following module must be\
               loaded first: $args"
         }
         error $errMsg
      }
   }\
   elseif {$mode eq "display"} {
      report "prereq\t\t$args"
   }

   return {}
}

proc x-resource {resource {value {}}} {
   global g_newXResources g_delXResources

   set mode [currentMode]

   reportDebug "x-resource: ($resource, $value)"

   # sometimes x-resource value may be provided within resource name
   # as the "x-resource {Ileaf.popup.saveUnder: True}" example provided
   # in manpage. so here is an attempt to extract real resource name and
   # value from resource argument
   if {[string length $value] == 0 && ![file exists $resource]} {
      # look first for a space character as delimiter, then for a colon
      set sepapos [string first " " $resource]
      if { $sepapos == -1 } {
         set sepapos [string first ":" $resource]
      }

      if { $sepapos > -1 } {
         set value [string range $resource [expr {$sepapos + 1}] end]
         set resource [string range $resource 0 [expr {$sepapos - 1}]]
         reportDebug "x-resource: corrected ($resource, $value)"
      } else {
         # if not a file and no value provided x-resource cannot be
         # recorded as it will produce an error when passed to xrdb
         reportWarning "x-resource $resource is not a valid string or file"
         return {}
      }
   }

   # if a resource does hold an empty value in g_newXResources or
   # g_delXResources arrays, it means this is a resource file to parse
   if {$mode eq "load"} {
      set g_newXResources($resource) $value
   }\
   elseif {$mode eq "unload"} {
      set g_delXResources($resource) $value
   }\
   elseif {$mode eq "display"} {
      report "x-resource\t$resource\t$value"
   }

   return {}
}

proc uname {what} {
   global unameCache tcl_platform
   set result {}

   reportDebug "uname: called: $what"

   if {! [info exists unameCache($what)]} {
      switch -- $what {
         sysname {
            set result $tcl_platform(os)
         }
         machine {
            set result $tcl_platform(machine)
         }
         nodename - node {
            set result [info hostname]
         }
         release {
            # on ubuntu get the CODENAME of the Distribution
            if { [file isfile /etc/lsb-release]} {
               set fd [open "/etc/lsb-release" "r"]
               set a [read $fd]
               regexp -nocase {DISTRIB_CODENAME=(\S+)(.*)}\
                  $a matched res end
               set result $res
            } else {
               set result $tcl_platform(osVersion)
            }
         }
         domain {
            set result [exec /bin/domainname]
         }
         version {
            if { [file isfile /bin/uname]} {
               set result [exec /bin/uname -v]
            } else {
               set result [exec /usr/bin/uname -v]
            }
         }
         default {
            error "uname $what not supported"
         }
      }
      set unameCache($what) $result
   }

   return $unameCache($what)
}

########################################################################
# internal module procedures
#
set g_modeStack {}

proc currentMode {} {
   global g_modeStack

   set mode [lindex $g_modeStack end]

   return $mode
}

proc pushMode {mode} {
   global g_modeStack

   lappend g_modeStack $mode
}

proc popMode {} {
   global g_modeStack

   set len [llength $g_modeStack]
   set len [expr {$len - 2}]
   set g_modeStack [lrange $g_modeStack 0 $len]
}

set g_moduleNameStack {}

proc currentModuleName {} {
   global g_moduleNameStack

   set moduleName [lindex $g_moduleNameStack end]
   return $moduleName
}

proc pushModuleName {moduleName} {
   global g_moduleNameStack

   lappend g_moduleNameStack $moduleName
}

proc popModuleName {} {
   global g_moduleNameStack

   set len [llength $g_moduleNameStack]
   set len [expr {$len - 2}]
   set g_moduleNameStack [lrange $g_moduleNameStack 0 $len]
}

# return list of loaded modules by parsing LOADEDMODULES env variable
proc getLoadedModuleList {} {
   global env g_def_separator

   if {[info exists env(LOADEDMODULES)]} {
      return [split $env(LOADEDMODULES) $g_def_separator]
   } else {
      return {}
   }
}

# return list of module paths by parsing MODULEPATH env variable
# behavior param enables to exit in error when no MODULEPATH env variable
# is set. by default an empty list is returned if no MODULEPATH set
proc getModulePathList {{behavior "returnempty"}} {
   global env g_def_separator

   if {[info exists env(MODULEPATH)]} {
      return [split $env(MODULEPATH) $g_def_separator]
   } elseif {$behavior eq "exiterronundef"} {
      reportErrorAndExit "No module path defined"
   } else {
      return {}
   }
}

# Return the full pathname and modulename to the module.  
# Resolve aliases and default versions if the module name is something like
# "name/version" or just "name" (find default version).
proc getPathToModule {mod} {
   global g_loadedModulesGeneric

   set retlist ""

   if {$mod eq ""} {
      return ""
   }

   reportDebug "getPathToModule: Finding $mod"

   # Check for $mod specified as a full pathname
   if {[string match {/*} $mod]} {
      if {[file exists $mod]} {
         if {[file readable $mod]} {
            if {[file isfile $mod]} {
               # note that a raw filename as an argument returns the full
               # path as the module name
               if {[checkValidModule $mod]} {
                  return [list $mod $mod]
               } else {
                  reportError "Unable to locate a modulefile for '$mod'"
                  return ""
               }
            }
         }
      }
   } else {
      # modparent is the the modulename minus the module version.
      lassign [getModuleNameVersion $mod] mod modparent modversion

      # Now search for $mod in module paths
      foreach dir [getModulePathList "exiterronundef"] {
         set path "$dir/$mod"
         set modparentpath "$dir/$modparent"

         # Search all parent directories (between modulepath dir and mod)
         # for .modulerc files in case we need to translate an alias
         set parentlist [split $mod "/"]
         set parentname [lindex $parentlist 0]
         set parentpath $dir/$parentname
         set i 1
         while {[file isdirectory $parentpath] && $parentpath ne $path} {
            # Execute any modulerc found on path toward modparent
            if {[file exists "$parentpath/.modulerc"]} {
               reportDebug "getPathToModule: Found\
                  $parentpath/.modulerc"
               # push name to be found by module-alias and version
               pushModuleName $parentname/.modulerc
               execute-modulerc $parentpath/.modulerc
               popModuleName
            }
            append parentname "/[lindex $parentlist $i]"
            append parentpath "/[lindex $parentlist $i]"
            incr i
         }

         # Check for an alias set by .modulerc found on parent path
         # or by a previously looked modulefile/modulerc
         set newmod [resolveModuleVersionOrAlias $mod]
         if {$newmod ne $mod} {
            return [getPathToModule $newmod]
         }

         # look if we can find mod in dir
         if {[file readable $path]} {
            set prevpath ""
            # loop to resolve correct modulefile in case specified mod is a
            # directory that should be analyzed to get default mod in it
            while {$prevpath ne $path} {
               set prevpath $path

               # If a directory, check for .modulerc then .version and if no
               # default found at this stage select last file within the dir
               if {[file isdirectory $path]} {
                  if {[info exists g_loadedModulesGeneric($mod)]} {
                     set ModulesVersion $g_loadedModulesGeneric($mod)
                  } else {
                     set ModulesVersion ""
                     # Execute any modulerc for this module
                     if {[file exists "$path/.modulerc"]} {
                        reportDebug "getPathToModule: Found $path/.modulerc"
                        # push name to be found by module-alias and version
                        pushModuleName $mod/.modulerc
                        execute-modulerc $path/.modulerc
                        popModuleName
                     }
                     # Check for an alias that may have been set by modulerc
                     lassign [getModuleNameVersion\
                        [resolveModuleVersionOrAlias $mod]]\
                        newmod newparent newversion
                     if {$newmod ne $mod} {
                        # if alias resolve to a different modulename then
                        # restart search on this new modulename
                        if {$modparent ne $newparent} {
                           return [getPathToModule $newmod]
                        # elsewhere set version to the alias found
                        } else {
                           set ModulesVersion $newversion
                        }
                     }

                     # now look at .version file that can superseed version
                     # set by modulerc
                     if {[file exists "$path/.version"]} {
                        reportDebug "getPathToModule: Found $path/.version"
                        # push name to be found by module-alias and version
                        pushModuleName $mod/.version
                        set ModulesVersion [execute-modulerc\
                           "$path/.version"]
                        popModuleName
                     }
                  }

                  # Try for the last file in directory if no luck so far
                  if {$ModulesVersion eq ""} {
                     # ask for module element at first path level only
                     set modlist [listModules $path "" 0 "" "no_depth"]
                     set ModulesVersion [lindex $modlist end]
                     reportDebug "getPathToModule: Found\
                        $ModulesVersion in $path"
                  }

                  if {$ModulesVersion ne ""} {
                     set modparent $mod
                     # The path to the module file
                     set path "$path/$ModulesVersion"
                     # The modulename (name + version)
                     set mod "$mod/$ModulesVersion"
                     # if ModulesVersion is a directory keep looking in it
                     # elsewhere we have found a module to return
                     if {![file isdirectory $path]} {
                        if {[file readable $path]} {
                           set retlist [list $path $mod]
                        } else {
                           # if we found a ModulesVersion in this dir but it
                           # points to a non-existent file, raise error and
                           # return
                           reportError "Unable to locate a modulefile for\
                              '$mod'"
                           return ""
                        }
                     }
                  }
               } else {
                  # If mod was a file in this path, try and return that file
                  set retlist [list $path $mod]
               }

               # if we have result, check its validity or raise error
               if {[llength $retlist] == 2} {
                  if {![checkValidModule [lindex $retlist 0]]} {
                     reportInternalBug "Magic cookie '#%Module' missing in\
                        '[lindex $retlist 0]'"
                     return ""
                  } else {
                     return $retlist
                  }
               }
            }
         }
         # File wasn't readable, go to next path
      }
      # End of of foreach loop
      reportError "Unable to locate a modulefile for '$mod'"
      return ""
   }
}

proc runModulerc {} {
   # Runs the global RC files if they exist
   global env
   set rclist {}

   reportDebug "runModulerc: running..."
   reportDebug "runModulerc: env MODULESHOME = $env(MODULESHOME)"
   reportDebug "runModulerc: env HOME = $env(HOME)"
   if {[info exists env(MODULERCFILE)]} {
      # if MODULERCFILE is a dir, look at a modulerc file in it
      if {[file isdirectory $env(MODULERCFILE)]\
         && [file isfile "$env(MODULERCFILE)/modulerc"]} {
         lappend rclist "$env(MODULERCFILE)/modulerc"
      } elseif {[file isfile $env(MODULERCFILE)]} {
         lappend rclist $env(MODULERCFILE)
      }
   }
   if {[info exists env(MODULESHOME)]\
      && [file isfile "$env(MODULESHOME)/etc/rc"]} {
      lappend rclist "$env(MODULESHOME)/etc/rc"
   }
   if {[info exists env(HOME)] && [file isfile "$env(HOME)/.modulerc"]} {
      lappend rclist "$env(HOME)/.modulerc"
   }

   foreach rc $rclist {
      if {[file readable $rc]} {
         reportDebug "runModulerc: Executing $rc"
         cmdModuleSource "$rc"
      }
   }
}

# manage settings to save as a stack to have a separate set of settings
# for each module loaded or unloaded in order to be able to restore the
# correct set in case of failure
proc pushSettings {} {
   foreach var {env g_Aliases g_stateEnvVars g_stateAliases g_newXResource\
      g_delXResource} {
      eval "global g_SAVE_$var $var"
      eval "lappend g_SAVE_$var \[array get $var\]"
   }
}

proc popSettings {} {
   foreach var {env g_Aliases g_stateEnvVars g_stateAliases g_newXResource\
      g_delXResource} {
      eval "global g_SAVE_$var"
      eval "set g_SAVE_$var \[lrange \$g_SAVE_$var 0 end-2\]"
   }
}

proc restoreSettings {} {
   foreach var {env g_Aliases g_stateEnvVars g_stateAliases g_newXResource\
      g_delXResource} {
      eval "global g_SAVE_$var $var"
      # clear current $var arrays
      if {[info exists $var]} {
         eval "unset $var; array set $var {}"
      }
      eval "array set $var \[lindex \$g_SAVE_$var end\]"
   }
}

proc renderSettings {} {
   global env g_Aliases g_shellType g_shell
   global g_stateEnvVars g_stateAliases
   global g_newXResources g_delXResources
   global g_pathList g_systemList error_count
   global g_autoInit CSH_LIMIT

   reportDebug "renderSettings: called."

   set iattempt 0

   # required to work on cygwin, shouldn't hurt real linux
   fconfigure stdout -translation lf

   # preliminaries

   switch -- $g_shellType {
      python {
         puts stdout "import os"
      }
   }

   if {$g_autoInit} {
      global argv0

      # automatically detect which tclsh should be used for 
      # future module commands
      set tclshbin [info nameofexecutable]

      # add cwd if not absolute script path
      if {! [regexp {^/} $argv0]} {
         set pwd [exec pwd]
         set argv0 "$pwd/$argv0"
      }

      set env(MODULESHOME) [file dirname $argv0]
      set g_stateEnvVars(MODULESHOME) "new"

      switch -- $g_shellType {
         csh {
            puts stdout "    alias module 'eval \
               `'$tclshbin' '$argv0' '$g_shell' \\!*`';"
         }
         sh {
            puts stdout "module () { eval \
               `'$tclshbin' '$argv0' '$g_shell' \$*`; } ;"
         }
         fish {
            puts stdout "function module"
            puts stdout "    eval '$tclshbin' '$argv0' '$g_shell' \$argv | source -"
            puts stdout "end"
         }
         tcl {
            puts stdout "proc module {args}  {"
            puts stdout "    global env;"
            puts stdout "    set script {};"
            puts stdout "    if {\[catch { set script \[eval exec\
                \"$tclshbin\" \"$argv0\" \"$g_shell\" \$args] } msg]} {"
            puts stdout "        puts \$msg"
            puts stdout "    };"
            puts stdout "    uplevel \$script;"
            puts stdout "}"

         }
         cmd {
            puts stdout "start /b \%MODULESHOME\%/init/module.cmd %*"
         }
         perl {
            puts stdout "sub module {"
            puts stdout "  eval `$tclshbin\
               \$ENV{\'MODULESHOME\'}/modulecmd.tcl perl @_`;"
            puts stdout "  if(\$@) {"
            puts stdout "    use Carp;"
            puts stdout "    confess \"module-error: \$@\n\";"
            puts stdout "  }"
            puts stdout "  return 1;"
            puts stdout "}"
         }
         python {
            puts stdout "import subprocess"
            puts stdout "def module(command, *arguments):"
            puts stdout "        exec(subprocess.Popen(\['$tclshbin',\
               '$argv0', 'python', command\] +\
               list(arguments),\
               stdout=subprocess.PIPE).communicate()\[0\])"
         }
         lisp {
            reportErrorAndExit "lisp mode autoinit not yet implemented"
         }
      }

      if {[file exists "$env(MODULESHOME)/modulerc"]} {
         cmdModuleSource "$env(MODULESHOME)/modulerc"
      }
      if {[file exists "$env(MODULESHOME)/init/modulerc"]} {
         cmdModuleSource "$env(MODULESHOME)/init/modulerc"
      }
   }

   # new environment variables
   foreach var [array names g_stateEnvVars] {
      if {$g_stateEnvVars($var) eq "new"} {
         switch -- $g_shellType {
            csh {
               set val [multiEscaped $env($var)]
               # csh barfs on long env vars
               if {$g_shell eq "csh" && [string length $val] >\
                  $CSH_LIMIT} {
                  if {$var eq "PATH"} {
                     reportWarning "PATH exceeds $CSH_LIMIT characters,\
                        truncating and appending /usr/bin:/bin ..."
                     set val [string range $val 0 [expr {$CSH_LIMIT\
                        - 1}]]:/usr/bin:/bin
                  } else {
                      reportWarning "$var exceeds $CSH_LIMIT characters,\
                         truncating..."
                      set val [string range $val 0 [expr {$CSH_LIMIT\
                         - 1}]]
                  }
               }
               puts stdout "setenv $var $val;"
            }
            sh {
               puts stdout "$var=[multiEscaped $env($var)];\
                  export $var;"
            }
            fish {
               set val [multiEscaped $env($var)]
               # fish shell has special treatment for PATH variable
               # so its value should be provided as a list separated
               # by spaces not by semi-colons
               if {$var eq "PATH"} {
                  regsub -all ":" $val " " val
               }
               puts stdout "set -xg $var $val;"
            }
            tcl {
               set val [doubleQuoteEscaped $env($var)]
               puts stdout "set env($var) $val;"
            }
            perl {
               set val [doubleQuoteEscaped $env($var)]
               puts stdout "\$ENV{\'$var\'} = \'$val\';"
            }
            python {
               set val [singleQuoteEscaped $env($var)]
               puts stdout "os.environ\['$var'\] = '$val'"
            }
            lisp {
               set val [doubleQuoteEscaped $env($var)]
               puts stdout "(setenv \"$var\" \"$val\")"
            }
            cmd {
               set val $env($var)
               puts stdout "set $var=$val"
            }
         }
      } elseif {$g_stateEnvVars($var) eq "del"} {
         switch -- $g_shellType {
            csh {
               puts stdout "unsetenv $var;"
            }
            sh {
               puts stdout "unset $var;"
            }
            fish {
               puts stdout "set -e $var;"
            }
            tcl {
               puts stdout "unset env($var);"
            }
            cmd {
               puts stdout "set $var="
            }
            perl {
               puts stdout "delete \$ENV{\'$var\'};"
            }
            python {
               puts stdout "os.environ\['$var'\] = ''"
               puts stdout "del os.environ\['$var'\]"
            }
            lisp {
               puts stdout "(setenv \"$var\" nil)"
            }
         }
      }
   }

   foreach var [array names g_stateAliases] {
      if {$g_stateAliases($var) eq "new"} {
         switch -- $g_shellType {
            csh {
               # set val [multiEscaped $g_Aliases($var)]
               set val $g_Aliases($var)
               # Convert $n -> \!\!:n
               regsub -all {\$([0-9]+)} $val {\\!\\!:\1} val
               # Convert $* -> \!*
               regsub -all {\$\*} $val {\\!*} val
               puts stdout "alias $var '$val';"
            }
            sh {
               set val $g_Aliases($var)
               puts stdout "alias $var=\'$val\';"
            }
            fish {
               set val $g_Aliases($var)
               puts stdout "alias $var '$val';"
            }
            tcl {
               set val $g_Aliases($var)
               puts stdout "alias $var \"$val\";"
            }
         }
      } elseif {$g_stateAliases($var) eq "del"} {
         switch -- $g_shellType {
            csh {
               puts stdout "unalias $var;"
            }
            sh {
               puts stdout "unalias $var;"
            }
            fish {
               puts stdout "functions -e $var;"
            }
            tcl {
               puts stdout "unalias $var;"
            }
         }
      }
   }

   # new x resources
   if {[array size g_newXResources] > 0} {
      set xrdb [findExecutable "xrdb"]
      switch -- $g_shellType {
         python {
            puts stdout "import subprocess"
         }
      }
      foreach var [array names g_newXResources] {
         set val $g_newXResources($var)
         # empty val means that var is a file to parse
         if {$val eq ""} {
            switch -regexp -- $g_shellType {
               {^(csh|fish|sh)$} {
                  puts stdout "$xrdb -merge $var;"
               }
               tcl {
                  puts stdout "exec $xrdb -merge $var;"
               }
               perl {
                  puts stdout "system(\"$xrdb -merge $var\");"
               }
               python {
                  set var [singleQuoteEscaped $var]
                  puts stdout "subprocess.Popen(\['$xrdb',\
                     '-merge', '$var'\])"
               }
               lisp {
                  puts stdout "(shell-command-to-string \"$xrdb\
                     -merge $var\")"
               }
            }
         } else {
            switch -regexp -- $g_shellType {
               {^(csh|fish|sh)$} {
                  set var [doubleQuoteEscaped $var]
                  set val [doubleQuoteEscaped $val]
                  puts stdout "echo \"$var: $val\" | $xrdb -merge;"
               }
               tcl {
                  puts stdout "set XRDBPIPE \[open \"|$xrdb -merge\" r+\];"
                  set var [doubleQuoteEscaped $var]
                  set val [doubleQuoteEscaped $val]
                  puts stdout "puts \$XRDBPIPE \"$var: $val\";"
                  puts stdout "close \$XRDBPIPE;"
                  puts stdout "unset XRDBPIPE;"
               }
               perl {
                  puts stdout "open(XRDBPIPE, \"|$xrdb -merge\");"
                  set var [doubleQuoteEscaped $var]
                  set val [doubleQuoteEscaped $val]
                  puts stdout "print XRDBPIPE \"$var: $val\\n\";"
                  puts stdout "close XRDBPIPE;"
               }
               python {
                  set var [singleQuoteEscaped $var]
                  set val [singleQuoteEscaped $val]
                  puts stdout "subprocess.Popen(\['$xrdb', '-merge'\],\
                     stdin=subprocess.PIPE).communicate(input='$var: $val\\n')"
               }
               lisp {
                  puts stdout "(shell-command-to-string \"echo $var:\
                     $val | $xrdb -merge\")"
               }
            }
         }
      }
   }

   if {[array size g_delXResources] > 0} {
      set xrdb [findExecutable "xrdb"]
      set xres_to_del {}
      foreach var [array names g_delXResources] {
         # empty val means that var is a file to parse
         if {$g_delXResources($var) eq ""} {
            # xresource file has to be parsed to find what resources
            # are declared there and need to be unset
            foreach fline [split [exec xrdb -n load $var] "\n"] {
               lappend xres_to_del [lindex [split $fline ":"] 0]
            }
         } else {
            lappend xres_to_del $var
         }
      }

      # xresource strings are unset by emptying their value since there
      # is no command of xrdb that can properly remove one property
      switch -regexp -- $g_shellType {
         {^(csh|fish|sh)$} {
            foreach var $xres_to_del {
               puts stdout "echo \"$var:\" | $xrdb -merge;"
            }
         }
         tcl {
            foreach var $xres_to_del {
               puts stdout "set XRDBPIPE \[open \"|$xrdb -merge\" r+\];"
               set var [doubleQuoteEscaped $var]
               puts stdout "puts \$XRDBPIPE \"$var:\";"
               puts stdout "close \$XRDBPIPE;"
               puts stdout "unset XRDBPIPE;"
            }
         }
         perl {
            foreach var $xres_to_del {
               puts stdout "open(XRDBPIPE, \"|$xrdb -merge\");"
               set var [doubleQuoteEscaped $var]
               puts stdout "print XRDBPIPE \"$var:\\n\";"
               puts stdout "close XRDBPIPE;"
            }
         }
         python {
            puts stdout "import subprocess"
            foreach var $xres_to_del {
               set var [singleQuoteEscaped $var]
               puts stdout "subprocess.Popen(\['$xrdb', '-merge'\],\
                  stdin=subprocess.PIPE).communicate(input='$var:\\n')"
            }
         }
         lisp {
            foreach var $xres_to_del {
               puts stdout "(shell-command-to-string \"echo $var: |\
                  $xrdb -merge\")"
            }
         }
      }
   }

   if {[info exists g_systemList]} {
      foreach var $g_systemList {
         puts stdout "$var;"
      }
   }

   # module path{s,} output
   if {[info exists g_pathList]} {
      foreach var $g_pathList {
         switch -- $g_shellType {
            csh {
               puts stdout "echo '$var';"
            }
            sh {
               puts stdout "echo '$var';"
            }
            fish {
               puts stdout "echo '$var';"
            }
            tcl {
               puts stdout "puts \"$var\";"
            }
            cmd {
               puts stdout "echo '$var'"
            }
            perl {
               puts stdout "print '$var'.\"\\n\";"
            }
            python {
               puts stdout "print '$var'"
            }
            lisp {
               puts stdout "(message \"$var\")"
            }
         }
      }
   }

   set nop 0
   if {$error_count == 0 && ! [tell stdout]} {
      set nop 1
   }

   if {$error_count > 0} {
      renderError
      set nop 0
   } else {
      switch -- $g_shellType {
         perl {
            puts stdout "1;"
         }
      }
   }

   if {$nop} {
      #            nothing written!
      switch -- $g_shellType {
         csh {
            puts "/bin/true;"
         }
         sh {
            puts "/bin/true;"
         }
         fish {
            puts "/bin/true;"
         }
         tcl {
            puts "exec /bin/true;"
         }
         cmd {
            # nothing needed, reserve for future cygwin, MKS, etc
         }
         perl {
            puts "1;"
         }
         python {
            # this is not correct
            puts ""
         }
         lisp {
            puts "t"
         }
      }
   }
}

proc cacheCurrentModules {} {
   global g_loadedModules g_loadedModulesGeneric

   reportDebug "cacheCurrentModules"

   # mark specific as well as generic modules as loaded
   foreach mod [getLoadedModuleList] {
      set g_loadedModules($mod) 1
      set g_loadedModulesGeneric([file dirname $mod]) [file tail $mod]
   }
}

# This proc resolves module aliases or version aliases to the real module name
# and version. A list of already resolved aliases and version is set to detect
# infinite resolution loop. Search may be limited to alias or alias hash, all
# kind of version/alias is looked for by default.
proc resolveModuleVersionOrAlias {name {search "all"} args} {
   global g_moduleVersion g_moduleDefault g_moduleAlias g_aliasHash

   reportDebug "resolveModuleVersionOrAlias: Resolving $name\
      (previously: $args), search for $search"

   # Chop off (default) if it exists
   set x [expr {[string length $name] - 9}]
   if {($x > 0) &&([string range $name $x end] eq "\(default\)")} {
      set name [string range $name 0 [expr {$x -1}]]
      reportDebug "resolveModuleVersionOrAlias: trimming name = \"$name\""
   }

   if {$search ne "aliashash" && [info exists g_moduleAlias($name)]} {
      reportDebug "resolveModuleVersionOrAlias: $name is an alias"
      set ret $g_moduleAlias($name)
   # if we only look for an alias, try to look in hash if not found above
   # and if recursive call to this proc has not been ignited yet
   } elseif {(([llength $args] == 0 && $search eq "alias")\
      || $search eq "aliashash") && [info exists g_aliasHash($name)]} {
      reportDebug "resolveModuleVersionOrAlias: $name is an alias"
      set ret $g_aliasHash($name)
      set search "aliashash"
   # do not look for version resolution if we only look for alias
   } elseif {$search eq "all" && [info exists g_moduleVersion($name)]} {
      reportDebug "resolveModuleVersionOrAlias: $name is a version alias"
      set ret $g_moduleVersion($name)
   # do not look for default resolution if we only look for alias
   } elseif {$search eq "all" && [info exists g_moduleDefault($name)]} {
      reportDebug "resolveModuleVersionOrAlias: found a default for $name"
      set ret "$name/$g_moduleDefault($name)"
   } else {
      reportDebug "resolveModuleVersionOrAlias: $name is nothing special"
      set ret $name
   }

   if {$ret ne $name} {
      if {[lsearch -exact $args $ret] == -1} {
         # add the alias, pseudo version or default to the list of already
         # resolved element in order to detect infinite resolution loop
         lappend args $ret
         # if the alias, pseudo version or default is an alias, we need to
         # resolve it
         set ret [eval resolveModuleVersionOrAlias $ret $search $args]
      } else {
         # resolution loop is detected, set return value to "*undef*" as
         # C-version does
         set ret "*undef*"
         # get version name and report loop error
         lassign [getModuleNameVersion $name] name modname modversion
         reportError "Version symbol '$modversion' loops"
      }
   }

   reportDebug "resolveModuleVersionOrAlias: Resolved to $ret"

   return $ret
}

proc multiEscaped {text} {
   regsub -all {([ \\\t\{\}|<>!;#^$&*"'`()])} $text {\\\1} regsub_tmpstrg
   return $regsub_tmpstrg
}

proc doubleQuoteEscaped {text} {
   regsub -all "\"" $text "\\\"" regsub_tmpstrg
   return $regsub_tmpstrg
}

proc singleQuoteEscaped {text} {
   regsub -all "\'" $text "\\\'" regsub_tmpstrg
   return $regsub_tmpstrg
}

proc findExecutable {cmd} {
   foreach dir {/usr/X11R6/bin /usr/openwin/bin /usr/bin/X11} {
      if {[file executable "$dir/$cmd"]} {
         return "$dir/$cmd"
      }
   }

   return $cmd
}

# Dictionary-style string comparison
# Use dictionary sort of lsort proc to compare two strings in the "string
# compare" fashion (returning -1, 0 or 1). Tcl dictionary-style comparison
# enables to compare software versions (ex: "1.10" is greater than "1.8")
proc stringDictionaryCompare {str1 str2} {
    if {$str1 eq $str2} {
        return 0
    # put both strings in a list, then lsort it and get last element
    } elseif {[lindex [lsort -dictionary [list $str1 $str2]] end] eq $str2} {
        return -1
    } else {
        return 1
    }
}

# provide a lreverse proc for Tcl8.4 and earlier
if {[info commands lreverse] eq ""} {
    proc lreverse l {
        set r {}
        set i [llength $l]
        while {[incr i -1]} {lappend r [lindex $l $i]}
        lappend r [lindex $l 0]
    }
}

# provide a lassign proc for Tcl8.4 and earlier
if {[info commands lassign] eq ""} {
   proc lassign {values args} {
      uplevel 1 [list foreach $args [linsert $values end {}] break]
      lrange $values [llength $args] end
   }
}

proc replaceFromList {list1 item {item2 {}}} {
    set xi [lsearch -exact $list1 $item]

    while {$xi >= 0} {
       if {[string length $item2] == 0} {
          set list1 [lreplace $list1 $xi $xi]
       } else {
          set list1 [lreplace $list1 $xi $xi $item2]
       }
       set xi [lsearch -exact $list1 $item]
    }

    return $list1
}

proc checkValidModule {modfile} {
   reportDebug "checkValidModule: $modfile"

   # Check for valid module
   if {![catch {open $modfile r} fileId]} {
      gets $fileId first_line
      close $fileId
      if {[string first "\#%Module" $first_line] == 0} {
         return 1
      }
   }

   return 0
}

# If given module maps to default or other version aliases, a list of 
# those aliases is returned. This takes module/version as an argument.
# A list of already resolved aliases and default is set to detect
# infinite resolution loop.
proc getVersAliasList {mod args} {
   global g_versionHash g_moduleDefault

   reportDebug "getVersAliasList: $mod (previously: $args)"

   # get module name and version after alias resolution attempt
   lassign [getModuleNameVersion $mod] mod
   lassign [getModuleNameVersion [resolveModuleVersionOrAlias $mod "alias"]]\
      mod modname modversion

   set tag_list {}
   if {[info exists g_versionHash($mod)]} {
      foreach version $g_versionHash($mod) {
         if {[lsearch -exact $tag_list $version] == -1} {
            if {[lsearch -exact $args $modname/$version] == -1} {
               # add pseudo version to the list of already resolved element
               # in order to detect infinite resolution loop
               lappend args $modname/$version
               # concat with any other tag found for modname/version
               set tag_list [concat $tag_list $version\
                  [eval getVersAliasList $modname/$version $args]]
            } else {
               reportError "Version symbol '$modversion' loops"
            }
         }
      }
   }
   if {[info exists g_moduleDefault($modname)]\
      && "$modname/$g_moduleDefault($modname)" eq $mod} {
      if {[lsearch -exact $args $modname] == -1} {
         # add default to the list of already resolved element in order to
         # detect infinite resolution loop
         lappend args $modname
         # concat with any other tag found for modname
         set tag_list [concat $tag_list "default"\
            [eval getVersAliasList $modname $args]]
      } else {
         reportError "Version symbol '$modversion' loops"
      }
   }

   # always dictionary-sort results and remove duplicates
   return [lsort -dictionary -unique $tag_list]
}

# Finds all module versions for mod in the module path dir
proc listModules {dir mod {show_flags {1}} {filter ""} {search "in_depth"}} {
   global ignoreDir ModulesCurrentModulefile
   global flag_default_mf flag_default_dir

   # report flags for directories and modulefiles depending on show_flags
   # procedure argument and global variables
   if {$show_flags && $flag_default_mf} {
      set show_flags_mf 1
   } else {
      set show_flags_mf 0
   }
   if {$show_flags && $flag_default_dir} {
      set show_flags_dir 1
   } else {
      set show_flags_dir 0
   }

   # On Cygwin, glob may change the $dir path if there are symlinks involved
   # So it is safest to reglob the $dir.
   # example:
   # [glob /home/stuff] -> "//homeserver/users0/stuff"

   set dir [glob $dir]
   set full_list [glob -nocomplain "$dir/$mod*"]

   # remove trailing / needed on some platforms
   regsub {\/$} $full_list {} full_list
        
   if {$filter eq "onlydefaults"} {
       # init a control list to correctly set implicit
       # or defined module default version
       set clean_defdefault {}
   }

   set dirlevel 0
   set clean_list {}
   set ModulesVersion {}
   for {set i 0} {$i < [llength $full_list]} {incr i 1} {
      set element [lindex $full_list $i]
      set tag_list {}

      # Cygwin TCL likes to append ".lnk" to the end of symbolic links.
      # This is not necessary and pollutes the module names, so let's
      # trim it off.
      if { [isWin] } {
         regsub {\.lnk$} $element {} element
      }

      set tail [file tail $element]
      set direlem [file dirname $element]

      set sstart [expr {[string length $dir] +1}]
      set modulename [string range $element $sstart end]

      if {[file isdirectory $element] && [file readable $element]} {
         set ModulesVersion ""

         reportDebug "listModules: found $element"

         if {![info exists ignoreDir($tail)]} {
            # in depth module listing includes .modulerc and .version file
            if {$search eq "in_depth"} {
               if {[file readable $element/.modulerc]} {
                  lappend full_list $element/.modulerc
               }
               if {[file readable $element/.version]} {
                  lappend full_list $element/.version
               }
            }

            # not in depth module listing stops at first directory level
            if {$search eq "in_depth" || $dirlevel == 0} {
               # Add each element in the current directory to the list
               foreach f [glob -nocomplain "$element/*"] {
                  lappend full_list $f
               }
               incr dirlevel

               # if element is directory AND default or a version alias, add
               # it to the list
               set tag_list [getVersAliasList $modulename]

               set tag {}
               if {[llength $tag_list]} {
                  append tag "(" [join $tag_list ":"] ")"
                  set mystr $modulename

                  # add to list only if it is the default set
                  if {$filter eq "onlydefaults"} {
                     if {[lsearch $tag_list "default"] >= 0} {
                        lappend clean_list $mystr
                     }
                  } else {
                     if {$show_flags_dir} {
                        append mystr $tag
                     }
                     lappend clean_list $mystr
                  }
               }
            # not in depth module listing do not process sub-directories
            # content but add them to the result list
            } else {
               lappend clean_list $modulename
            }
         }
      } else {
         reportDebug "listModules: checking $element ($modulename)\
            show_flags_dir=$show_flags_dir show_flags_mf=$show_flags_mf"
         switch -glob -- $tail {
            {.modulerc} {
               # push name to be found by module-alias and version
               pushModuleName $modulename
               # set is needed for execute-modulerc
               set ModulesCurrentModulefile $element
               execute-modulerc $element
               popModuleName
            }
            {.version} {
               # push name to be found by module-alias and version
               pushModuleName $modulename
               # set is needed for execute-modulerc
               set ModulesCurrentModulefile $element
               execute-modulerc "$element"
               popModuleName

               reportDebug "listModules: checking default $element"
            }
            {.*} - {*~} - {*,v} - {\#*\#} { }
            default {
               if {[checkValidModule $element]} {
                  set tag_list [getVersAliasList $modulename]
                  set tag {}

                  if {[llength $tag_list]} {
                     append tag "(" [join $tag_list ":"] ")"
                  }
                  set mystr $modulename

                  # add to list only if it is the default set
                  # or if it is an implicit default when no default is set
                  if {$filter eq "onlydefaults"} {
                     set moduleelem [string range $direlem $sstart end]

                     # do not add element if a default has already
                     # been added for this module
                     if {[lsearch -exact $clean_defdefault $moduleelem] == -1} {
                        set clean_mystr_idx [lsearch $clean_list "$moduleelem/*"]
                        # only one element has to be set for this module
                        # so replace previously existing element
                        if {$clean_mystr_idx >= 0} {
                           # only replace if new occurency is greater than
                           # existing one or if new occurency is the default set
                           if {[stringDictionaryCompare $mystr \
                              [lindex $clean_list $clean_mystr_idx]] == 1 \
                              || [lsearch $tag_list "default"] >= 0} {
                              set clean_list [lreplace $clean_list \
                                 $clean_mystr_idx $clean_mystr_idx $mystr]
                           }
                        } else {
                           lappend clean_list $mystr
                        }

                        # if default is defined add to control list
                        if {[lsearch $tag_list "default"] >= 0} {
                           lappend clean_defdefault $moduleelem
                        }
                     }

                     # add latest version to list only
                     } elseif {$filter eq "onlylatest"} {
                     set moduleelem [string range $direlem $sstart end]
                     set clean_mystr_idx [lsearch $clean_list "$moduleelem/*"]

                     # only one element has to be set for this module
                     # so replace previously existing element and only
                     # if new occurency is greater than existing one
                     if {$clean_mystr_idx >= 0 && \
                        [stringDictionaryCompare $mystr \
                        [lindex $clean_list $clean_mystr_idx]] == 1} {
                        set clean_list [lreplace $clean_list \
                           $clean_mystr_idx $clean_mystr_idx $mystr]
                     } elseif {$clean_mystr_idx == -1} {
                        lappend clean_list $mystr
                     }
                  } else {
                     if {$show_flags_mf} {
                        append mystr $tag
                     }

                     lappend clean_list $mystr
                  }
               }
            }
         }
      }
   }
   # always dictionary-sort results
   set clean_list [lsort -dictionary $clean_list]
   reportDebug "listModules: Returning $clean_list"

   return $clean_list
}

proc showModulePath {} {
   reportDebug "showModulePath"

   set modpathlist [getModulePathList]
   if {[llength $modpathlist] > 0} {
      report "Search path for module files (in search order):"
      foreach path $modpathlist {
         report "  $path"
      }
   } else {
      reportWarning "No directories on module search path"
   }
}

# get a list of elements and print them in a column or in a
# one-per-line fashion
proc displayElementList {header one_per_line display_idx args} {
   global DEF_COLUMNS

   set elt_cnt [llength $args]
   reportDebug "displayElementList: header=$header, elt_cnt=$elt_cnt,\
      one_per_line=$one_per_line, display_idx=$display_idx"

   # display header if any provided
   if {$header ne "" && $header ne "noheader"} {
      set len  [string length $header]
      set lrep [expr {($DEF_COLUMNS - $len - 2)/2}]
      set rrep [expr {$DEF_COLUMNS - $len - 2 - $lrep}]
      report "[string repeat {-} $lrep] $header [string repeat {-} $rrep]"
   }

   # end proc if no element are to print
   if {$elt_cnt == 0} {
      return
   }

   # display one element per line
   if {$one_per_line} {
      if {$display_idx} {
         set idx 1
         foreach elt $args {
            report [format "%2d) %s " $idx $elt]
            incr idx
         }
      } else {
         foreach elt $args {
            report $elt
         }
      }
   # elsewhere display elements in columns
   } else {
      if {$display_idx} {
         # save room for numbers and spacing: 2 digits + ) + space
         set elt_prefix_len 4
      } else {
         set elt_prefix_len 0
      }
      # save room for two spaces after element
      set elt_suffix_len 2

      # compute rows*cols grid size with optimized column number
      # the size of each column is computed to display as much column
      # as possible on each line
      set old_rows 0
      set rows 1
      set cols 1
      for {set i 0} {$i < $elt_cnt} {incr i} {
         set col_width($i) 0
      }

      # find valid grid by starting with 1 row and increase
      # number of rows until number of cols fit screen width
      while {$old_rows != $rows && $rows <= $elt_cnt} {
         set old_rows $rows
         for {set i 0} {$i < $rows} {incr i} {
            set row_width($i) 0
         }

         for {set i 0} {$i < $elt_cnt} {incr i} {
            set col [expr {int($i / $rows)}]
            set row [expr {$i % $rows}]
            set elt_len [expr {[string length [lindex $args $i]]\
               + $elt_suffix_len}]
            if {$elt_len > $col_width($col)} {
               set col_width($col) $elt_len
               set cols [expr {$col + 1}]
               set old_rows 0
               break
            }
            incr row_width($row) +[expr {$col_width($col) + $elt_prefix_len}]
            if {$row_width($row) > $DEF_COLUMNS} {
               incr rows
               set cols 1
               for {set j 0} {$j < [expr {int($elt_cnt / $rows) + 1}]}\
                  {incr j} {
                  set col_width($j) 0
               }
               break
            }
         }
      }

      reportDebug "displayElementList: list=$args"
      reportDebug "displayElementList: rows/cols=$rows/$cols,\
         lastcol_item_cnt=[expr {int($elt_cnt % $rows)}]"

      for {set row 0} {$row < $rows} {incr row} {
         for {set col 0} {$col < $cols} {incr col} {
            set index [expr {$col * $rows + $row}]
            if {$index < $elt_cnt} {
               if {$display_idx} {
                  report [format "%2d) %-$col_width($col)s"\
                     [expr {$index +1}] [lindex $args $index]] -nonewline
               } else {
                  report [format "%-$col_width($col)s"\
                     [lindex $args $index]] -nonewline
               }
            }
         }

         report ""
      }
   }
}

# build list of what to undo then do to move
# from an initial list to a target list
proc getMovementBetweenList {from to} {
   reportDebug "getMovementBetweenList: from($from) to($to)"

   set undo {}
   set do {}

   # determine what element to undo then do
   # to restore a target list from a current list
   # with preservation of the element order
   set imax [expr {max([llength $to], [llength $from])}]
   set list_equal 1
   for {set i 0} {$i < $imax} {incr i} {
      set to_obj [lindex $to $i]
      set from_obj [lindex $from $i]

      if {$to_obj ne $from_obj} {
         set list_equal 0
      }
      if {$list_equal == 0} {
         if {$to_obj ne ""} {
            lappend do $to_obj
         }
         if {$from_obj ne ""} {
            lappend undo $from_obj
         }
      }
   }

   return [list $undo $do]
}

# build list of currently loaded modules where modulename
# is registered minus module version if loaded version is
# the default one. a helper list may be provided and looked
# at if no module path is set
proc getSimplifiedLoadedModuleList {{helper_raw_list {}}\
   {helper_list {}}} {
   reportDebug "getSimplifiedLoadedModuleList"

   set curr_mod_list {}
   set modpathlist [getModulePathList]
   foreach mod [getLoadedModuleList] {
      if {[string length $mod] > 0} {
         set modparent [file dirname $mod]
         if {$modparent eq "."} {
            lappend curr_mod_list $mod
         } elseif {[llength $modpathlist] > 0} {
            # fetch all module version available
            set modlist {}
            foreach dir $modpathlist {
               if {[file isdirectory $dir]} {
                  set modlist [concat $modlist [listModules $dir $modparent]]
               }
            }

            # check if loaded version is default
            set dflpos [lsearch $modlist "*(default)"]
            if {$dflpos == -1} {
               if {$mod eq [lindex $modlist end]} {
                  lappend curr_mod_list $modparent
               } else {
                  lappend curr_mod_list $mod
               }
            } else {
               if {"$mod\(default\)" eq [lindex $modlist $dflpos]} {
                  lappend curr_mod_list $modparent
               } else {
                  lappend curr_mod_list $mod
               }
            }
         } else {
            # if no path set currently, cannot search for all
            # available version so use helper lists if provided
            set helper_idx [lsearch -exact $helper_raw_list $mod]
            if {$helper_idx == -1} {
               lappend curr_mod_list $mod
            } else {
               # if mod found in a previous LOADEDMODULES list use
               # simplified version of this module found in relative
               # helper list (previously computed simplified list)
               lappend curr_mod_list [lindex $helper_list $helper_idx]
            }
         }
      }
   }

   return $curr_mod_list
}

# get collection target currently set if any.
# a target is a domain on which a collection is only valid.
# when a target is set, only the collections made for that target
# will be available to list and restore, and saving will register
# the target footprint
proc getCollectionTarget {} {
   global env

   if {[info exists env(MODULES_COLLECTION_TARGET)]} {
      return $env(MODULES_COLLECTION_TARGET)
   } else {
      return ""
   }
}

# get filename corresponding to collection name provided as argument.
# name provided may already be a file name. a variable name may also be
# provided to get back collection description (with target info if any)
proc getCollectionFilename {coll {descvar}} {
   global env

   # initialize description with collection name
   # if description variable is set
   if {[info exists descvar]} {
      uplevel 1 set $descvar $coll
   }

   # is collection a filepath
   if {[string first "/" $coll] > -1} {
      # collection target has no influence when
      # collection is specified as a filepath
      set collfile "$coll"
   # elsewhere collection is a name
   } elseif {[info exists env(HOME)]} {
      set collfile "$env(HOME)/.module/$coll"
      # if a target is set, append the suffix corresponding
      # to this target to the collection file name
      set colltarget [getCollectionTarget]
      if {$colltarget ne ""} {
         append collfile ".$colltarget"
         # add knowledge of collection target on description
         if {[info exists descvar]} {
            uplevel 1 append $descvar \" (for target \\"$colltarget\\")\"
         }
      }
   } else {
      reportErrorAndExit "HOME not defined"
   }

   return $collfile
}

# generate collection content based on provided path and module lists
proc formatCollectionContent {path_list mod_list} {
   set content ""

   # start collection content with modulepaths
   foreach path $path_list {
      # 'module use' prepends paths by default so we clarify
      # path order here with --append flag
      append content "module use --append $path" "\n"
   }

   # then add modules
   foreach mod $mod_list {
      append content "module load $mod" "\n"
   }

   return $content
}

# read given collection file and return the path and module lists it defines
proc readCollectionContent {collfile} {
   # init lists (maybe coll does not set mod to load)
   set path_list {}
   set mod_list {}

   # read file
   if {[catch {
      set fid [open $collfile r]
      set fdata [split [read $fid] "\n"]
      close $fid
   } errMsg ]} {
      reportErrorAndExit "Collection $collfile cannot be read.\n$errMsg"
   }

   # analyze collection content
   foreach fline $fdata {
      if {[regexp {module use (.*)$} $fline match patharg] == 1} {
         # paths are appended by default
         set stuff_path "append"
         # manage with "split" multiple paths and path options
         # specified on single line, for instance:
         # module use --append path1 path2 path3
         foreach path [split $patharg] {
            # following path is asked to be appended
            if {($path eq "--append") || ($path eq "-a")\
               || ($path eq "-append")} {
               set stuff_path "append"
            # following path is asked to be prepended
            # collection generated with 'save' does not prepend
            } elseif {($path eq "--prepend") || ($path eq "-p")\
               || ($path eq "-prepend")} {
               set stuff_path "prepend"
            } else {
               # add path to end of list
               if {$stuff_path eq "append"} {
                  lappend path_list $path
               # insert path to first position
               } else {
                  set path_list [linsert $path_list 0 $path]
               }
            }
         }
      } elseif {[regexp {module load (.*)$} $fline match modarg] == 1} {
         # manage multiple modules specified on a
         # single line with "split", for instance:
         # module load mod1 mod2 mod3
         set mod_list [concat $mod_list [split $modarg]]
      }
   }

   return [list $path_list $mod_list]
}


########################################################################
# command line commands
#
proc cmdModuleList {} {
   global show_oneperline show_modtimes
   global g_def_separator

   set loadedmodlist [getLoadedModuleList]

   if {[llength $loadedmodlist] == 0} {
      report "No Modulefiles Currently Loaded."
   } else {
      set list {}
      if {$show_modtimes} {
         report "- Package -----------------------------.- Versions -.- Last\
            mod. ------"
      }
      report "Currently Loaded Modulefiles:"
      set display_list {}
      if {$show_modtimes || $show_oneperline} {
         set display_idx 0
         set one_per_line 1
      } else {
         set display_idx 1
         set one_per_line 0
      }

      foreach mod $loadedmodlist {
         if {[string length $mod] > 0} {
            if {$show_modtimes} {
               set filetime [clock format [file mtime [lindex\
                  [getPathToModule $mod] 0]] -format "%Y/%m/%d %H:%M:%S"]
               lappend display_list [format "%-53s%10s" $mod $filetime]
            }\
            elseif {$show_oneperline} {
               lappend display_list $mod
            } else {
               # skip zero length module names
               # call getPathToModule to find and execute .version and
               # .modulerc files for this module
               getPathToModule $mod
               set tag_list [getVersAliasList $mod]

               if {[llength $tag_list]} {
                  append mod "(" [join $tag_list $g_def_separator] ")"
               }

               lappend display_list $mod
            }
         }
      }

      eval displayElementList "noheader" $one_per_line $display_idx\
         $display_list
   }
}

proc cmdModuleDisplay {mod} {
   lassign [getPathToModule $mod] modfile modname
   if {$modfile ne ""} {
      pushModuleName $modname
      report\
         "-------------------------------------------------------------------"
      report "$modfile:\n"
      pushMode "display"
      execute-modulefile $modfile
      popMode
      popModuleName
      report\
         "-------------------------------------------------------------------"
   }
}

proc cmdModulePaths {mod} {
   global g_pathList

   reportDebug "cmdModulePaths: ($mod)"

   foreach dir [getModulePathList "exiterronundef"] {
      if {[file isdirectory $dir]} {
         foreach mod2 [listModules $dir $mod] {
            lappend g_pathList $mod2
         }
      }
   }
}

proc cmdModulePath {mod} {
   global g_pathList ModulesCurrentModulefile

   reportDebug "cmdModulePath: ($mod)"
   lassign [getPathToModule $mod] modfile modname
   if {$modfile ne ""} {
      set ModulesCurrentModulefile $modfile

      set g_pathList $modfile
   }
}

proc cmdModuleWhatIs {{mod {}}} {
   cmdModuleSearch $mod {}
}

proc cmdModuleApropos {{search {}}} {
   cmdModuleSearch {} $search
}

proc cmdModuleSearch {{mod {}} {search {}}} {
   global g_whatis

   reportDebug "cmdModuleSearch: ($mod, $search)"
   if {$mod eq ""} {
      set mod "*"
   }
   foreach dir [getModulePathList "exiterronundef"] {
      if {[file isdirectory $dir]} {
         set display_list {}

         set modlist [listModules $dir $mod 0]
         foreach mod2 $modlist {
            set g_whatis ""
            lassign [getPathToModule $mod2] modfile modname

            if {$modfile ne ""} {
               pushMode "whatis"
               pushModuleName $modname
               execute-modulefile $modfile
               popMode
               popModuleName

               if {$search eq "" || [regexp -nocase $search $g_whatis]} {
                  lappend display_list [format "%20s: %s" $mod2 $g_whatis]
               }
            }
         }

         eval displayElementList $dir 1 0 $display_list
      }
   }
}

proc cmdModuleSwitch {old {new {}}} {
   global g_loadedModulesGeneric g_loadedModules

   if {$new eq ""} {
      set new $old
   } elseif {[info exists g_loadedModules($new)]} {
      set tmp $new
      set new $old
      set old $tmp
   }

   if {![info exists g_loadedModules($old)] &&
      [info exists g_loadedModulesGeneric($old)]} {
      set old "$old/$g_loadedModulesGeneric($old)"
   }

   reportDebug "cmdModuleSwitch: new=\"$new\" old=\"$old\""

   cmdModuleUnload $old
   cmdModuleLoad $new
}

proc cmdModuleSave {{coll {}}} {
   # default collection used if no name provided
   if {$coll eq ""} {
      set coll "default"
   }
   reportDebug "cmdModuleSave: $coll"

   # format collection content
   set save [formatCollectionContent [getModulePathList] \
      [getSimplifiedLoadedModuleList]]

   if { [string length $save] == 0} {
      reportErrorAndExit "Nothing to save in a collection"
   }

   # get coresponding filename and its directory
   set collfile [getCollectionFilename $coll colldesc]
   set colldir [file dirname $collfile]

   if {![file exists $colldir]} {
      reportDebug "cmdModuleSave: Creating $colldir"
      file mkdir $colldir
   } elseif {![file isdirectory $colldir]} {
      reportErrorAndExit "$colldir exists but is not a directory"
   }

   reportDebug "cmdModuleSave: Saving $collfile"

   if {[catch {
      set fid [open $collfile w]
      puts $fid $save
      close $fid
   } errMsg ]} {
      reportErrorAndExit "Collection $colldesc cannot be saved.\n$errMsg"
   }
}

proc cmdModuleRestore {{coll {}}} {
   # default collection used if no name provided
   if {$coll eq ""} {
      set coll "default"
   }
   reportDebug "cmdModuleRestore: $coll"

   # get coresponding filename
   set collfile [getCollectionFilename $coll colldesc]

   if {![file readable $collfile]} {
      reportErrorAndExit "Collection $colldesc does not exist or is not\
         readable"
   }

   # read collection
   lassign [readCollectionContent $collfile] coll_path_list coll_mod_list

   # collection should at least define a path
   if {[llength $coll_path_list] == 0} {
      reportErrorAndExit "$colldesc is not a valid collection"
   }

   # fetch what is currently loaded
   set curr_path_list [getModulePathList]
   # get current loaded module list in simplified and raw versions
   # these lists may be used later on, see below
   set curr_mod_list_raw [getLoadedModuleList]
   set curr_mod_list [getSimplifiedLoadedModuleList]

   # determine what module to unload to restore collection
   # from current situation with preservation of the load order
   lassign [getMovementBetweenList $curr_mod_list $coll_mod_list] \
      mod_to_unload mod_to_load

   # proceed as well for modulepath
   lassign [getMovementBetweenList $curr_path_list $coll_path_list] \
      path_to_unuse path_to_use

   # unload modules
   if {[llength $mod_to_unload] > 0} {
      eval cmdModuleUnload [lreverse $mod_to_unload]
   }
   # unuse paths
   if {[llength $path_to_unuse] > 0} {
      eval cmdModuleUnuse [lreverse $path_to_unuse]
   }

   # since unloading a module may unload other modules or
   # paths, what to load/use has to be determined after
   # the undo phase, so current situation is fetched again
   set curr_path_list [getModulePathList]

   # here we may be in a situation were no more path is left
   # in module path, so we cannot easily compute the simplified loaded
   # module list. so we provide two helper lists: simplified and raw
   # versions of the loaded module list computed before starting to
   # unload modules. these helper lists may help to learn the
   # simplified counterpart of a loaded module if it was already loaded
   # before starting to unload modules
   set curr_mod_list [getSimplifiedLoadedModuleList\
      $curr_mod_list_raw $curr_mod_list]

   # determine what module to load to restore collection
   # from current situation with preservation of the load order
   lassign [getMovementBetweenList $curr_mod_list $coll_mod_list] \
      mod_to_unload mod_to_load

   # proceed as well for modulepath
   lassign [getMovementBetweenList $curr_path_list $coll_path_list] \
      path_to_unuse path_to_use

   # use paths
   if {[llength $path_to_use] > 0} {
      # always append path here to guaranty the order
      # computed above in the movement lists
      eval cmdModuleUse --append $path_to_use
   }

   # load modules
   if {[llength $mod_to_load] > 0} {
      eval cmdModuleLoad $mod_to_load
   }
}

proc cmdModuleSaverm {{coll {}}} {
   # default collection used if no name provided
   if {$coll eq ""} {
      set coll "default"
   }
   reportDebug "cmdModuleSaverm: $coll"

   # avoid to remove any kind of file with this command
   if {[string first "/" $coll] > -1} {
      reportErrorAndExit "Command does not remove collection specified as\
         filepath"
   }

   # get coresponding filename
   set collfile [getCollectionFilename $coll colldesc]

   if {![file exists $collfile]} {
      reportErrorAndExit "Collection $colldesc does not exist"
   }

   # attempt to delete specified colletion
   if {[catch {
      file delete $collfile
   } errMsg ]} {
      reportErrorAndExit "Collection $colldesc cannot be removed.\n$errMsg"
   }
}

proc cmdModuleSaveshow {{coll {}}} {
   # default collection used if no name provided
   if {$coll eq ""} {
      set coll "default"
   }
   reportDebug "cmdModuleSaveshow: $coll"

   # get coresponding filename
   set collfile [getCollectionFilename $coll colldesc]

   if {![file readable $collfile]} {
      reportErrorAndExit "Collection $colldesc does not exist or is not\
         readable"
   }

   # read collection
   lassign [readCollectionContent $collfile] coll_path_list coll_mod_list

   # collection should at least define a path
   if {[llength $coll_path_list] == 0} {
      reportErrorAndExit "$colldesc is not a valid collection"
   }

   report\
      "-------------------------------------------------------------------"
   report "$collfile:\n"
   report [formatCollectionContent $coll_path_list $coll_mod_list]
   report\
      "-------------------------------------------------------------------"
}

proc cmdModuleSavelist {} {
   global env show_oneperline show_modtimes

   # if a target is set, only list collection matching this
   # target (means having target as suffix in their name)
   set colltarget [getCollectionTarget]
   if {$colltarget ne ""} {
      set suffix ".$colltarget"
      set targetdesc " (for target \"$colltarget\")"
   } else {
      set suffix ""
      set targetdesc ""
   }

   reportDebug "cmdModuleSavelist: list collections for target\
      \"$colltarget\""

   # list saved collections (matching target suffix)
   set coll_list [glob -nocomplain -- "$env(HOME)/.module/*$suffix"]

   if { [llength $coll_list] == 0} {
      report "No named collection$targetdesc."
   } else {
      set list {}
      if {$show_modtimes} {
         report "- Collection ---------------------------------------.- Last\
            mod. ------"
      }
      report "Named collection list$targetdesc:"
      set display_list {}
      if {$show_modtimes || $show_oneperline} {
         set display_idx 0
         set one_per_line 1
      } else {
         set display_idx 1
         set one_per_line 0
      }

      foreach coll [lsort -dictionary $coll_list] {
         # remove target suffix from names to display
         regsub "$suffix$" [file tail $coll] {} mod

         if {[string length $mod] > 0} {
            if {$show_modtimes} {
               set filetime [clock format [file mtime $coll]\
                  -format "%Y/%m/%d %H:%M:%S"]
               lappend display_list [format "%-53s%10s" $mod $filetime]
            } else {
               lappend display_list $mod
            }
         }
      }

      eval displayElementList "noheader" $one_per_line $display_idx\
         $display_list
   }
}


proc cmdModuleSource {args} {
   reportDebug "cmdModuleSource: $args"
   foreach file $args {
      if {[file exists $file]} {
         pushMode "load"
         pushModuleName $file
         execute-modulefile $file
         popModuleName
         popMode
      } else {
         reportErrorAndExit "File $file does not exist"
      }
   }
}

proc cmdModuleLoad {args} {
   global g_loadedModules g_loadedModulesGeneric g_force
   global ModulesCurrentModulefile

   reportDebug "cmdModuleLoad: loading $args"

   foreach mod $args {
      lassign [getPathToModule $mod] modfile modname
      if {$modfile ne ""} {
         set currentModule $modname
         set ModulesCurrentModulefile $modfile

         if {$g_force || ! [info exists g_loadedModules($currentModule)]} {
            pushMode "load"
            pushModuleName $currentModule
            pushSettings

            if {[execute-modulefile $modfile]} {
               restoreSettings
            } else {
               append-path LOADEDMODULES $currentModule
               append-path _LMFILES_ $modfile

               set g_loadedModules($currentModule) 1
               set genericModName [file dirname $currentModule]

               reportDebug "cmdModuleLoad: genericModName = $genericModName"

               if {![info exists\
                  g_loadedModulesGeneric($genericModName)]} {
                     set g_loadedModulesGeneric($genericModName) [file tail\
                        $currentModule]
               }
            }

            popSettings
            popMode
            popModuleName
         }
      }
   }
}

proc cmdModuleUnload {args} {
   global g_loadedModules g_loadedModulesGeneric
   global ModulesCurrentModulefile g_def_separator

   reportDebug "cmdModuleUnload: unloading $args"

   foreach mod $args {
      if {[catch {
         lassign [getPathToModule $mod] modfile modname
         if {$modfile ne ""} {
            set currentModule $modname
            set ModulesCurrentModulefile $modfile

            if {[info exists g_loadedModules($currentModule)]} {
               pushMode "unload"
               pushModuleName $currentModule
               pushSettings

               if {[execute-modulefile $modfile]} {
                  restoreSettings
               } else {
                  unload-path LOADEDMODULES $currentModule\
                     $g_def_separator
                  unload-path _LMFILES_ $modfile $g_def_separator
                  unset g_loadedModules($currentModule)

                  if {[info exists g_loadedModulesGeneric([file dirname\
                     $currentModule])]} {
                     unset g_loadedModulesGeneric([file dirname\
                        $currentModule])
                  }
               }

               popSettings
               popMode
               popModuleName
            }
         } else {
            if {[info exists g_loadedModulesGeneric($mod)]} {
               set mod "$mod/$g_loadedModulesGeneric($mod)"
            }
            unload-path LOADEDMODULES $mod $g_def_separator
            unload-path _LMFILES_ $modfile $g_def_separator

            if {[info exists g_loadedModules($mod)]} {
               unset g_loadedModules($mod)
            }
            if {[info exists g_loadedModulesGeneric([file dirname $mod])]} {
               unset g_loadedModulesGeneric([file dirname $mod])
            }
         }
      } errMsg ]} {
         reportError "module unload $mod failed.\n$errMsg"
      }
   }
}

proc cmdModulePurge {} {
   reportDebug "cmdModulePurge"

   eval cmdModuleUnload [lreverse [getLoadedModuleList]]
}

proc cmdModuleReload {} {
   reportDebug "cmdModuleReload"

   set list [getLoadedModuleList]
   set rlist [lreverse $list]
   foreach mod $rlist {
      cmdModuleUnload $mod
   }
   foreach mod $list {
      cmdModuleLoad $mod
   }
}

proc cmdModuleAliases {} {
   global g_moduleAlias g_moduleVersion

   # parse paths to fill g_moduleAlias and g_moduleVersion if empty
   if {[array size g_moduleAlias] == 0 \
      && [array size g_moduleVersion] == 0 } {
      foreach dir [getModulePathList "exiterronundef"] {
         if {[file isdirectory "$dir"] && [file readable $dir]} {
            listModules "$dir" ""
         }
      }
   }

   set display_list {}
   foreach name [lsort -dictionary [array names g_moduleAlias]] {
      lappend display_list "$name -> $g_moduleAlias($name)"
   }
   eval displayElementList "Aliases" 1 0 $display_list

   set display_list {}
   foreach name [lsort -dictionary [array names g_moduleVersion]] {
      lappend display_list "$name -> $g_moduleVersion($name)"
   }
   eval displayElementList "Versions" 1 0 $display_list
}

proc system {mycmd args} {
   global g_systemList

   reportDebug "system: $mycmd $args"
   set mode [currentMode]
   set mycmd [join [concat $mycmd $args] " "]

   if {$mode eq "load"} {
      lappend g_systemList $mycmd
   }\
   elseif {$mode eq "unload"} {
      # No operation here unable to undo a syscall.
   }\
   elseif {$mode eq "display"} {
      report "system\t\t$mycmd"
   }

   return {}
}

proc cmdModuleAvail {{mod {*}}} {
   global show_oneperline show_modtimes show_filter

   if {$show_modtimes} {
      report "- Package -----------------------------.- Versions -.- Last\
         mod. ------"
   }

   foreach dir [getModulePathList "exiterronundef"] {
      if {[file isdirectory "$dir"] && [file readable $dir]} {
         set display_list {}

         set list [listModules "$dir" "$mod" 1 $show_filter]
         if {$show_modtimes} {
            set one_per_line 1
            foreach i $list {
               # don't change $i with the regsub - we need it 
               # to figure out the file time.
               regsub {\(default\)} $i "   (default)" i2 
               set filetime [clock format [file mtime [lindex\
                  [getPathToModule $i] 0]] -format "%Y/%m/%d %H:%M:%S" ]
               lappend display_list [format "%-53s%10s" $i2 $filetime]
            }
         }\
         elseif {$show_oneperline} {
            set one_per_line 1
            foreach i $list {
               regsub {\(default\)} $i "   (default)" i2 
               lappend display_list $i2
            }
         } else {
            set one_per_line 0
            foreach mod2 $list {
               lappend display_list $mod2
            }
         }

         eval displayElementList $dir $one_per_line 0 $display_list
      }
   }
}

proc cmdModuleUse {args} {
   global g_def_separator

   reportDebug "cmdModuleUse: $args"

   if {$args eq ""} {
      showModulePath
   } else {
      set stuff_path "prepend"
      foreach path $args {
         if {$path eq ""} {
            # Skip "holes"
         }\
         elseif {($path eq "--append") ||($path eq "-a") ||($path eq\
            "-append")} {
            set stuff_path "append"
         }\
         elseif {($path eq "--prepend") ||($path eq "-p") ||($path eq\
            "-prepend")} {
            set stuff_path "prepend"
         }\
         elseif {[file isdirectory $path]} {
            reportDebug "cmdModuleUse: calling add-path \
               MODULEPATH $path $stuff_path $g_def_separator"

            pushMode "load"
            catch {
               add-path MODULEPATH $path $stuff_path $g_def_separator
            }

            popMode
         } else {
            reportError "Directory '$path' not found"
         }
      }
   }
}

proc cmdModuleUnuse {args} {
   global g_def_separator

   reportDebug "cmdModuleUnuse: $args"
   if {$args eq ""} {
      showModulePath
   } else {
      foreach path $args {
         # get current module path list
         if {![info exists modpathlist]} {
            set modpathlist [getModulePathList]
         }
         if {[lsearch -exact $modpathlist $path] >= 0} {
            reportDebug "calling unload-path MODULEPATH $path\
               $g_def_separator"

            pushMode "unload"

            catch {
               unload-path MODULEPATH $path $g_def_separator
            }
            popMode

            # refresh path list after unload
            set modpathlist [getModulePathList]
            if {[lsearch -exact $modpathlist $path] >= 0} {
               reportWarning "Did not unuse $path"
            }
         }
      }
   }
}

proc cmdModuleDebug {} {
   global env g_def_separator

   reportDebug "cmdModuleDebug"

   foreach var [array names env] {
      array set countarr [getReferenceCountArray $var $g_def_separator]

      foreach path [array names countarr] {
         report "$var\t$path\t$countarr($path)"
      }
      unset countarr
   }
   foreach dir [split $env(PATH) $g_def_separator] {
      foreach file [glob -nocomplain -- "$dir/*"] {
         if {[file executable $file]} {
            set exec [file tail $file]
            lappend execcount($exec) $file
         }
      }
   }
   foreach file [lsort -dictionary [array names execcount]] {
      if {[llength $execcount($file)] > 1} {
         report "$file:\t$execcount($file)"
      }
   }
}

proc cmdModuleAutoinit {} {
   global g_autoInit

   reportDebug "cmdModuleAutoinit:"
   set g_autoInit 1
}

proc cmdModuleInit {args} {
   global g_shell env

   set moduleinit_cmd [lindex $args 0]
   set notdone 1
   set notclear 1

   reportDebug "cmdModuleInit: $args"

   # Define startup files for each shell
   set files(csh) [list ".modules" ".cshrc" ".cshrc_variables" ".login"]
   set files(tcsh) [list ".modules" ".tcshrc" ".cshrc" ".cshrc_variables"\
      ".login"]
   set files(sh) [list ".modules" ".bash_profile" ".bash_login" ".profile"\
      ".bashrc"]
   set files(bash) $files(sh)
   set files(ksh) $files(sh)
   set files(fish) [list ".modules" ".config/fish/config.fish"]
   set files(zsh) [list ".modules" ".zshrc" ".zshenv" ".zlogin"]

   array set nargs {
      list    0
      add     1
      load    1
      prepend 1
      rm      1
      unload  1
      switch  2
      clear   0
   }

   # Process startup files for this shell
   set current_files $files($g_shell)
   foreach filename $current_files {
      if {$notdone && $notclear} {
         set filepath $env(HOME)
         append filepath "/" $filename
         # create a new file to put the changes in
         set newfilepath "$filepath-NEW"

         reportDebug "Looking at: $filepath"
         if {[file readable $filepath] && [file isfile $filepath]} {
            set fid [open $filepath r]

            set temp [expr {[llength $args] -1}]
            if {$temp != $nargs($moduleinit_cmd)} {
               reportErrorAndExit "'module init$moduleinit_cmd' requires\
                  exactly $nargs($moduleinit_cmd) arg(s)."
               #               cmdModuleHelp
            }

            # Only open the new file if we are not doing "initlist"
            if {[string compare $moduleinit_cmd "list"] != 0} {
               set newfid [open $newfilepath w]
            }

            while {[gets $fid curline] >= 0} {
               # Find module load/add command in startup file 
               set comments {}
               if {$notdone && [regexp {^([ \t]*module[ \t]+(load|add)[\
                  \t]+)(.*)} $curline match cmd subcmd modules]} {
                  regexp {([ \t]*\#.+)} $modules match comments
                  regsub {\#.+} $modules {} modules

                  # remove existing references to the named module from
                  # the list Change the module command line to reflect the 
                  # given command
                  switch $moduleinit_cmd {
                     list {
                        report "$g_shell initialization file $filepath\
                           loads modules: $modules"
                     }
                     add {
                        set newmodule [lindex $args 1]
                        set modules [replaceFromList $modules $newmodule]
                        append modules " $newmodule"
                        puts $newfid "$cmd$modules$comments"
                        set notdone 0
                     }
                     prepend {
                        set newmodule [lindex $args 1]
                        set modules [replaceFromList $modules $newmodule]
                        set modules "$newmodule $modules"
                        puts $newfid "$cmd$modules$comments"
                        set notdone 0
                     }
                     rm {
                        set oldmodule [lindex $args 1]
                        set modules [replaceFromList $modules $oldmodule]
                        if {[llength $modules] == 0} {
                           set modules ""
                        }
                        puts $newfid "$cmd$modules$comments"
                        set notdone 0
                     }
                     switch {
                        set oldmodule [lindex $args 1]
                        set newmodule [lindex $args 2]
                        set modules [replaceFromList $modules\
                           $oldmodule $newmodule]
                        puts $newfid "$cmd$modules$comments"
                        set notdone 0
                     }
                     clear {
                        set modules ""
                        puts $newfid "$cmd$modules$comments"
                        set notclear 0
                     }
                     default {
                        report "Command init$moduleinit_cmd not\
                           recognized"
                     }
                  }
               } else {
                  # copy the line from the old file to the new
                  if {[info exists newfid]} {
                     puts $newfid $curline
                  }
               }
            }

            close $fid
            if {[info exists newfid]} {
               close $newfid
               if {[catch {file copy -force $filepath $filepath-OLD}] != 0} {
                  reportErrorAndExit "Failed to back up original\
                     $filepath...exiting"
               }
               if {[catch {file copy -force $newfilepath $filepath}] != 0} {
                  reportErrorAndExit "Failed to write $filepath...exiting"
               }
            }
         }
      }
   }
}

proc cmdModuleHelp {args} {
   global MODULES_CURRENT_VERSION

   set done 0
   foreach arg $args {
      if {$arg ne ""} {
         lassign [getPathToModule $arg] modfile modname

         if {$modfile ne ""} {
            pushModuleName $modname
            report\
               "-------------------------------------------------------------------"
            report "Module Specific Help for $modfile:\n"
            set mode "Help"
            execute-modulefile $modfile 1
            popMode
            popModuleName
            report\
               "-------------------------------------------------------------------"
         }
         set done 1
      }
   }
   if {$done == 0} {
      report "Modules Release Tcl $MODULES_CURRENT_VERSION " 1
      report {        Copyright GNU GPL v2 1991}
      report {Usage: module [options] [command] [args ...]}

      report {}
      report {Loading / Unloading commands:}
      report {  add | load      modulefile [...]  Load modulefile(s)}
      report {  rm | unload     modulefile [...]  Remove modulefile(s)}
      report {  purge                             Unload all loaded\
         modulefiles}
      report {  reload                            Unload then load all\
         loaded modulefiles}
      report {  switch | swap   [mod1] mod2       Unload mod1 and load mod2}
      report {}
      report {Listing / Searching commands:}
      report {  list            [-t|-l]           List loaded modules}
      report {  avail   [-d|-L] [-t|-l] [mod ...] List all or matching\
         available modules}
      report {  aliases                           List all module aliases}
      report {  whatis          [modulefile ...]  Print whatis\
         information of modulefile(s)}
      report {  apropos | keyword | search  str   Search all name and\
         whatis containing str}
      report {}
      report {Collection of modules handling commands:}
      report {  save            [collection|file] Save current module\
         list to collection}
      report {  restore         [collection|file] Restore module list\
         from collection or file}
      report {  saverm          [collection]      Remove saved collection}
      report {  saveshow        [collection|file] Display information\
         about collection}
      report {  savelist        [-t|-l]           List all saved\
         collections}
      report {}
      report {Shell's initialization files handling commands:}
      report {  initlist                          List all modules\
         loaded from init file}
      report {  initadd         modulefile        Add modulefile to\
         shell init file}
      report {  initrm          modulefile        Remove modulefile\
         from shell init file}
      report {  initprepend     modulefile        Add to beginning of\
         list in init file}
      report {  initswitch      mod1 mod2         Switch mod1 with mod2\
         from init file}
      report {  initclear                         Clear all modulefiles\
         from init file}
      report {}
      report {Other commands:}
      report {  help            [modulefile ...]  Print this or\
         modulefile(s) help info}
      report {  display | show  modulefile [...]  Display information\
         about modulefile(s)}
      report {  use     [-a|-p] dir [...]         Add dir(s) to\
         MODULEPATH variable}
      report {  unuse           dir [...]         Remove dir(s) from\
         MODULEPATH variable}
      report {  path            modulefile        Print modulefile path}
      report {  paths           modulefile        Print path of\
         matching available modules}
      report {  source          scriptfile [...]  Execute scriptfile(s)}
      report {}
      report {Switches:}
      report {  -t | --terse    Display output in terse format}
      report {  -l | --long     Display output in long format}
      report {  -d | --default  Only show default versions available}
      report {  -L | --latest   Only show latest versions available}
      report {  -a | --append   Append directory to MODULEPATH}
      report {  -p | --prepend  Prepend directory to MODULEPATH}
      report {}
      report {Options:}
      report {  -h | --help     This usage info}
      report {  -V | --version  Module version}
      report {  -D | --debug    Enable debug messages}
   }
}


########################################################################
# main program

# needed on a gentoo system. Shouldn't hurt since it is
# supposed to be the default behavior
fconfigure stderr -translation auto

reportDebug "CALLING $argv0 $argv"

if {[catch {
   # Parse shell
   set g_shell [lindex $argv 0]
   switch -regexp -- $g_shell {
      ^(sh|bash|ksh|zsh)$ {
          set g_shellType sh
      }
      ^(fish)$ {
          set g_shellType fish
      }
      ^(cmd)$ {
          set g_shellType cmd
      }
      ^(csh|tcsh)$ {
          set g_shellType csh
      }
      ^(tcl)$ {
         set g_shellType tcl
      }
      ^(perl)$ {
          set g_shellType perl
      }
      ^(python)$ {
          set g_shellType python
      }
      ^(lisp)$ {
          set g_shellType lisp
      }
      . {
          reportErrorAndExit "Unknown shell type \'($g_shell)\'"
      }
   }

   # Parse options
   set opt [lindex $argv 1]
   switch -regexp -- $opt {
      {^(-deb|--deb|-D)} {
         if {!$g_debug} {
            report "CALLING $argv0 $argv"
         }

         set g_debug 1
         reportDebug "debug enabled"

         set argv [lreplace $argv 1 1]
      }
      {^(--help|-h)} {
          cmdModuleHelp
          exit 0
      }
      {^(-V|--ver)} {
          report "Modules Release Tcl $MODULES_CURRENT_VERSION"
          exit 0
      }
      {^-} {
          reportErrorAndExit "Invalid option '$opt'\nTry\
            'module --help' for more information."
      }
   }

   set command [lindex $argv 1]
   # default command is help if none supplied
   if {$command eq ""} {
      set command "help"
   }
   set argv [lreplace $argv 0 1]

   cacheCurrentModules

   # Find and execute any .modulerc file found in the module directories
   # defined in env(MODULESPATH)
   runModulerc

   # extract command switches from other args
   set otherargv {}
   foreach arg $argv {
      switch -- $arg {
         "-t" - "--terse" {
            set show_oneperline 1
         }
         "-l" - "--long" {
            set show_modtimes 1
         }
         "-d" - "--default" {
            set show_filter "onlydefaults"
         }
         "-L" - "--latest" {
            set show_filter "onlylatest"
         }
         default {
            lappend otherargv $arg
         }
      }
   }

   # eval needed to pass otherargv as list to module proc
   eval module $command $otherargv
} errMsg ]} {
   reportError "$errMsg"
   exit 1
}

exit 0

# ;;; Local Variables: ***
# ;;; mode:tcl ***
# ;;; End: ***
# vim:set tabstop=3 shiftwidth=3 expandtab autoindent: