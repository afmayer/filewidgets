package require Tk

# ******** GUI FUNCTIONS ********

proc guiCreate {} {
    wm title . "File Action"
    raise .
    bind . <Key-F1> [list console show]
    bind . <Key-Escape> guiCancelBtnPressed
    # grid propagate . 0
    . configure -height 500
    . configure -width 400
    
    # widgets
    ttk::frame .f
    
    ttk::frame .f.a -padding 2
    
    ttk::frame .f.a.f1 -borderwidth 3 -relief solid
    ttk::label .f.a.f1.testlabel -text "TEST1"
    
    ttk::frame .f.a.f2 -borderwidth 3 -relief solid
    ttk::label .f.a.f2.testlabel -text "TEST2"
    
    ttk::button .f.btn1 -text OK
    ttk::button .f.btn2 -text Cancel -command guiCancelBtnPressed
    
    # layout
    grid .f -column 0 -row 0 -sticky nwes
    grid rowconfigure . .f -weight 1
    grid columnconfigure . .f -weight 1
    
    grid .f.a -column 0 -row 0 -columnspan 2 -rowspan 1 -sticky nwes
    grid rowconfigure .f .f.a -weight 1
    grid columnconfigure .f .f.a -weight 1
    
    grid .f.a.f1
    grid .f.a.f1.testlabel
    grid .f.a.f2
    grid .f.a.f2.testlabel
    
    grid .f.btn1 -column 0 -row 3 -sticky s
    grid .f.btn2 -column 1 -row 3 -sticky s
}

proc guiCancelBtnPressed {} {
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
guiCreate
