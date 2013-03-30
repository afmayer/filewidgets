package require Tk

# ******** GUI FUNCTIONS ********
namespace eval gui {}
proc gui::Create {root} {
    global tcl_platform
    variable base [expr {($root eq ".") ? "" : $root}]
    variable fontSmall
    variable fontMedium
    variable fontLarge
    variable widgetWidth 500

    # choose fonts dependent on platform
    if {$tcl_platform(platform) eq "windows"} {
        set fontSmall "Calibri 8"
        set fontMedium "Calibri 12"
        set fontLarge "Calibri 16"
    } else {
        set fontSmall "Helvetica 8"
        set fontMedium "Helvetica 12"
        set fontLarge "Helvetica 16"
    }

    if {$root eq "."} {
        wm title . "File Widgets"
        image create photo mainiconimage -width 16 -height 16
        mainiconimage put #33CC33 -to  4 4 12 6
        mainiconimage put #3333CC -to  4 7 12 9
        mainiconimage put #CC3333 -to  4 10 12 12
        wm iconphoto . -default mainiconimage
        wm resizable . 0 0
        raise .
        bind . <Key-F1> [list console show]
        bind . <Key-Escape> [namespace code [list EscapeKeyPressed]]
    }

    # images
    image create photo configbtnimage -data {
        R0lGODlhIAAgAOZgACAgIFNTU1dXVxsbG29vb1xcXB4eHh0dHSEhIfT09KCgoGBgYDMzM5ubm2xs
        bBwcHEtLS09PT3h4ePDw8Orq6vLy8nZ2drKyspeXl2FhYdPT0/z8/GRkZKenp5aWlvPz8zQ0NPv7
        +/r6+s7OzszMzLa2tp6enmJiYnl5eUZGRmpqaklJSZGRkaGhoaioqNTU1PHx8XV1dV1dXR8fH5iY
        mEJCQqOjo2hoaMbGxkFBQYODg2ZmZiIiItnZ2ZqamoGBgenp6dXV1Y2NjWdnZ9fX1+Hh4VRUVOPj
        439/f0xMTCcnJ3d3d4aGhkpKSubm5sHBwS4uLuzs7DAwMNLS0rq6urGxsb+/v1BQUBoaGrOzs9vb
        2y8vL4SEhENDQ6ysrG1tbf///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5
        BAEAAGAALAAAAAAgACAAAAflgGCCg4SFhoeIiYqLjI2Oj5CRkpOKLxZMGEWUhyMEnlwim4UTFxgO
        Dlmihz43Dk6bVjtfhBQcHFSbOAsLCYNTCxlAm0QFBR0bYBMWBQSiCUMCAjE0J9ECNqIfHkYB3d4B
        LaoaBBIlHVcR6SaqhBdJEPAN7IMuIAz3QvOCCjwI/j8kdAh4okoBAgAIEwIgEEWUghkGIq5IERGK
        BlEqDmwJAmZDgwMHWIjKcQAJoRoHlmzq8eCBF0IFHmTYVEHKgC4hBsGg0GtTlQEDZDTQog9MAaAD
        JBQ90kQJFhRFB1XoGbWqVUiBAAA7}

    # widgets
    frame $base.tf
    entry $base.tf.searchbox \
        -font $fontMedium
    button $base.tf.configbtn \
        -image configbtnimage \
        -relief flat \
        -overrelief solid \
        -borderwidth 1

    frame $base.f

    # layout
    grid $base.tf \
        -column 0 \
        -row 0 \
        -sticky e
    grid $base.tf.searchbox \
        -column 0 \
        -row 0 \
        -padx 2 \
        -pady 2
    grid $base.tf.configbtn \
        -column 1 \
        -row 0 \
        -padx 2 \
        -pady 2
    grid $base.f \
        -column 0 \
        -row 1 \
        -sticky nwes

    # layout resizing
    grid rowconfigure $root $base.f \
        -weight 1
    grid columnconfigure $root $base.f \
        -weight 1

    # focus to search box
    focus .tf.searchbox

    return
}

proc gui::DrawEmptyWidgets {listOfHeights} {
    variable base
    variable widgetWidth

    if {[info exists base] == 0} {
        error "GUI does not exist"
    }

    set index 0
    set returnedFrameList [list]

    foreach w [winfo children $base.f] {
        destroy $w
    }

    foreach height $listOfHeights {
        frame ${base}.f.f${index} \
            -borderwidth 1 \
            -relief solid \
            -width $widgetWidth \
            -height $height

        grid ${base}.f.f${index}

        if {$index < [llength $listOfHeights] - 1} {
            frame ${base}.f.s${index} \
                -height 5
            grid ${base}.f.s${index}
        }

        grid propagate ${base}.f.f${index} 0
        grid propagate ${base}.f.f${index} 0

        lappend returnedFrameList ${base}.f.f${index}
        incr index
    }

    return $returnedFrameList
}

proc gui::DrawInfoText {text} {
    variable base
    variable fontLarge
    variable widgetWidth

    foreach w [winfo children $base.f] {
        destroy $w
    }

    frame $base.f.f0 \
        -width $widgetWidth \
        -height 100
    label $base.f.f0.l \
        -text $text \
        -font [list {*}$fontLarge italic]
    grid $base.f.f0
    grid $base.f.f0.l \
        -sticky nwes
    grid propagate $base.f.f0 0
    grid rowconfigure $base.f.f0 $base.f.f0.l \
        -weight 1
    grid columnconfigure $base.f.f0 $base.f.f0.l \
        -weight 1

    return
}

proc gui::EscapeKeyPressed {} {
    exit
}

# ******** NON-GUI FUNCTIONS ********

proc CollectCommandLineArguments {pActDir pInactDir pActCaret pInactCaret \
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
            set actDir [file normalize $arg]
        } elseif {$argumentState == 2} {
            set inactDir [file normalize $arg]
        } elseif {$argumentState == 3} {
            set actCaret [file normalize $arg]
        } elseif {$argumentState == 4} {
            set inactCaret [file normalize $arg]
        } elseif {$argumentState == 5} {
            lappend as [file normalize $arg]
        } elseif {$argumentState == 6} {
            lappend is [file normalize $arg]
        }
    }

    set actSelectionList $as
    set inactSelectionList $is
}

proc FileWidgetsMain {} {
    global brokenPluginNames pluginNames pluginParams
    set brokenPluginNames [list]
    set pluginNames [list]
    array set pluginParams {}

    CollectCommandLineArguments actDir inactDir actCaret inactCaret \
                actSel inactSel

    # create the GUI
    gui::Create .

    # source all .tcl files in the "widgets" subdirectory
    foreach sourcefile [glob -directory [file join [file dirname [info script]] widgets] -nocomplain -tails *.tcl] {
        if [
            catch {
                # create a namespace for the plugin and source it from inside that namespace
                namespace eval $sourcefile {
                    variable path [file join [file dirname [info script]] widgets [namespace tail [namespace current]]]
                    source $path
                }

                # ask for parameter list via FWGetParameters
                foreach {attribute value} [${sourcefile}::FWGetParameters] {
                    array set pluginParams [list "$sourcefile/$attribute" $value]
                }
            }
        ] {
            # error in plugin
            namespace delete $sourcefile
            lappend brokenPluginNames $sourcefile
        } else {
            # plugin seems OK
            lappend pluginNames $sourcefile
        }
    }

    # get widget height list from each plugin
    set widgetsPerPlugin [list]
    set emptyWidgetHeights [list]
    foreach plugin $pluginNames {
        catch {
            # announce selected files
            ${plugin}::FWSetFiles $actDir $inactDir $actCaret $inactCaret \
                $actSel $inactSel
        }
        set widgetHeightList [list]
        catch {
            set widgetHeightList [${plugin}::FWGetWidgetHeightList]
        }
        if {[llength $widgetHeightList] != 0} {
            lappend widgetsPerPlugin $plugin
            lappend widgetsPerPlugin [llength $widgetHeightList]
        }
        foreach widgetHeight $widgetHeightList {
            lappend emptyWidgetHeights $widgetHeight
        }
    }

    # draw empty widgets
    if {[llength $emptyWidgetHeights] != 0} {
        set createdWidgetFrames [gui::DrawEmptyWidgets $emptyWidgetHeights]
    } else {
        gui::DrawInfoText "no active widgets"
        return
    }

    # announce created widget frames to plugins
    set lowRange 0
    tk_messageBox -title {$widgetsPerPlugin} -message $widgetsPerPlugin
    foreach {pluginName numOfWidgets} $widgetsPerPlugin {
        set highRange [expr {$lowRange + $numOfWidgets - 1}]
        set widgetHeightList [lrange $createdWidgetFrames $lowRange $highRange]
        set lowRange [expr {$highRange + 1}]
        catch {
            ${pluginName}::FWAnnounceWidgetFrames $widgetHeightList
        }
    }
}

# entry point
FileWidgetsMain
