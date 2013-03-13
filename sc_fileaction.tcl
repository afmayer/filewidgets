package require Tk

# ******** GUI FUNCTIONS ********
namespace eval gui {}
proc gui::Create {root} {
    set base [expr {($root eq ".") ? "" : $root}]

    if {$root eq "."} {
        wm title . "File Action"
        raise .
        bind . ? [list console show]
        bind . <Key-F1> [list console show]
        bind . <Key-Escape> [namespace code [list CancelBtnPressed]]
    }

    # widgets
    frame $base.f
    
    frame $base.f.a
    
    frame $base.f.a.f1 \
        -borderwidth 3 \
        -relief solid
    label $base.f.a.f1.testlabel \
        -text "TEST1"
    
    frame $base.f.a.f2 -borderwidth 3 \
        -relief solid
    label $base.f.a.f2.testlabel \
        -text "TEST2"
    
    button $base.f.btn1 \
        -text OK
    button $base.f.btn2 \
        -text Cancel \
        -command [namespace code [list CancelBtnPressed]]
    
    # layout
    grid $base.f \
        -column 0 \
        -row 0 \
        -sticky nwes
    grid rowconfigure $root $base.f \
        -weight 1
    grid columnconfigure $root $base.f \
        -weight 1
    
    grid $base.f.a \
        -column 0 \
        -row 0 \
        -columnspan 2 \
        -rowspan 1 \
        -sticky nwes
    grid rowconfigure $base.f $base.f.a \
        -weight 1
    grid columnconfigure $base.f $base.f.a \
        -weight 1
    
    grid $base.f.a.f1
    grid $base.f.a.f1.testlabel
    grid $base.f.a.f2
    grid $base.f.a.f2.testlabel
    
    grid $base.f.btn1 \
        -column 0 \
        -row 3 \
        -sticky s
    grid $base.f.btn2 \
        -column 1 \
        -row 3 \
        -sticky s
}

proc gui::CancelBtnPressed {} {
    exit
}

# ******** NON-GUI FUNCTIONS ********

proc collectCommandLineArguments {pActDir pInactDir pActCaret pInactCaret \
                    pActSelectionList pInactSelectionList} {
    global argv
    upvar 1 $pActDir actDir $pInactDir inactDir $pActSelectionList \
                    actSelectionList $pInactSelectionList inactSelectionList \
                    $pActCaret actCaret $pInactCaret inactCaret
    set argumentState 0
    set actDir ""
    set inactDir ""
    set actCaret ""
    set inactCaret ""
    set as [list]
    set is [list]
    foreach arg $argv {
        # special argument words to split different argument types
        # sent from SpeedCommander
        if {$arg eq "*AD"} {
            set argumentState 1
            continue
        } elseif {$arg eq "*ID"} {
            set argumentState 2
            continue
        } elseif {$arg eq "*AC"} {
            set argumentState 3
            continue
        } elseif {$arg eq "*IC"} {
            set argumentState 4
            continue
        } elseif {$arg eq "*AS"} {
            set argumentState 5
            continue
        } elseif {$arg eq "*IS"} {
            set argumentState 6
            continue
        # when no files apply SpeedCommander does not repace the variables
        # so we need to remove the placeholders
        } elseif {$arg eq "\$(ActDir)"} {
            set actDir ""
            continue
        } elseif {$arg eq "\$(InactDir)"} {
            set inactDir ""
            continue
        } elseif {$arg eq "\$(ActCaret)"} {
            set actCaret ""
            continue
        } elseif {$arg eq "\$(InactCaret)"} {
            set inactCaret ""
            continue
        } elseif {$arg eq "\$(ActSel)"} {
            set as [list]
            continue
        } elseif {$arg eq "\$(InactSel)"} {
            set is [list]
            continue
        }
        
        # append value to corresponding list or set value
        if {$argumentState == 1} {
            set actDir $arg
        } elseif {$argumentState == 2} {
            set inactDir $arg
        } elseif {$argumentState == 3} {
            set actCaret $arg
        } elseif {$argumentState == 4} {
            set inactCaret $arg
        } elseif {$argumentState == 5} {
            lappend as $arg
        } elseif {$argumentState == 6} {
            lappend is $arg
        }
    }
    
    set actSelectionList $as
    set inactSelectionList $is
}

# entry point
collectCommandLineArguments actDir inactDir actCaret inactCaret \
                actSel inactSel
gui::Create .
