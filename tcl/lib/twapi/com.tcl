#
# Copyright (c) 2006-2010 Ashok P. Nadkarni
# All rights reserved.
#
# See the file LICENSE for license

# TBD - object identity comparison 
#   - see http://blogs.msdn.com/ericlippert/archive/2005/04/26/412199.aspx



namespace eval twapi {
    # Maps TYPEKIND data values to symbols
    array set _typekind_map {
        0 enum
        1 record
        2 module
        3 interface
        4 dispatch
        5 coclass
        6 alias
        7 union
    }

    # Cache of Interface names - IID mappings
    array set _iid_to_name_cache {
    }
    array set _name_to_iid_cache {
        iunknown  {{00000000-0000-0000-C000-000000000046}}
        idispatch {{00020400-0000-0000-C000-000000000046}}
        idispatchex {{A6EF9860-C720-11D0-9337-00A0C90DCAA9}}
        itypeinfo {{00020401-0000-0000-C000-000000000046}}
        itypecomp {{00020403-0000-0000-C000-000000000046}}
        ienumvariant {{00020404-0000-0000-C000-000000000046}}
        iprovideclassinfo {{B196B283-BAB4-101A-B69C-00AA00341D07}}

        ipersist  {{0000010c-0000-0000-C000-000000000046}}
        ipersistfile {{0000010b-0000-0000-C000-000000000046}}

        iprovidetaskpage {{4086658a-cbbb-11cf-b604-00c04fd8d565}}
        itasktrigger {{148BD52B-A2AB-11CE-B11F-00AA00530503}}
        ischeduleworkitem {{a6b952f0-a4b1-11d0-997d-00aa006887ec}}
        itask {{148BD524-A2AB-11CE-B11F-00AA00530503}}
        ienumworkitems {{148BD528-A2AB-11CE-B11F-00AA00530503}}
        itaskscheduler {{148BD527-A2AB-11CE-B11F-00AA00530503}}
    }

    # Controls debug checks
    variable com_debug 0
}

# Get the CLSID for a ProgID
proc twapi::progid_to_clsid {progid} {
    return [CLSIDFromProgID $progid]
}

# Get the ProgID for a CLSID
proc twapi::clsid_to_progid {progid} {
    return [ProgIDFromCLSID $progid]
}

#
# Get IUnknown interface for an existing active object
# TBD - make a comobj out of this and document
proc twapi::get_active_object {clsid} {
    return [::twapi::make_interface_proxy [GetActiveObject $clsid]]
}

#
# Create a new object and get an interface to it
# Generates exception if no such interface
# TBD - document
proc twapi::com_create_instance {clsid args} {
    array set opts [parseargs args {
        {model.arg any}
        download.bool
        {disablelog.bool false}
        enableaaa.bool
        {nocustommarshal.bool false 0x1000}
        {interface.arg IUnknown}
        raw
    } -maxleftover 0]

    # CLSCTX_NO_CUSTOM_MARSHAL ?
    set flags $opts(nocustommarshal)

    set model 0
    if {[info exists opts(model)]} {
        foreach m $opts(model) {
            switch -exact -- $m {
                any           {setbits model 23}
                inprocserver  {setbits model 1}
                inprochandler {setbits model 2}
                localserver   {setbits model 4}
                remoteserver  {setbits model 16}
            }
        }
    }

    setbits flags $model

    if {[info exists opts(download)]} {
        if {$opts(download)} {
            setbits flags 0x2000;       # CLSCTX_ENABLE_CODE_DOWNLOAD
        } else {
            setbits flags 0x400;       # CLSCTX_NO_CODE_DOWNLOAD
        }
    }

    if {$opts(disablelog)} {
        setbits flags 0x4000;           # CLSCTX_NO_FAILURE_LOG
    }

    if {[info exists opts(enableaaa)]} {
        if {$opts(enableaaa)} {
            setbits flags 0x10000;       # CLSCTX_ENABLE_AAA
        } else {
            setbits flags 0x8000;       # CLSCTX_DISABLE_AAA
        }
    }

    lassign [_resolve_iid $opts(interface)] iid iid_name

    # In some cases, like Microsoft Office getting an interface other
    # than IUnknown fails fails.
    # We need to get IUnknown, wait for the object to run, and then
    # get the desired interface from IUnknown.
    #  We could check for a specific error code but no guarantee that
    #  the error is same in all versions so we catch and retry on all errors
    if {[catch {set ifc [Twapi_CoCreateInstance $clsid NULL $flags $iid $iid_name]}]} {
        # Try through IUnknown
        set iunk [Twapi_CoCreateInstance $clsid NULL $flags [_iid_iunknown] IUnknown]
        trap {
            # Wait for it to run, then get desired interface from it
            twapi::OleRun $iunk
            set ifc [Twapi_IUnknown_QueryInterface $iunk $iid $iid_name]
        } finally {
            IUnknown_Release $iunk
        }
    }

    if {$opts(raw)} {
        return $ifc
    } else {
        return [make_interface_proxy $ifc]
    }
}

#
# NULL comobj object
proc twapi::comobj_null {args} {
    switch -exact -- [lindex $args 0] {
        -isnull    { return true }
        -interface { return NULL }
        -destroy   { return }
        default {
            error "NULL comobj called with arguments <[join $args ,]>."
        }
    }
}

#
# Creates an object command for a COM object from IDispatch or IDispatchEx
# Caller must hold a reference (count) to ifc that it hands off to comobj.
# If caller wants to use ifc for its own purpose, it must do an additional
# AddRef itself to ensure the interface is not released.
proc twapi::comobj_idispatch {ifc} {
    if {[Twapi_IsNullPtr $ifc]} {
        return ::twapi::comobj_null
    }

    if {[Twapi_IsPtr $ifc IDispatch]} {
        set proxyobj [IDispatchProxy new $ifc]
    } elseif {[Twapi_IsPtr $ifc IDispatchEx]} {
        set proxyobj [IDispatchExProxy new $ifc]
    } else {
        error "'$ifc' does not reference an IDispatch interface"
    }

    return [Automation new $proxyobj]
}

#
# Create an object command for a COM object from a name
# TBD - add -progid option so file can be opened with different app
#       see "Mapping Visual Basic to Automation" in SDK help
proc twapi::comobj_object {path args} {
    array set opts [parseargs args {
        {interface.arg IDispatch {IDispatch IDispatchEx}}
    } -maxleftover 0]

    return [comobj_idispatch [::twapi::Twapi_CoGetObject $path {} [name_to_iid $opts(interface)] $opts(interface)]]
}

#
# Create a object command for a COM object IDispatch interface
# comid is either a CLSID or a PROGID
proc twapi::comobj {comid args} {
    array set opts [parseargs args {
        {interface.arg IDispatch {IDispatch IDispatchEx}}
    } -ignoreunknown]
    set clsid [_convert_to_clsid $comid]
    return [comobj_idispatch [com_create_instance $clsid -interface $opts(interface) -raw {*}$args]]
}


# Return an interface to a typelib<
proc twapi::ITypeLibProxy_from_path {path args} {
    array set opts [parseargs args {
        {registration.arg none {none register default}}
    } -maxleftover 0]

    return [make_interface_proxy [LoadTypeLibEx $path [kl_get {default 0 register 1 none 2} $opts(registration) $opts(registration)]]]
}

#
# Return an interface to a typelib from the registry
proc twapi::ITypeLibProxy_from_guid {uuid major minor args} {
    array set opts [parseargs args {
        lcid.int
    } -maxleftover 0 -nulldefault]
    
    return [make_interface_proxy [LoadRegTypeLib $uuid $major $minor $opts(lcid)]]
}

#
# Unregister a typelib
proc twapi::unregister_typelib {uuid major minor args} {
    array set opts [parseargs args {
        lcid.int
    } -maxleftover 0 -nulldefault]

    UnRegisterTypeLib $uuid $major $minor $opts(lcid) 1
}

#
# Returns the path to the typelib based on a guid
proc twapi::get_typelib_path_from_guid {guid major minor args} {
    array set opts [parseargs args {
        lcid.int
    } -maxleftover 0 -nulldefault]


    set path [QueryPathOfRegTypeLib $guid $major $minor $opts(lcid)]
    # At least some versions have a bug in that there is an extra \0
    # at the end.
    if {[string equal [string index $path end] \0]} {
        set path [string range $path 0 end-1]
    }
    return $path
}

#
# Map interface name to IID
proc twapi::name_to_iid {iname} {
    set iname [string tolower $iname]

    if {[info exists ::twapi::_name_to_iid_cache($iname)]} {
        return $::twapi::_name_to_iid_cache($iname)
    }

    # Look up the registry
    set iids {}
    foreach iid [registry keys HKEY_CLASSES_ROOT\\Interface] {
        if {![catch {
            set val [registry get HKEY_CLASSES_ROOT\\Interface\\$iid ""]
        }]} {
            if {[string equal -nocase $iname $val]} {
                lappend iids $iid
            }
        }
    }

    if {[llength $iids] == 1} {
        return [set ::twapi::_name_to_iid_cache($iname) [lindex $iids 0]]
    } elseif {[llength $iids]} {
        error "Multiple interfaces found matching name $iname: [join $iids ,]"
    } else {
        return [set ::twapi::_name_to_iid_cache($iname) ""]
    }
}


#
# Map interface IID to name
proc twapi::iid_to_name {iid} {
    set iname ""
    catch {set iname [registry get HKEY_CLASSES_ROOT\\Interface\\$iid ""]}
    return $iname
}

#
# Convert a variant time to a time list
proc twapi::variant_time_to_timelist {double} {
    return [VariantTimeToSystemTime $double]
}

#
# Convert a time list time to a variant time
proc twapi::timelist_to_variant_time {timelist} {
    return [SystemTimeToVariantTime $timelist]
}

################################################################

#
# Test code
proc twapi::typelib_print {path args} {
    array set opts [parseargs args {
        type.arg
        name.arg
        output.arg
    } -maxleftover 0 -nulldefault]

    
    if {$opts(output) ne ""} {
        if {[file exists $opts(output)]} {
            error "File $opts(output) already exists."
        }
        set outfd [open $opts(output) a]
    } else {
        set outfd stdout
    }

    trap {
        set tl [ITypeLibProxy_from_path $path -registration none]
        puts $outfd [$tl @Text -type $opts(type) -name $opts(name)]
    } finally {
        if {[info exists tl]} {
            $tl Release
        }
        if {$outfd ne "stdout"} {
            close $outfd
        }
    }        

    return
}


proc twapi::_interface_text {ti} {
    # ti must be TypeInfo for an interface or module (or enum?) - TBD
    set desc ""
    array set attrs [$ti @GetTypeAttr -all]
    set desc "Functions:\n"
    for {set j 0} {$j < $attrs(-fncount)} {incr j} {
        array set funcdata [$ti @GetFuncDesc $j -all]
        if {$funcdata(-funckind) eq "dispatch"} {
            set funckind "(dispid $funcdata(-memid))"
        } else {
            set funckind "(vtable $funcdata(-vtbloffset))"
        }
        append desc "\t$funckind [::twapi::_resolve_com_type_text $ti $funcdata(-datatype)] $funcdata(-name) $funcdata(-invkind) [::twapi::_resolve_com_params_text $ti $funcdata(-params) $funcdata(-paramnames)]\n"
    }
    append desc "Variables:\n"
    for {set j 0} {$j < $attrs(-varcount)} {incr j} {
        array set vardata [$ti @GetVarDesc $j -all]
        set vardesc "($vardata(-memid)) $vardata(-varkind) [::twapi::_flatten_com_type [::twapi::_resolve_com_type_text $ti $vardata(-datatype)]] $vardata(-name)"
        if {$attrs(-typekind) eq "enum" || $vardata(-varkind) eq "const"} {
            append vardesc " = $vardata(-value)"
        } else {
            append vardesc " (offset $vardata(-value))"
        }
        append desc "\t$vardesc\n"
    }
    return $desc
}

#
# Print methods in an interface, including inherited names
proc twapi::dispatch_print {di args} {
    array set opts [parseargs args {
        output.arg
    } -maxleftover 0 -nulldefault]

    if {$opts(output) ne ""} {
        if {[file exists $opts(output)]} {
            error "File $opts(output) already exists."
        }
        set outfd [open $opts(output) a]
    } else {
        set outfd stdout
    }

    trap {
        set ti [$di @GetTypeInfo]
        twapi::_dispatch_print_helper $ti $outfd
    } finally {
        if {[info exists ti]} {
            $ti Release
        }
        if {$outfd ne "stdout"} {
            close $outfd
        }
    }

    return
}

proc twapi::_dispatch_print_helper {ti outfd {names_already_done ""}} {
    set name [$ti @GetName]
    if {$name in $names_already_done} {
        # Already printed this
        return $names_already_done
    }
    lappend names_already_done $name

    # Check for dual interfaces - we want to print both vtable and disp versions
    set tilist [list $ti]
    if {![catch {set ti2 [$ti @GetRefTypeInfoFromIndex $ti -1]}]} {
        lappend tilist $ti2
    }

    trap {
        foreach tifc $tilist {
            puts $outfd $name
            puts $outfd [_interface_text $tifc]
        }
    } finally {
        if {[info exists ti2]} {
            $ti2 Release
        }
    }

    # Now get any referenced typeinfos and print them
    array set tiattrs [$ti GetTypeAttr]
    for {set j 0} {$j < $tiattrs(cImplTypes)} {incr j} {
        set ti2 [$ti @GetRefTypeInfoFromIndex $j]
        trap {
            set names_already_done [_dispatch_print_helper $ti2 $outfd $names_already_done]
        } finally {
            $ti2 Release
        }
    }

    return $names_already_done
}



#
# Resolves references to parameter definition
proc twapi::_resolve_com_params_text {ti params paramnames} {
    set result [list ]
    foreach param $params paramname $paramnames {
        set paramdesc [_flatten_com_type [_resolve_com_type_text $ti [lindex $param 0]]]
        if {[llength $param] > 1 && [llength [lindex $param 1]] > 0} {
            set paramdesc "\[[lindex $param 1]\] $paramdesc"
        }
        if {[llength $param] > 2} {
            append paramdesc " [lrange $param 2 end]"
        }
        append paramdesc " $paramname"
        lappend result $paramdesc
    }
    return "([join $result {, }])"
}

# Flattens the output of _resolve_com_type_text
proc twapi::_flatten_com_type {com_type_desc} {
    if {[llength $com_type_desc] < 2} {
        return $com_type_desc
    }

    if {[lindex $com_type_desc 0] eq "ptr"} {
        return "[_flatten_com_type [lindex $com_type_desc 1]]*"
    } else {
        return "([lindex $com_type_desc 0] [_flatten_com_type [lindex $com_type_desc 1]])"
    }
}

#
# Resolves typedefs
proc twapi::_resolve_com_type_text {ti typedesc} {
    
    switch -exact -- [lindex $typedesc 0] {
        26 -
        ptr {
            # Recurse to resolve any inner types
            set typedesc [list ptr [_resolve_com_type_text $ti [lindex $typedesc 1]]]
        }
        29 -
        userdefined {
            set hreftype [lindex $typedesc 1]
            set ti2 [$ti @GetRefTypeInfo $hreftype]
            set typedesc [$ti2 @GetName]
            $ti2 Release
        }
        default {
            set typedesc [_vttype_to_string $typedesc]
        }
    }

    return $typedesc
}


#
# Given a COM type descriptor, resolved all user defined types (UDT) in it
# The descriptor must be in raw form as returned by the C code
proc twapi::_resolve_comtype {ti typedesc} {
    
    if {[lindex $typedesc 0] == 26} {
        # VT_PTR - {26 INNER_TYPEDESC}
        # If pointing to a UDT, convert to appropriate base type if possible
        set inner [_resolve_comtype $ti [lindex $typedesc 1]]
        if {[lindex $inner 0] == 29} {
            # TBD - is this really correct / necessary ? For UDT, the
            # second element is hreftype, not a vt_code so why are we
            # checking in this manner. It should not even match since 
            # the second element will not "dispatch" or "interface"
            switch -exact -- [lindex $inner 1] {
                dispatch  {set typedesc [list 9]}
                interface {set typedesc [list 13]}
                default {
                    # TBD - need to decode all the other types (record etc.)
                    set typedesc [list 26 $inner]
                }
            }
        }
    } elseif {[lindex $typedesc 0] == 29} {
        # VT_USERDEFINED - {29 HREFTYPE}
        set ti2 [$ti @GetRefTypeInfo [lindex $typedesc 1]]
        array set tattr [$ti2 @GetTypeAttr -guid -typekind]
        if {$tattr(-typekind) eq "enum"} {
            set typedesc [list 3]; # 3 -> i4
        } else {
            set typedesc [list 29 $tattr(-typekind) $tattr(-guid)]
        }
        $ti2 Release
    }

    return $typedesc
}

proc twapi::_resolve_params_for_prototype {ti paramdescs} {
    set params {}
    foreach paramdesc $paramdescs {
        lappend params \
            [lreplace $paramdesc 0 0 [::twapi::_resolve_comtype $ti [lindex $paramdesc 0]]]
    }
    return $params
}

#
# Returns a string value from a formatted variant value pair {VT_xxx value}
# $addref controls whether we do an AddRef when the value is a pointer to
# an interface. $raw controls whether interface pointers are returned
# as raw interface handles or objects.
proc twapi::_variant_value {variant {raw false} {addref false}} {
    # TBD - format appropriately depending on variant type for dates and
    # currency
    if {[llength $variant] == 0} {
        return ""
    }
    set vt [lindex $variant 0]

    if {$vt & 0x2000} {
        # VT_ARRAY
        if {[llength $variant] < 3} {
            return [list ]
        }
        set vt [expr {$vt & ~ 0x2000}]
        if {$vt == 12} {
            # Array of variants. Recursively convert values
            set result [list ]
            foreach elem [lindex $variant 2] {
                lappend result [_variant_value $elem $raw $addref]
            }
            return $result
        } else {
            return [lindex $variant 2]
        }
    } else {
        if {$vt == 9} {
            set idisp [lindex $variant 1]; # May be NULL!
            if {$addref && ! [Twapi_IsNullPtr $idisp]} {
                IUnknown_AddRef $idisp
            }
            if {$raw} {
                return $idisp
            } else {
                # Note comobj_idispatch takes care of NULL
                return [comobj_idispatch $idisp]
            }
        } elseif {$vt == 13} {
            set iunk [lindex $variant 1]; # May be NULL!
            if {$addref && ! [Twapi_IsNullPtr $iunk]} {
                IUnknown_AddRef $iunk
            }
            if {$raw} {
                return $iunk
            } else {
                return [make_interface_proxy $iunk]
            }
        }
    }
    return [lindex $variant 1]
}


#
# General dispatcher for callbacks from event sinks. Invokes the actual
# registered script after mapping dispid's
proc twapi::_eventsink_callback {comobj dispidmap script dispid lcid flags params} {
    # Check if the comobj is still active
    if {[llength [info commands $comobj]] == 0} {
        if {$::twapi::com_debug} {
            debuglog "COM event received for inactive object"
        }
        return;                         # Object has gone away, ignore
    }

    set retcode [catch {
        # Map dispid to event if possible
        set dispid [twapi::kl_get_default $dispidmap $dispid $dispid]
        set converted_params [list ]
        foreach param $params {
            # Note we do NOT ask _variant_value to do AddRef.
            # Called script has to do that if holding on to them.
            lappend converted_params [_variant_value $param true]
        }
        set result [uplevel \#0 $script [list $dispid] $converted_params]
    } result]

    if {$::twapi::com_debug && $retcode} {
        debuglog "Event sink callback error ($retcode): $result\n$::errorInfo"
    }

    # $retcode is returned as HRESULT by the Invoke
    return -code $retcode $result
}

#
# Return clsid from a string. If $clsid is a valid CLSID - returns as is
# else tries to convert it from progid. An error is generated if neither
# works
proc twapi::_convert_to_clsid {comid} {
    if {! [Twapi_ValidIID $comid]} {
        return [progid_to_clsid $comid]
    }
    return $comid
}

#
# Format a prototype definition for human consumption
# Proto is in the form {DISPID "" LCID INVOKEFLAGS RETTYPE PARAMTYPES}
proc twapi::_format_prototype {name proto} {
    set dispid_lcid [lindex $proto 0]/[lindex $proto 2]
    set ret_type [_vttype_to_string [lindex $proto 4]]
    set invkind [_invkind_to_string [lindex $proto 3]]
    # Distinguish between no parameters and parameters not known
    set paramstr ""
    if {[llength $proto] > 5} {
        set params {}
        foreach param [lindex $proto 5] {
            lassign $param type paramdesc
            set type [_vttype_to_string $type]
            set parammods [_paramflags_to_tokens [lindex $paramdesc 0]]
            if {[llength [lindex $paramdesc 1]]} {
                # Default specified
                lappend parammods "default:[lindex [lindex $paramdesc 1] 1]"
            }
            lappend params "\[$parammods\] $type"
        }
        set paramstr " ([join $params {, }])"
    }
    return "$dispid_lcid $invkind $ret_type ${name}${paramstr}"
}

# Convert parameter modifiers to string tokens.
# modifiers is list of integer flags or tokens.
proc twapi::_paramflags_to_tokens {modifiers} {
    array set tokens {}
    foreach mod $modifiers {
        if {! [string is integer -strict $mod]} {
            # mod is a token itself
            set tokens($mod) ""
        } else {
            foreach tok [_make_symbolic_bitmask $mod {
                in 1
                out 2
                lcid 4
                retval 8
                optional 16
                hasdefault 32
                hascustom  64
            }] {
                set tokens($tok) ""
            }
        }
    }

    # For cosmetic reasons, in/out should be first and remaining sorted
    # Also (in,out) -> inout
    if {[info exists tokens(in)]} {
        if {[info exists tokens(out)]} {
            set inout [list inout]
            unset tokens(in)
            unset tokens(out)
        } else {
            set inout [list in]
            unset tokens(in)
        }
    } else {
        if {[info exists tokens(out)]} {
            set inout [list out]
            unset tokens(out)
        }
    }

    if {[info exists inout]} {
        return [linsert [lsort [array names tokens]] 0 $inout]
    } else {
        return [lsort [array names tokens]]
    }
}

#
# Map method invocation code to string
# Return code itself if no match
proc twapi::_invkind_to_string {code} {
    return [kl_get {
        1  func
        2  propget
        4  propput
        8  propputref
    } $code $code]
}

#
# Map string method invocation symbol to code
# Error if no match and not an integer
proc twapi::_string_to_invkind {s} {
    if {[string is integer $s]} { return $s }
    return [kl_get {
        func    1
        propget 2
        propput 4
        propputref 8
    } $s]
}


#
# Convert a VT typedef to a string
# vttype may be nested
proc twapi::_vttype_to_string {vttype} {
    set vts [_vtcode_to_string [lindex $vttype 0]]
    if {[llength $vttype] < 2} {
        return $vts
    }

    return [list $vts [_vttype_to_string [lindex $vttype 1]]]
}

#
# Convert VT codes to strings
proc twapi::_vtcode_to_string {vt} {
    return [kl_get {
        2        i2
        3        i4
        4       r4
        5       r8
        6       cy
        7       date
        8       bstr
        9       idispatch
        10       error
        11       bool
        12       variant
        13       iunknown
        14       decimal
        16       i1
        17       ui1
        18       ui2
        19       ui4
        20       i8
        21       ui8
        22       int
        23       uint
        24       void
        25       hresult
        26       ptr
        27       safearray
        28       carray
        29       userdefined
        30       lpstr
        31       lpwstr
        36       record
    } $vt $vt]
}

#
# Get WMI service
proc twapi::_wmi {{top cimv2}} {
    return [comobj_object "winmgmts:{impersonationLevel=impersonate}!//./root/$top"]
}

#
# Get ADSI provider service
proc twapi::_adsi {{prov WinNT} {path {//.}}} {
    return [comobj_object "${prov}:$path"]
}


# Get cached IDispatch and IUNknown IID's
proc twapi::_iid_iunknown {} {
    return $::twapi::_name_to_iid_cache(iunknown)
}
proc twapi::_iid_idispatch {} {
    return $::twapi::_name_to_iid_cache(idispatch)
}

#
# Return IID and name given a IID or name
proc twapi::_resolve_iid {name_or_iid} {

    # IID -> name mapping is more efficient so first assume it is
    # an IID else we will unnecessarily trundle through the whole
    # registry area looking for an IID when we already have it
    # Assume it is a name
    set other [iid_to_name $name_or_iid]
    if {$other ne ""} {
        # It was indeed the IID. Return the pair
        return [list $name_or_iid $other]
    }

    # Else resolve as a name
    set other [name_to_iid $name_or_iid]
    if {$other ne ""} {
        # Yep
        return [list $other $name_or_iid]
    }

    win32_error 0x80004002 "Could not find IID $name_or_iid"
}


#
# Some simple tests

proc twapi::_com_tests {{tests {ie word excel wmi tracker}}} {

    if {"ie" in $tests} {
        puts "Invoking Internet Explorer"
        set ie [comobj InternetExplorer.Application -enableaaa true]
        $ie Visible 1
        $ie Navigate http://www.google.com
        after 2000
        puts "Exiting Internet Explorer"
        $ie Quit
        $ie -destroy
        puts "Internet Explorer done."
        puts "------------------------------------------"
    }

    if {"word" in $tests} {
        puts "Invoking Word"
        set word [comobj Word.Application]
        set doc [$word -with Documents Add]
        $word Visible 1
        puts "Inserting text"
        $word -with {selection font} name "Courier New"
        $word -with {selection font} size 10.0
        $doc -with content text "Text in Courier 10 point"
        after 2000
        puts "Exiting Word"
        $doc -destroy
        $word Quit 0
        $word -destroy
        puts "Word done."
        
        puts "------------------------------------------"
    }

    if {"excel" in $tests} {
        puts "Invoking Excel"
        # This tests property sets with multiple parameters
        set xl [comobj Excel.Application]
        $xl -set Visible True

        $xl WindowState -4137;        # Test for enum params

        set workbooks [$xl Workbooks]
        set workbook [$workbooks Add]
        set sheets [$workbook Sheets]
        set sheet [$sheets Item 1]
        $sheet Activate
        set r [$sheet Range "A1:B2"]
        $r Value 10 "helloworld"
        after 2000
        $r Value 11 [string map {helloworld hellouniverse} [$r Value 11]]
        set vals [$r Value 10]
        if {$vals ne "hellouniverse hellouniverse hellouniverse hellouniverse"} {
            puts "EXcel mismatch"
        }

        # clean up
        $xl DisplayAlerts 0
        $xl Quit
        foreach obj {r sheet sheets workbook workbooks xl} {
            [set $obj] -destroy
        }

    }

    if {"wmi" in $tests} {
        puts "WMI BIOS test"
        puts [_get_bios_info]
        puts "WMI BIOS done."

        puts "------------------------------------------"
    
        puts "WMI direct property access test (get bios version)"
        set wmi [twapi::_wmi]
        $wmi -with {{ExecQuery "select * from Win32_BIOS"}} -iterate biosobj {
            puts "BIOS version: [$biosobj BiosVersion]"
            $biosobj -destroy
        }
        $wmi -destroy

        puts "------------------------------------------"
    }

    if {"tracker" in $tests} {
        puts " Starting process tracker. Type 'twapi::_stop_process_tracker' to stop it."
        twapi::_start_process_tracker
        vwait ::twapi::_stop_tracker
    }
}


#
proc twapi::_wmi_read_popups {} {
    set res {}
    set wmi [twapi::_wmi]
    set wql {select * from Win32_NTLogEvent where LogFile='System' and \
                 EventType='3'    and \
                 SourceName='Application Popup'}
    set svcs [$wmi ExecQuery $wql]

    # Iterate all records
    $svcs -iterate instance {
        set propSet [$instance Properties_]
        # only the property (object) 'Message' is of interest here
        set msgVal [[$propSet Item Message] Value]
        lappend res $msgVal
    }
    return $res
}

#
proc twapi::_wmi_read_popups_succint {} {
    set res [list ]
    set wmi [twapi::_wmi]
    $wmi -with {
        {ExecQuery "select * from Win32_NTLogEvent where LogFile='System' and EventType='3' and SourceName='Application Popup'"}
    } -iterate event {
        lappend res [$event Message]
    }
    return $res
}

# Returns a list of records returned by WMI. The name of each field in
# the record is in lower case to make it easier to extract without
# worrying about case.
proc twapi::_wmi_records {wmi_class} {
    set wmi [twapi::_wmi]
    set records [list ]
    $wmi -with {{ExecQuery "select * from $wmi_class"}} -iterate elem {
        set record {}
        set propset [$elem Properties_]
        $propset -iterate itemobj {
            # Note how we get the default property
            lappend record [string tolower [$itemobj Name]] [$itemobj -default]
            $itemobj -destroy
        }
        $elem -destroy
        $propset -destroy
        lappend records $record
    }
    $wmi -destroy
    return $records
}

#
proc twapi::_wmi_get_autostart_services {} {
    set res [list ]
    set wmi [twapi::_wmi]
    $wmi -with {
        {ExecQuery "select * from Win32_Service where StartMode='Auto'"}
    } -iterate svc {
        lappend res [$svc DisplayName]
    }
    return $res
}

proc twapi::_get_bios_info {} {
    set wmi [twapi::_wmi]
    set entries [list ]
    $wmi -with {{ExecQuery "select * from Win32_BIOS"}} -iterate elem {
        set propset [$elem Properties_]
        $propset -iterate itemobj {
            # Note how we get the default property
            lappend entries [$itemobj Name] [$itemobj -default]
            $itemobj -destroy
        }
        $elem -destroy
        $propset -destroy
    }
    $wmi -destroy
    return $entries
}

# Handler invoked when a process is started.  Will print exe name of process.
proc twapi::_process_start_handler {wmi_event args} {
    if {$wmi_event eq "OnObjectReady"} {
        # First arg is a IDispatch interface of the event object
        # Create a TWAPI COM object out of it
        set ifc [lindex $args 0]
        IUnknown_AddRef $ifc;   # Must hold ref before creating comobj
        set event_obj [comobj_idispatch $ifc]

        # Get and print the Name property
        puts "Process [$event_obj ProcessID] [$event_obj ProcessName] started at [clock format [large_system_time_to_secs [$event_obj TIME_CREATED]] -format {%x %X}]"

        # Get rid of the event object
        $event_obj -destroy
    }
}

# Call to begin tracking of processes.
proc twapi::_start_process_tracker {} {
    # Get local WMI root provider
    set ::twapi::_process_wmi [twapi::_wmi]

    # Create an WMI event sink
    set ::twapi::_process_event_sink [comobj wbemscripting.swbemsink]

    # Attach our handler to it
    set ::twapi::_process_event_sink_id [$::twapi::_process_event_sink -bind twapi::_process_start_handler]

    # Associate the sink with a query that polls every 1 sec for process
    # starts.
    set sink_ifc [$::twapi::_process_event_sink -interface]; # Does AddRef
    trap {
        $::twapi::_process_wmi ExecNotificationQueryAsync $sink_ifc "select * from Win32_ProcessStartTrace"
        # WMI will internally do a AddRef, so we can release our AddRef on sink_ifc
    } finally {
        IUnknown_Release $sink_ifc
    }
}

# Stop tracking of process starts
proc twapi::_stop_process_tracker {} {
    # Cancel event notifications
    $::twapi::_process_event_sink Cancel

    # Unbind our callback
    $::twapi::_process_event_sink -unbind $::twapi::_process_event_sink_id

    # Get rid of all objects
    $::twapi::_process_event_sink -destroy
    $::twapi::_process_wmi -destroy

    set ::twapi::_stop_tracker 1
    return
}


# Handler invoked when a service status changes.
proc twapi::_service_change_handler {wmi_event args} {
    if {$wmi_event eq "OnObjectReady"} {
        # First arg is a IDispatch interface of the event object
        # Create a TWAPI COM object out of it
        set ifc [lindex $args 0]
        IUnknown_AddRef $ifc;   # Needed before passing to comobj
        set event_obj [twapi::comobj_idispatch $ifc]

        puts "Previous: [$event_obj PreviousInstance]"
        #puts "Target: [$event_obj -with TargetInstance State]"

        # Get rid of the event object
        $event_obj -destroy
    }
}

# Call to begin tracking of service state
proc twapi::_start_service_tracker {} {
    # Get local WMI root provider
    set ::twapi::_service_wmi [twapi::_wmi]

    # Create an WMI event sink
    set ::twapi::_service_event_sink [twapi::comobj wbemscripting.swbemsink]

    # Attach our handler to it
    set ::twapi::_service_event_sink_id [$::twapi::_service_event_sink -bind twapi::_service_change_handler]

    # Associate the sink with a query that polls every 1 sec for service
    # starts.
    $::twapi::_service_wmi ExecNotificationQueryAsync [$::twapi::_service_event_sink -interface] "select * from __InstanceModificationEvent within 1 where TargetInstance ISA 'Win32_Service'"
}

# Stop tracking of services
proc twapi::_stop_service_tracker {} {
    # Cancel event notifications
    $::twapi::_service_event_sink Cancel

    # Unbind our callback
    $::twapi::_service_event_sink -unbind $::twapi::_service_event_sink_id

    # Get rid of all objects
    $::twapi::_service_event_sink -destroy
    $::twapi::_service_wmi -destroy
}

#================ NEW COM CODE

namespace eval twapi {
    # TBD - enable oo if available
    if {0} {
        namespace import ::oo::class
    } else {
        namespace import ::metoo::class
    }

    # The prototype cache is indexed a composite key consisting of
    #  - the GUID of the interface,
    #  - the name of the function
    #  - the LCID
    #  - the invocation kind (as an integer)
    # Each value contains the full prototype in a form
    # that can be passed to IDispatch_Invoke. This is a list with the
    # elements {DISPID LCID INVOKEFLAGS RETTYPE PARAMTYPES}
    # Here PARAMTYPES is a list each element of which describes a
    # parameter in the following format:
    #     {TYPE {FLAGS DEFAULT}} where DEFAULT is optional
    # 
    
    variable _dispatch_prototype_cache
    array set _dispatch_prototype_cache {}
}


proc twapi::_dispatch_prototype_get {guid name lcid invkind vproto} {
    variable _dispatch_prototype_cache
    set invkind [::twapi::_string_to_invkind $invkind]
    if {[info exists _dispatch_prototype_cache($guid,$name,$lcid,$invkind)]} {
        # Note this may be null if that name does not exist in the interface
        upvar 1 $vproto proto
        set proto $_dispatch_prototype_cache($guid,$name,$lcid,$invkind)
        return 1
    }
    return 0
}

# Update a prototype in cache. Note lcid and invkind cannot be
# picked up from prototype since it might be empty.
proc twapi::_dispatch_prototype_set {guid name lcid invkind proto} {
    variable _dispatch_prototype_cache
    set invkind [_string_to_invkind $invkind]
    set _dispatch_prototype_cache($guid,$name,$lcid,$invkind) $proto
}

# Explicitly set prototypes for a guid 
# protolist is a list of alternating name and prototype pairs.
# Each prototype must contain the LCID and invkind fields
proc twapi::_dispatch_prototype_load {guid protolist} {
    foreach {name proto} $protolist {
        _dispatch_prototype_set $guid $name [lindex $proto 1] [lindex $proto 2] $proto
    }
}

# Used to track when interface proxies are renamed/deleted
proc twapi::_interface_proxy_tracer {ifc oldname newname op} {
    variable _interface_proxies
    if {$op eq "rename"} {
        if {$oldname eq $newname} return
        set _interface_proxies($ifc) $newname
    } else {
        unset _interface_proxies($ifc)
    }
}


# Return a COM interface proxy object for the specified interface.
# If such an object already exists, it is returned. Otherwise a new one
# is created. $ifc must be a valid COM Interface pointer for which
# the caller is holding a reference. Caller relinquishes ownership
# of the interface and must solely invoke operations through the
# returned proxy object. When done with the object, call the Release
# method on it, NOT destroy.
proc twapi::make_interface_proxy {ifc} {
    variable _interface_proxies

    if {[info exists _interface_proxies($ifc)]} {
        set proxy $_interface_proxies($ifc)
        $proxy AddRef
        if {! [Twapi_IsNullPtr $ifc]} {
            # Release the caller's ref to the interface since we are holding
            # one in the proxy object
            ::twapi::IUnknown_Release $ifc
        }
    } else {
        if {[Twapi_IsNullPtr $ifc]} {
            set proxy [INullProxy new $ifc]
        } else {
            set ifcname [Twapi_PtrType $ifc]
            set proxy [${ifcname}Proxy new $ifc]
        }
        set _interface_proxies($ifc) $proxy
        trace add command $proxy {rename delete} [list ::twapi::_interface_proxy_tracer $ifc]
    }
    return $proxy
}

# "Null" object - clones IUnknown but will raise error on method calls
twapi::class create ::twapi::INullProxy {
    constructor {ifc} {
        my variable _ifc
        # We keep the interface pointer because it encodes type information
        if {! [::twapi::Twapi_IsNullPtr $ifc]} {
            error "Attempt to create a INullProxy with non-NULL interface"
        }

        my variable _nrefs;   # Internal ref count (held by app)
        set _nrefs 1
    }

    method @Null? {} { return true }
    method @Type {} {
        my variable _ifc
        return [::twapi::Twapi_PtrType $_ifc]
    }
    method @Type? {type} {
        my variable _ifc
        return [::twapi::Twapi_IsPtr $_ifc $type]
    }
    method AddRef {} {
        my variable _nrefs
        # We maintain our own ref counts.
        incr _nrefs
    }

    method Release {} {
        my variable _nrefs
        if {[incr _nrefs -1] == 0} {
            my destroy
        }
    }
}

twapi::class create ::twapi::IUnknownProxy {
    # Note caller must hold ref on the ifc. This ref is passed to
    # the proxy object and caller must not make use of that ref
    # unless it does an AddRef on it.
    constructor {ifc} {

        if {[::twapi::Twapi_IsNullPtr $ifc]} {
            error "Attempt to register a NULL interface"
        }

        my variable _ifc
        set _ifc $ifc

        # We keep an internal reference count instead of explicitly
        # calling out to the object's AddRef/Release every time.
        # When the internal ref count goes to 0, we will invoke the 
        # object's "native" Release.
        #
        # Note the primary purpose of maintaining our internal reference counts
        # is not efficiency by shortcutting the "native" AddRefs. It is to
        # prevent crashes by bad application code; we can just generate an
        # error instead by having the command go away.
        my variable _nrefs;   # Internal ref count (held by app)

        set _nrefs 1
    }

    destructor {
        my variable _ifc
        ::twapi::IUnknown_Release $_ifc
    }

    method AddRef {} {
        my variable _nrefs
        # We maintain our own ref counts. Not pass it on to the actual object
        incr _nrefs
    }

    method Release {} {
        my variable _nrefs
        if {[incr _nrefs -1] == 0} {
            my destroy
        }
    }

    method QueryInterface {name_or_iid} {
        my variable _ifc
        lassign [::twapi::_resolve_iid $name_or_iid] iid name
        return [::twapi::Twapi_IUnknown_QueryInterface $_ifc $iid $name]
    }

    # Same as QueryInterface except return "" instead of exception
    # if interface not found and returns proxy object instead of interface
    method @QueryInterface {name_or_iid} {
        ::twapi::trap {
            return [::twapi::make_interface_proxy [my QueryInterface $name_or_iid]]
        } onerror {TWAPI_WIN32 0x80004002} {
            # No such interface, return "", don't generate error
            return ""
        }
    }

    method @Type {} {
        my variable _ifc
        return [::twapi::Twapi_PtrType $_ifc]
    }

    method @Type? {type} {
        my variable _ifc
        return [::twapi::Twapi_IsPtr $_ifc $type]
    }

    method @Null? {} {
        # Should never be true since we check in constructor
        return 0
    }

    # Returns raw interface. Caller must call IUnknown_Release on it
    method @Interface {} {
        my variable _ifc
        ::twapi::IUnknown_AddRef $_ifc
        return $_ifc
    }

}

twapi::class create ::twapi::IDispatchProxy {
    superclass ::twapi::IUnknownProxy

    destructor {
        my variable _typecomp
        if {[info exists _typecomp] && $_typecomp ne ""} {
            $_typecomp Release
        }
        next
    }

    method GetTypeInfoCount {} {
        my variable _ifc
        return [::twapi::IDispatch_GetTypeInfoCount $_ifc]
    }

    # names is list - method name followed by parameter names
    # Returns list of name dispid pairs
    method GetIDsOfNames {names {lcid 0}} {
        my variable _ifc
        return [::twapi::IDispatch_GetIDsOfNames $_ifc $names $lcid]
    }

    # Get dispid of a method (without parameter names)
    method @GetIDOfOneName {name {lcid 0}} {
        return [lindex [my GetIDsOfNames [list $name] $lcid] 1]
    }

    method GetTypeInfo {{infotype 0} {lcid 0}} {
        my variable _ifc
        if {$infotype != 0} {error "Parameter infotype must be 0"}
        return [::twapi::IDispatch_GetTypeInfo $_ifc $infotype $lcid]
    }

    method @GetTypeInfo {{lcid 0}} {
        return [::twapi::make_interface_proxy [my GetTypeInfo 0 $lcid]]
    }

    method Invoke {prototype args} {
        my variable _ifc
        if {$prototype eq "" && [llength $args] == 0} {
            # Treat as a property get DISPID_VALUE (default value)
            # {dispid=0, lcid=0 cmd=propget(2) ret type=bstr(8) {} (no params)}
            set prototype {0 0 2 8 {}}
        }
        # The uplevel is so that if some parameters are output, the varnames
        # are resolved in caller
        uplevel 1 [list ::twapi::IDispatch_Invoke $_ifc $prototype] $args
    }

    # Methods are tried in the order specified by invkinds.
    method @Invoke {name invkinds lcid params} {
        if {$name eq ""} {
            # Default method
            return [uplevel 1 [list [self] Invoke {}] $params]
        } else {
            set nparams [llength $params]

            # We will try for each invkind to match. matches can be of
            # different degrees, in descending priority -
            # - prototype has parameter info and num params match exactly
            # - prototype has parameter info and num params is greater
            #   than supplied arguments (assumes others have defaults)
            # - prototype has no parameter information
            # Within these classes, the order of invkinds determines
            # priority

            foreach invkind $invkinds {
                set proto [my @Prototype $name $invkind $lcid]
                if {[llength $proto]} {
                    if {[llength $proto] < 5} {
                        # No parameter information
                        lappend class3 $proto
                    } else {
                        if {[llength [lindex $proto 4]] == $nparams} {
                            lappend class1 $proto
                            break; # Class 1 match, no need to try others
                        } elseif {[llength [lindex $proto 4]] > $nparams} {
                            lappend class2 $proto
                        } else {
                            # Ignore - proto has fewer than supplied params
                            # Could not be a match
                        }
                    }
                }
            }

            if {[info exists class1]} {
                set proto [lindex $class1 0]
            } elseif {[info exists class2]} {
                set proto [lindex $class2 0]
            } elseif {[info exists class3]} {
                set proto [lindex $class3 0]
            } else {
                # No prototype via typecomp / typeinfo available. No lcid worked.
                # We have to use the last resort of GetIDsOfNames
                set dispid [my @GetIDOfOneName [list $name] 0]
                # TBD - should we cache result ? Probably not.
                if {$dispid ne ""} {
                    # Note params field (last) is missing signifying we do not
                    # know prototypes
                    set proto [list $dispid 0 [lindex $invkinds 0] 8]
                } else {
                    twapi::win32_error 0x80020003 "No property or method found with name '$name'."
                }
            }

            # Need uplevel so by-ref param vars are resolved correctly
            return [uplevel 1 [list [self] Invoke $proto] $params]
        }
    }

    # Get prototype that match the specified name
    method @Prototype {name invkind lcid} {
        my variable  _ifc  _guid  _typecomp

        # If we have been through here before and have our guid,
        # check if a prototype exists and return it. 
        if {[info exists _guid] && $_guid ne "" &&
            [::twapi::_dispatch_prototype_get $_guid $name $lcid $invkind proto]} {
            return $proto
        }

        # Not in cache, have to look for it
        # Get the ITypeComp for this interface if we do not
        # already have it. We trap any errors because we will retry with
        # different LCID's below.
        set proto {}
        my @InitTypeCompAndGuid; # Inits _guid and _typecomp
        if {$_typecomp ne ""} {
            ::twapi::trap {

                set invkind [::twapi::_string_to_invkind $invkind]
                set lhash   [::twapi::LHashValOfName $lcid $name]

                if {![catch {$_typecomp Bind $name $lhash $invkind} binddata] &&
                    [llength $binddata]} {
                    lassign $binddata type data ifc
                    if {$type eq "funcdesc" ||
                        ($type eq "vardesc" && [::twapi::kl_get $data varkind] == 3)} {
                        set params {}
                        set bindti [::twapi::make_interface_proxy $ifc]
                        ::twapi::trap {
                            set params [::twapi::_resolve_params_for_prototype $bindti [::twapi::kl_get $data lprgelemdescParam]]
                        } finally {
                            $bindti Release
                        }
                        set proto [list [::twapi::kl_get $data memid] \
                                       $lcid \
                                       $invkind \
                                       [::twapi::kl_get $data elemdescFunc.tdesc] \
                                       $params]
                    } else {
                        ::twapi::IUnknown_Release $ifc; # Don't need this but must release
                        debuglog "IDispatchProxy::@Prototype: Unexpected Bind type: $type, data: $data"
                    }
                }
            } onerror {} {
                # Ignore and retry with other LCID's below
            }
        }


        # If we do not have a guid return because even if we do not
        # have a proto yet,  falling through to try another lcid will not
        # help and in fact will cause infinite recursion.
        
        if {$_guid eq ""} {
            return $proto
        }

        # We do have a guid, store the proto in cache (even if negative)
        ::twapi::_dispatch_prototype_set $_guid $name $lcid $invkind $proto

        # If we have the proto return it
        if {[llength $proto]} {
            return $proto
        }

        # Could not find a matching prototype from the typeinfo/typecomp.
        # We are not done yet. We will try and fall back to other lcid's
        # Note we do this AFTER setting the prototype in the cache. That
        # way we prevent (infinite) mutual recursion between lcid fallbacks.
        # The fallback sequence is $lcid -> 0 -> 1033
        # (1033 is US English). Note lcid could itself be 1033
        # default and land up being checked twice times but that's
        # ok since that's a one-time thing, and not very expensive either
        # since the second go-around will hit the cache (negative). 
        # Note the time this is really useful is when the cache has
        # been populated explicitly from a type library since in that
        # case many interfaces land up with a US ENglish lcid (MSI being
        # just one example)

        if {$lcid == 0} {
            # Note this call may further recurse and return either a
            # proto or empty (fail)
            set proto [my @Prototype $name $invkind 1033]
        } else {
            set proto [my @Prototype $name $invkind 0]
        }
        
        # Store it as *original* lcid.
        ::twapi::_dispatch_prototype_set $_guid $name $lcid $invkind $proto
        
        return $proto
    }


    # Initialize _typecomp and _guid. Not in constructor because may
    # not always be required. Raises error if not available
    method @InitTypeCompAndGuid {} {
        my variable   _guid   _typecomp
        
        if {[info exists _typecomp]} {
            return
        }

        ::twapi::trap {
            set ti [my @GetTypeInfo 0]
        } onerror {} {
            # We do not raise an error because
            # even without the _typecomp we can try invoking
            # methods via IDispatch::GetIDsOfNames
            if {![info exists _guid]} {
                # Do not overwrite if set thru @SetGuid
                set _guid ""
            }
            set _typecomp ""
            return
        }

        ::twapi::trap {
            # In case of dual interfaces, we need the typeinfo for the 
            # dispatch. Again, errors handled in try handlers
            switch -exact -- [::twapi::kl_get [$ti GetTypeAttr] typekind] {
                4 {
                    # Dispatch type, fine, just what we want
                }
                3 {
                    # Interface type, Get the dispatch interface
                    set ti2 [$ti @GetRefTypeInfo [$ti GetRefTypeOfImplType -1]]
                    $ti Release
                    set ti $ti2
                }
                default {
                    error "Interface is not a dispatch interface"
                }
            }
            set _guid [::twapi::kl_get [$ti GetTypeAttr] guid]
            set _typecomp [$ti @GetTypeComp]; # ITypeComp

        } finally {
            $ti Release
        }
    }            

    # Some COM objects like MSI do not have TypeInfo interfaces from
    # where the GUID and TypeComp can be extracted. So we allow caller
    # to explicitly set the GUID so we can look up methods in the
    # dispatch prototype cache if it was populated directly by the
    # application. If guid is not a valid GUID, an attempt is made
    # to look it up as an IID name.
    method @SetGuid {guid} {
        my variable _guid
        if {$guid eq ""} {
            if {![info exists _guid]} {
                my @InitTypeCompAndGuid
            }
        } else {
            if {![::twapi::Twapi_IsValidGUID $guid]} {
                set resolved_guid [::twapi::name_to_iid $guid]
                if {$resolved_guid eq ""} {
                    error "Could not resolve $guid to a Interface GUID."
                }
                set guid $resolved_guid
            }

            if {[info exists _guid] && $_guid ne ""} {
                if {[string compare -nocase $guid $_guid]} {
                    error "Attempt to set the GUID to $guid when the dispatch proxy has already been initialized to $_guid"
                }
            } else {
                set _guid $guid
            }
        }

        return $_guid
    }

    method @GetCoClassTypeInfo {{co_clsid ""}} {
        my variable _ifc
        # We can get the typeinfo for the coclass in one of two ways:
        # If the object supports IProvideClassInfo, we use it. Else
        # we try the following:
        #   - from the idispatch, we get its typeinfo
        #   - from the typeinfo, we get the containing typelib
        #   - then we search the typelib for the coclass clsid

        ::twapi::trap {
            set pci_ifc [my QueryInterface IProvideClassInfo]
            set ti_ifc [::twapi::IProvideClassInfo_GetClassInfo $pci_ifc]
            return [::twapi::make_interface_proxy $ti_ifc]
        } onerror {} {
            # Ignore - try the longer route if we were given the coclass clsid
        } finally {
            if {[info exists pci_ifc]} {
                ::twapi::IUnknown_Release $pci_ifc
            }
            # Note - do not do anything with ti_ifc here, EVEN on error
        }

        if {$co_clsid eq ""} {
            # E_FAIL
            win32_error 0x80004005 "Could not get ITypeInfo for coclass: object does not support IProvideClassInfo and clsid not specified."
        }

        set ti [my @GetTypeInfo]
        ::twapi::trap {
            set tl [lindex [$ti @GetContainingTypeLib] 0]
            if {0} {
                $tl @Foreach -guid $co_clsid -type coclass coti {
                    break
                }
                if {[info exists coti]} {
                    return $coti
                }
            } else {
                return [$tl @GetTypeInfoOfGuid $co_clsid]
            }
            win32_error 0x80004005 "Could not find coclass."; # E_FAIL
        } finally {
            if {[info exists ti]} {
                $ti Release
            }
            if {[info exists tl]} {
                $tl Release
            }
        }
    }
}


twapi::class create ::twapi::IDispatchExProxy {
    superclass ::twapi::IDispatchProxy

    method DeleteMemberByDispID {dispid} {
        my variable _ifc
        return [::twapi::IDispatchEx_DeleteMemberByDispID $_ifc $dispid]
    }

    method DeleteMemberByName {name {lcid 0}} {
        my variable _ifc
        return [::twapi::IDispatchEx_DeleteMemberByName $_ifc $name $lcid]
    }

    method GetDispID {name flags} {
        my variable _ifc
        return [::twapi::IDispatchEx_GetDispID $_ifc $name $flags]
    }

    method GetMemberName {dispid} {
        my variable _ifc
        return [::twapi::IDispatchEx_GetMemberName $_ifc $dispid]
    }

    method GetMemberProperties {dispid flags} {
        my variable _ifc
        return [::twapi::IDispatchEx_GetMemberProperties $_ifc $dispid $flags]
    }

    # For some reason, order of args is different for this call!
    method GetNextDispID {flags dispid} {
        my variable _ifc
        return [::twapi::IDispatchEx_GetNextDispID $_ifc $flags $dispid]
    }

    method GetNameSpaceParent {} {
        my variable _ifc
        return [::twapi::IDispatchEx_GetNameSpaceParent $_ifc]
    }

    method @GetNameSpaceParent {} {
        return [::twapi::make_interface_proxy [my GetNameSpaceParent]]
    }

    method @Prototype {name invkind {lcid 0}} {
        set invkind [::twapi::_string_to_invkind $invkind]

        # First try IDispatch
        ::twapi::trap {
            set proto [next $name $invkind $lcid]
            if {[llength $proto]} {
                return $proto
            }
            # Note negative results ignored, as new members may be added/deleted
            # to an IDispatchEx at any time. We will try below another way.

        } onerror {} {
            # Ignore the error - we will try below using another method
        }

        # Not a simple dispatch interface method. Could be expando
        # type which is dynamically created. NOTE: The member is NOT
        # created until the GetDispID call is made.

        # 10 -> case insensitive, create if required
        set dispid [my GetDispID $name 10]

        # IMPORTANT : prototype retrieval results MUST NOT be cached since
        # underlying object may add/delete members at any time.

        # No type information is available for dynamic members.
        # TBD - is that really true?
        
        # Invoke kind - 1 (method), 2 (propget), 4 (propput)
        if {$invkind == 1} {
            # method
            set flags 0x100
        } elseif {$invkind == 2} {
            # propget
            set flags 0x1
        } elseif {$invkind == 4} {
            # propput
            set flags 0x4
        } else {
            # TBD - what about putref (flags 0x10)
            error "Internal error: Invalid invkind value $invkind"
        }

        # Try at least getting the invocation type but even that is not
        # supported by all objects in which case we assume it can be invoked.
        # TBD - in that case, why even bother doing GetMemberProperties?
        if {! [catch {
            set flags [expr {[my GetMemberProperties 0x115] & $flags}]
        }]} {
            if {! $flags} {
                return {};      # EMpty proto -> no valid name for this invkind
            }
        }

        # Valid invkind or object does not support GetMemberProperties
        # Return type is 8 (BSTR) but does not really matter as 
        # actual type will be set based on what is returned.
        return [list $dispid $lcid $invkind 8]
    }
}


# ITypeInfo 
#-----------

twapi::class create ::twapi::ITypeInfoProxy {
    superclass ::twapi::IUnknownProxy

    method GetRefTypeOfImplType {index} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetRefTypeOfImplType $_ifc $index]
    }

    method GetDocumentation {memid} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetDocumentation $_ifc $memid]
    }

    method GetImplTypeFlags {index} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetImplTypeFlags $_ifc $index]
    }

    method GetNames {index} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetNames $_ifc $index]
    }

    method GetTypeAttr {} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetTypeAttr $_ifc]
    }

    method GetFuncDesc {index} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetFuncDesc $_ifc $index]
    }

    method GetVarDesc {index} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetVarDesc $_ifc $index]
    }

    method GetIDsOfNames {names} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetIDsOfNames $_ifc $names]
    }

    method GetRefTypeInfo {hreftype} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetRefTypeInfo $_ifc $hreftype]
    }

    method @GetRefTypeInfo {hreftype} {
        return [::twapi::make_interface_proxy [my GetRefTypeInfo $hreftype]]
    }

    method GetTypeComp {} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetTypeComp $_ifc]
    }

    method @GetTypeComp {} {
        return [::twapi::make_interface_proxy [my GetTypeComp]]
    }

    method GetContainingTypeLib {} {
        my variable _ifc
        return [::twapi::ITypeInfo_GetContainingTypeLib $_ifc]
    }

    method @GetContainingTypeLib {} {
        lassign [my GetContainingTypeLib] itypelib index
        return [list [::twapi::make_interface_proxy $itypelib] $index]
    }

    method @GetRefTypeInfoFromIndex {index} {
        return [my @GetRefTypeInfo [my GetRefTypeOfImplType $index]]
    }

    # Friendlier version of GetTypeAttr
    method @GetTypeAttr {args} {

        array set opts [::twapi::parseargs args {
            all
            guid
            lcid
            constructorid
            destructorid
            schema
            instancesize
            typekind
            fncount
            varcount
            interfacecount
            vtblsize
            alignment
            majorversion
            minorversion
            aliasdesc
            flags
            idldesc
            memidmap
        } -maxleftover 0]

        array set data [my GetTypeAttr]
        set result [list ]
        foreach {opt key} {
            guid guid
            lcid lcid
            constructorid memidConstructor
            destructorid  memidDestructor
            schema lpstrSchema
            instancesize cbSizeInstance
            fncount cFuncs
            varcount cVars
            interfacecount cImplTypes
            vtblsize cbSizeVft
            alignment cbAlignment
            majorversion wMajorVerNum
            minorversion wMinorVerNum
            aliasdesc tdescAlias
        } {
            if {$opts(all) || $opts($opt)} {
                lappend result -$opt $data($key)
            }
        }

        if {$opts(all) || $opts(typekind)} {
            set typekind $data(typekind)
            if {[info exists ::twapi::_typekind_map($typekind)]} {
                set typekind $::twapi::_typekind_map($typekind)
            }
            lappend result -typekind $typekind
        }

        if {$opts(all) || $opts(flags)} {
            lappend result -flags [::twapi::_make_symbolic_bitmask $data(wTypeFlags) {
                appobject       1
                cancreate       2
                licensed        4
                predeclid       8
                hidden         16
                control        32
                dual           64
                nonextensible 128
                oleautomation 256
                restricted    512
                aggregatable 1024
                replaceable  2048
                dispatchable 4096
                reversebind  8192
                proxy       16384
            }]
        }

        if {$opts(all) || $opts(idldesc)} {
            lappend result -idldesc [::twapi::_make_symbolic_bitmask $data(idldescType) {
                in 1
                out 2
                lcid 4
                retval 8
            }]
        }

        if {$opts(all) || $opts(memidmap)} {
            set memidmap [list ]
            for {set i 0} {$i < $data(cFuncs)} {incr i} {
                array set fninfo [my @GetFuncDesc $i -memid -name]
                lappend memidmap $fninfo(-memid) $fninfo(-name)
            }
            lappend result -memidmap $memidmap
        }

        return $result
    }

    #
    # Get a variable description associated with a type
    method @GetVarDesc {index args} {
        # TBD - add support for retrieving elemdescVar.paramdesc fields

        array set opts [::twapi::parseargs args {
            all
            name
            memid
            schema
            datatype
            value
            valuetype
            varkind
            flags
        } -maxleftover 0]

        array set data [my GetVarDesc $index]
        
        set result [list ]
        foreach {opt key} {
            memid memid
            schema lpstrSchema
            datatype elemdescVar.tdesc
        } {
            if {$opts(all) || $opts($opt)} {
                lappend result -$opt $data($key)
            }
        }


        if {$opts(all) || $opts(value)} {
            if {[info exists data(lpvarValue)]} {
                # Const value
                lappend result -value [lindex $data(lpvarValue) 1]
            } else {
                lappend result -value $data(oInst)
            }
        }

        if {$opts(all) || $opts(valuetype)} {
            if {[info exists data(lpvarValue)]} {
                lappend result -valuetype [lindex $data(lpvarValue) 0]
            } else {
                lappend result -valuetype int
            }
        }

        if {$opts(all) || $opts(varkind)} {
            lappend result -varkind [::twapi::kl_get {
                0 perinstance
                1 static
                2 const
                3 dispatch
            } $data(varkind) $data(varkind)]
        }

        if {$opts(all) || $opts(flags)} {
            lappend result -flags [::twapi::_make_symbolic_bitmask $data(wVarFlags) {
                readonly       1
                source       2
                bindable        4
                requestedit       8
                displaybind         16
                defaultbind        32
                hidden           64
                restricted 128
                defaultcollelem 256
                uidefault    512
                nonbrowsable 1024
                replaceable  2048
                immediatebind 4096
            }]
        }
        
        if {$opts(all) || $opts(name)} {
            set result [concat $result [my @GetDocumentation $data(memid) -name]]
        }    

        return $result
    }

    method @GetFuncDesc {index args} {
        array set opts [::twapi::parseargs args {
            all
            name
            memid
            funckind
            invkind
            callconv
            params
            paramnames
            flags
            datatype
            resultcodes
            vtbloffset
        } -maxleftover 0]

        array set data [my GetFuncDesc $index]
        set result [list ]

        if {$opts(all) || $opts(paramnames)} {
            lappend result -paramnames [lrange [my GetNames $data(memid)] 1 end]
        }
        foreach {opt key} {
            memid       memid
            vtbloffset  oVft
            datatype    elemdescFunc.tdesc
            resultcodes lprgscode
        } {
            if {$opts(all) || $opts($opt)} {
                lappend result -$opt $data($key)
            }
        }

        if {$opts(all) || $opts(funckind)} {
            lappend result -funckind [::twapi::kl_get {
                0 virtual
                1 purevirtual
                2 nonvirtual
                3 static
                4 dispatch
            } $data(funckind) $data(funckind)]
        }

        if {$opts(all) || $opts(invkind)} {
            lappend result -invkind [::twapi::_string_to_invkind $data(invkind)]
        }

        if {$opts(all) || $opts(callconv)} {
            lappend result -callconv [::twapi::kl_get {
                0 fastcall
                1 cdecl
                2 pascal
                3 macpascal
                4 stdcall
                5 fpfastcall
                6 syscall
                7 mpwcdecl
                8 mpwpascal
            } $data(callconv) $data(callconv)]
        }

        if {$opts(all) || $opts(flags)} {
            lappend result -flags [::twapi::_make_symbolic_bitmask $data(wFuncFlags) {
                restricted   1
                source       2
                bindable     4
                requestedit  8
                displaybind  16
                defaultbind  32
                hidden       64
                usesgetlasterror  128
                defaultcollelem 256
                uidefault    512
                nonbrowsable 1024
                replaceable  2048
                immediatebind 4096
            }]
        }

        if {$opts(all) || $opts(params)} {
            set params [list ]
            foreach param $data(lprgelemdescParam) {
                lassign $param paramtype paramdesc
                set paramflags [::twapi::_paramflags_to_tokens [lindex $paramdesc 0]]
                if {[llength $paramdesc] > 1} {
                    # There is a default value associated with the parameter
                    lappend params [list $paramtype $paramflags [lindex $paramdesc 1]]
                } else {
                    lappend params [list $paramtype $paramflags]
                }
            }
            lappend result -params $params
        }

        if {$opts(all) || $opts(name)} {
            set result [concat $result [my @GetDocumentation $data(memid) -name]]
        }    

        return $result
    }

    #
    # Get documentation for a element of a type
    method @GetDocumentation {memid args} {
        array set opts [::twapi::parseargs args {
            all
            name
            docstring
            helpctx
            helpfile
        } -maxleftover 0]

        lassign [my GetDocumentation $memid] name docstring helpctx helpfile

        set result [list ]
        foreach opt {name docstring helpctx helpfile} {
            if {$opts(all) || $opts($opt)} {
                lappend result -$opt [set $opt]
            }
        }
        return $result
    }

    method @GetName {{memid -1}} {
        return [lindex [my @GetDocumentation $memid -name] 1]
    }

    method @GetImplTypeFlags {index} {
        return [::twapi::_make_symbolic_bitmask \
                    [my GetImplTypeFlags $index] \
                    {
                        default      1
                        source       2
                        restricted   4
                        defaultvtable 8
                    }]  
    }

    #
    # Get the typeinfo for the default source interface of a coclass
    # This object must be the typeinfo of the coclass
    method @GetDefaultSourceTypeInfo {} {
        set count [lindex [my @GetTypeAttr -interfacecount] 1]
        for {set i 0} {$i < $count} {incr i} {
            set flags [my GetImplTypeFlags $i]
            # default 0x1, source 0x2
            if {($flags & 3) == 3} {
                return [my @GetRefTypeInfoFromIndex $i]
            }
        }
        return ""
    }
}


# ITypeLib
#----------

twapi::class create ::twapi::ITypeLibProxy {
    superclass ::twapi::IUnknownProxy

    method GetDocumentation {index} {
        my variable _ifc
        return [::twapi::ITypeLib_GetDocumentation $_ifc $index]
    }
    method GetTypeInfoCount {} {
        my variable _ifc
        return [::twapi::ITypeLib_GetTypeInfoCount $_ifc]
    }
    method GetTypeInfoType {index} {
        my variable _ifc
        return [::twapi::ITypeLib_GetTypeInfoType $_ifc $index]
    }
    method GetLibAttr {} {
        my variable _ifc
        return [::twapi::ITypeLib_GetLibAttr $_ifc]
    }
    method GetTypeInfo {index} {
        my variable _ifc
        return [::twapi::ITypeLib_GetTypeInfo $_ifc $index]
    }
    method @GetTypeInfo {index} {
        return [::twapi::make_interface_proxy [my GetTypeInfo $index]]
    }
    method GetTypeInfoOfGuid {guid} {
        my variable _ifc
        return [::twapi::ITypeLib_GetTypeInfoOfGuid $_ifc $guid]
    }
    method @GetTypeInfoOfGuid {guid} {
        return [::twapi::make_interface_proxy [my GetTypeInfoOfGuid $guid]]
    }
    method @GetTypeInfoType {index} {
        set typekind [my GetTypeInfoType $index]
        if {[info exists ::twapi::_typekind_map($typekind)]} {
            set typekind $::twapi::_typekind_map($typekind)
        }
        return $typekind
    }

    method @GetDocumentation {id args} {
        array set opts [::twapi::parseargs args {
            all
            name
            docstring
            helpctx
            helpfile
        } -maxleftover 0]

        lassign [my GetDocumentation $id] name docstring helpctx helpfile
        set result [list ]
        foreach opt {name docstring helpctx helpfile} {
            if {$opts(all) || $opts($opt)} {
                lappend result -$opt [set $opt]
            }
        }
        return $result
    }

    method @GetLibAttr {args} {
        array set opts [::twapi::parseargs args {
            all
            guid
            lcid
            syskind
            majorversion
            minorversion
            flags
        } -maxleftover 0]

        array set data [my GetLibAttr]
        set result [list ]
        foreach {opt key} {
            guid guid
            lcid lcid
            majorversion wMajorVerNum
            minorversion wMinorVerNum
        } {
            if {$opts(all) || $opts($opt)} {
                lappend result -$opt $data($key)
            }
        }

        if {$opts(all) || $opts(flags)} {
            lappend result -flags [::twapi::_make_symbolic_bitmask $data(wLibFlags) {
                restricted      1
                control         2
                hidden          4
                hasdiskimage    8
            }]
        }

        if {$opts(all) || $opts(syskind)} {
            lappend result -syskind [::twapi::kl_get {
                0 win16
                1 win32
                2 mac
            } $data(syskind) $data(syskind)]
        }

        return $result
    }

    #
    # Iterate through a typelib. Caller is responsible for releasing
    # each ITypeInfo passed to it
    # 
    method @Foreach {args} {

        array set opts [::twapi::parseargs args {
            type.arg
            name.arg
            guid.arg
        } -maxleftover 2 -nulldefault]

        if {[llength $args] != 2} {
            error "Syntax error: Should be '[self] @Foreach ?options? VARNAME SCRIPT'"
        }

        lassign $args varname script
        upvar $varname varti

        set count [my GetTypeInfoCount]
        for {set i 0} {$i < $count} {incr i} {
            if {$opts(type) ne "" && $opts(type) ne [my @GetTypeInfoType $i]} {
                continue;                   # Type does not match
            }
            if {$opts(name) ne "" &&
                [string compare -nocase $opts(name) [lindex [my @GetDocumentation $i -name] 1]]} {
                continue;                   # Name does not match
            }
            set ti [my @GetTypeInfo $i]
            if {$opts(guid) ne ""} {
                if {[string compare -nocase [lindex [$ti @GetTypeAttr -guid] 1] $opts(guid)]} {
                    $ti Release
                    continue
                }
            }
            set varti $ti
            set ret [catch {uplevel 1 $script} result]
            switch -exact -- $ret {
                1 {
                    error $result $::errorInfo $::errorCode
                }
                2 {
                    return -code return $result; # TCL_RETURN
                }
                3 {
                    set i $count; # TCL_BREAK
                }
            }
        }
        return
    }

    method @Register {path {helppath ""}} {
        my variable _ifc
        ::twapi::RegisterTypeLib $_ifc $path $helppath
    }

    method @LoadDispatchPrototypes {} {
        my @Foreach -type dispatch ti {
            ::twapi::trap {
                array set attrs [$ti GetTypeAttr]
                # Load up the functions
                for {set j 0} {$j < $attrs(cFuncs)} {incr j} {
                    array set funcdata [$ti GetFuncDesc $j]
                    if {$funcdata(funckind) != 4} {
                        # Not a dispatch function (4), ignore
                        # TBD - what else could it be if already filtering
                        # typeinfo on dispatch
                        # Vtable set funckind "(vtable $funcdata(-oVft))"
                        ::twapi::debuglog "Unexpected funckind value '$funcdata(funckind)' ignored. funcdata: [array get funcdata]"
                        continue;
                    }
                    
                    set proto [list $funcdata(memid) \
                                   $attrs(lcid) \
                                   $funcdata(invkind) \
                                   $funcdata(elemdescFunc.tdesc) \
                                   [::twapi::_resolve_params_for_prototype $ti $funcdata(lprgelemdescParam)]]
                    ::twapi::_dispatch_prototype_set \
                        $attrs(guid) [$ti @GetName $funcdata(memid)] \
                        $attrs(lcid) \
                        $funcdata(invkind) \
                        $proto
                }
                # Load up the properties
                for {set j 0} {$j < $attrs(cVars)} {incr j} {
                    array set vardata [$ti GetVarDesc $j]
                    # We will add both propput and propget.
                    # propget:
                    ::twapi::_dispatch_prototype_set \
                        $attrs(guid) [$ti @GetName $vardata(memid)] \
                        $attrs(lcid) \
                        2 \
                        [list $vardata(memid) $attrs(lcid) 2 $vardata(elemdescVar.tdesc) {}]

                    # TBD - mock up the parameters for the property set
                    # Single parameter corresponding to return type of
                    # property. Param list is of the form
                    # {PARAM1 PARAM2} where PARAM is {TYPE {FLAGS ?DEFAULT}}
                    # So param list with one param is
                    # {{TYPE {FLAGS ?DEFAULT?}}}
                    # propput:
                    if {! ($vardata(wVarFlags) & 1)} {
                        # Not read-only
                        ::twapi::_dispatch_prototype_set \
                            $attrs(guid) [$ti @GetName $vardata(memid)] \
                            $attrs(lcid) \
                            4 \
                            [list $vardata(memid) $attrs(lcid) 4 24 [list [list $vardata(elemdescVar.tdesc) [list 1]]]]
                    }
                }
            } finally {
                $ti Release
            }
        }
    }

    method @Text {args} {
        array set opts [::twapi::parseargs args {
            type.arg
            name.arg
        } -maxleftover 0 -nulldefault]

        set text {}
        my @Foreach -type $opts(type) -name $opts(name) ti {
            ::twapi::trap {
                array set attrs [$ti @GetTypeAttr -all]
                set docs [$ti @GetDocumentation -1 -name -docstring]
                set desc "[string totitle $attrs(-typekind)] [::twapi::kl_get $docs -name] - [::twapi::kl_get $docs -docstring]\n"
                switch -exact -- $attrs(-typekind) {
                    record -
                    union  -
                    enum {
                        for {set j 0} {$j < $attrs(-varcount)} {incr j} {
                            array set vardata [$ti @GetVarDesc $j -all]
                            set vardesc "$vardata(-varkind) [::twapi::_resolve_com_type_text $ti $vardata(-datatype)] $vardata(-name)"
                            if {$attrs(-typekind) eq "enum"} {
                                append vardesc " = $vardata(-value) ([::twapi::_resolve_com_type_text $ti $vardata(-valuetype)])"
                            } else {
                                append vardesc " (offset $vardata(-value))"
                            }
                            append desc "\t$vardesc\n"
                        }
                    }
                    alias {
                        append desc "\ttypedef $attrs(-aliasdesc)\n"
                    }
                    module -
                    dispatch -
                    interface {
                        append desc [::twapi::_interface_text $ti]
                    }
                    coclass {
                        for {set j 0} {$j < $attrs(-interfacecount)} {incr j} {
                            set ti2 [$ti @GetRefTypeInfoFromIndex $j]
                            set idesc [$ti2 @GetName]
                            set iflags [$ti @GetImplTypeFlags $j]
                            if {[llength $iflags]} {
                                append idesc " ([join $iflags ,])"
                            }
                            append desc \t$idesc
                            $ti2 Release
                            unset ti2
                        }
                    }
                    default {
                        append desc "Unknown typekind: $attrs(-typekind)\n"
                    }
                }
                append text \n$desc
            } finally {
                $ti Release
                if {[info exists ti2]} {
                    $ti2 Release
                }
            }
        }
        return $text
    }

}

# ITypeComp
#----------
twapi::class create ::twapi::ITypeCompProxy {
    superclass ::twapi::IUnknownProxy

    method Bind {name lhash flags} {
        my variable _ifc
        return [::twapi::ITypeComp_Bind $_ifc $name $lhash $flags]
    }

    # Returns empty list if bind not found
    method @Bind {name flags {lcid 0}} {
        ::twapi::trap {
            set binding [my Bind $name [::twapi::LHashValOfName $lcid $name] $flags]
        } onerror {TWAPI_WIN32 0x80028ca0} {
            # Found but type mismatch (flags not correct)
            return {}
        }

        lassign $binding type data tifc
        return [list $type $data [::twapi::make_interface_proxy $tifc]]
    }
}

# IEnumVARIANT
#-------------

twapi::class create ::twapi::IEnumVARIANTProxy {
    superclass ::twapi::IUnknownProxy

    method Next {count {value_only 0}} {
        my variable _ifc
        return [::twapi::IEnumVARIANT_Next $_ifc $count $value_only]
    }
    method Clone {} {
        my variable _ifc
        return [::twapi::IEnumVARIANT_Clone $_ifc]
    }
    method @Clone {} {
        return [::twapi::make_interface_proxy [my Clone]]
    }
    method Reset {} {
        my variable _ifc
        return [::twapi::IEnumVARIANT_Reset $_ifc]
    }
    method Skip {count} {
        my variable _ifc
        return [::twapi::IEnumVARIANT_Skip $_ifc $count]
    }
}

# Automation
#-----------
twapi::class create ::twapi::Automation {

    # Caller gives up ownership of proxy in all cases, even errors.
    # $proxy will eventually be Release'ed. If caller wants to keep
    # a reference to it, it must do an *additional* AddRef on it to
    # keep it from going away when the Automation object releases it.
    constructor {proxy {lcid 0}} {
        my variable   _proxy   _lcid   _sinks   _connection_pts

        set type [$proxy @Type]
        if {$type ne "IDispatch" && $type ne "IDispatchEx"} {
            $proxy Release;     # Even on error, responsible for releasing
            error "Automation objects do not support interfaces of type '$type'"
        }
        set _proxy $proxy
        set _lcid $lcid
        array set _sinks {}
        array set _connection_pts {}
    }

    destructor {
        my variable _proxy  _sinks

        # Release sinks, connection points
        foreach sinkid [array names _sinks] {
            my -unbind $sinkid
        }

        $_proxy Release
    }

    # Intended to be called only from another method. Not directly.
    # Does an uplevel 2 to get to application context.
    # On failures, retries with IDispatchEx interface
    method _invoke {name invkinds params} {
        my variable  _proxy  _lcid
        ::twapi::trap {
            return [::twapi::_variant_value [uplevel 2 [list $_proxy @Invoke $name $invkinds $_lcid $params]]]
        } onerror {} {
            set erinfo $::errorInfo
            set ercode $::errorCode
            set ermsg $::errorResult
        }

        # We plan on trying to get a IDispatchEx interface in case
        # the method/property is the "expando" type
        my variable  _have_dispex
        if {[info exists _have_dispex]} {
            # We have already tried for IDispatchEx, either successfully
            # or not. Either way, no need to try again
            error $ermsg $erinfo $ercode
        }

        # Try getting a IDispatchEx interface
        set proxy_ex [$_proxy @QueryInterface IDispatchEx]
        if {$proxy_ex eq ""} {
            set _have_dispex 0
            error $ermsg $erinfo $ercode
        }

        set _have_dispex 1
        $_proxy Release
        set _proxy $proxy_ex
        
        # Retry with the IDispatchEx interface
        return [::twapi::_variant_value [uplevel 2 [list $_proxy @Invoke $name $invkinds $_lcid $params]]]
    }

    method -get {name args} {
        return [my _invoke $name [list 2] $args]
    }

    method -set {name args} {
        return [my _invoke $name [list 4] $args]
    }

    method -call {name args} {
        return [my _invoke $name [list 1] $args]
    }

    method -destroy {} {
        # For backwords compatibility. Synonym for destroy
        my destroy
    }

    method -isnull {} {
        return false
    }

    method -default {} {
        my variable _proxy
        return [::twapi::_variant_value [$_proxy Invoke ""]]
    }

    # Caller must call release on the proxy
    method -proxy {} {
        my variable _proxy
        $_proxy AddRef
        return $_proxy
    }

    # Returns the raw interface. Caller must call IUnknownRelease on it.
    method -interface {} {
        my variable _proxy
        return [$_proxy @Interface]
    }

    # Set/return the GUID for the interface
    method -interfaceguid {{guid ""}} {
        my variable _proxy
        return [$_proxy @SetGuid $guid]
    }

    # Prints methods in an interface
    method -print {} {
        my variable _proxy
        ::twapi::dispatch_print $_proxy
    }

    method -with {subobjlist args} {
        # $obj -with SUBOBJECTPATHLIST arguments
        # where SUBOBJECTPATHLIST is list each element of which is
        # either a property or a method of the previous element in
        # the list. The element may itself be a list in which case
        # the first element is the property/method and remaining
        # are passed to it
        #
        # Note that 'arguments' may themselves be comobj subcommands!
        set next [self]
        set releaselist [list ]
        ::twapi::trap {
            while {[llength $subobjlist]} {
                set nextargs [lindex $subobjlist 0]
                set subobjlist [lrange $subobjlist 1 end]
                set next [uplevel 1 [list $next] $nextargs]
                lappend releaselist $next
            }
            # We use uplevel here because again we want to run in caller
            # context 
            return [uplevel 1 [list $next] $args]
        } finally {
            foreach next $releaselist {
                $next -destroy
            }
        }
    }

    method -iterate {varname script} {
        upvar 1 $varname var
        # First get IEnumVariant iterator using the _NewEnum method
        set enumerator [my -get _NewEnum]
        # This gives us an IUnknown.
        ::twapi::trap {
            # Convert the IUnknown to IEnumVARIANT
            set iter [$enumerator @QueryInterface IEnumVARIANT]
            if {! [$iter @Null?]} {
                set more 1
                while {$more} {
                    # Get the next item from iterator
                    set next [$iter Next 1]
                    lassign $next more values
                    if {[llength $values]} {
                        set var [::twapi::_variant_value [lindex $values 0]]
                        set ret [catch {uplevel 1 $script} msg]
                        switch -exact -- $ret {
                            1 {
                                error $msg $::errorInfo $::errorCode
                            }
                            2 {
                                return; # TCL_RETURN
                            }
                            3 {
                                set more 0; # TCL_BREAK
                            }
                        }
                    }
                }
            }
        } finally {
            $enumerator Release
            if {[info exists iter] && ![$iter @Null?]} {
                $iter Release
            }
        }
        return
    }

    method -bind {script} {
        my variable   _proxy   _sinks    _connection_pts

        # Get the coclass typeinfo and  locate the source interface
        # within it and retrieve disp id mappings
        ::twapi::trap {
            # TBD - where can we get co_clsid from ? Ask from caller?
            # Or part of automation class ?
            set co_clsid "";    # TBD - temp placeholder
            set coti [$_proxy @GetCoClassTypeInfo $co_clsid]

            # $coti is the coclass information. Get dispids for the default
            # source interface for events and its guid
            set srcti [$coti @GetDefaultSourceTypeInfo]
            array set srcinfo [$srcti @GetTypeAttr -memidmap -guid]

            # TBD - implement IConnectionPointContainerProxy
            # Now we need to get the actual connection point itself
            set container [$_proxy QueryInterface IConnectionPointContainer]
            set connpt_ifc [::twapi::IConnectionPointContainer_FindConnectionPoint $container $srcinfo(-guid)]

            # Finally, create our sink object
            # TBD - need to make sure Automation object is not deleted or
            # should the callback itself check?
            set sink_ifc [::twapi::ComEventSink $srcinfo(-guid) [list ::twapi::_eventsink_callback [self] $srcinfo(-memidmap) $script]]

            # OK, we finally have everything we need. Tell the event source
            set sinkid [::twapi::IConnectionPoint_Advise $connpt_ifc $sink_ifc]
            
            set _sinks($sinkid) $sink_ifc
            set _connection_pts($sinkid) $connpt_ifc
            return $sinkid
        } onerror {} {
            # These are released only on error as otherwise they have
            # to be kept until unbind time
            foreach ifc {connpt_ifc sink_ifc} {
                if {[info exists $ifc] && [set $ifc] ne ""} {
                    ::twapi::IUnknown_Release [set $ifc]
                }
            }
            error $errorResult $errorInfo $errorCode
        } finally {
            # In all cases, release any interfaces we created
            # Note connpt_ifc and sink_ifc are released at unbind time except
            # on error
            foreach obj {coti srcti} {
                if {[info exists $obj]} {
                    [set $obj] Release
                }
            }
            if {[info exists container]} {
                ::twapi::IUnknown_Release $container
            }
        }
    }

    method -unbind {sinkid} {
        my variable   _proxy   _sinks    _connection_pts

        if {[info exists _connection_pts($sinkid)]} {
            ::twapi::IConnectionPoint_Unadvise $_connection_pts($sinkid) $sinkid
            unset _connection_pts($sinkid)
        }

        if {[info exists _sinks($sinkid)]} {
            ::twapi::IUnknown_Release $_sinks($sinkid)
            unset _sinks($sinkid)
        }
        return
    }

    method unknown {name args} {
        # Try to figure out whether it is a property or method

        # We have to figure out if it is a property get, property put
        # or a method. We make a guess based on number of parameters.
        # We specify an order to try based on this. The invoke will try
        # all invocations in that order.
        # TBD - what about propputref ?
        set nargs [llength $args]
        if {$nargs == 0} {
            # No arguments, cannot be propput. Try propget and method
            set invkinds [list 2 1]
        } elseif {$nargs == 1} {
            # One argument, likely propput, method, propget
            set invkinds [list 4 1 2]
        } else {
            # Multiple arguments, likely method, propput, propget
            set invkinds [list 1 4 2]
        }

        # Invoke the function. We do a uplevel instead of eval
        # here so variables if any are in caller's context
        return [my _invoke $name $invkinds $args]
    }
}
