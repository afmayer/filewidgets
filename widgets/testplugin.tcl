variable selectedFiles

proc FWInit {} {
    return [list \
        test1 val1 \
        test2 val2 \
    ]
}

proc FWSetFiles {actDir inactDir actCaret inactCaret actSel inactSel} {
    variable selectedFiles $actSel
}

proc FWGetWidgetHeightList {} {
    variable selectedFiles
    set returnedHeightList [list]
    set activateWidget 0

    # activate test widget when any of the selected files has a '.txt' extension
    foreach file $selectedFiles {
        if {[file isfile $file]} {
            if {[string tolower [file extension $file]] eq ".txt"} {
                set activateWidget 1
            }
        }
    }

    if {$activateWidget != 0} {
        lappend returnedHeightList 100
    }
    return $returnedHeightList
}

proc FWAnnounceWidgetFrames {widgetFrames} {
    variable widgetFrame [lindex $widgetFrames 0]
    label $widgetFrame.l1 -text "testplugin" -font $filewidgets::gui::fontLarge
    grid $widgetFrame.l1 -row 0 -column 0
}

proc FWGetDynamicSearchResults {searchTerm} {
    set returnedList [list]
    foreach s [split $searchTerm " "] {
        if {$s ne ""} {
            lappend returnedList "test-search-result $s"
            lappend returnedList ""
            lappend returnedList "Oh! I found something with $s!"
            lappend returnedList "testplugin"
        }
    }
    return $returnedList
}

proc FWGetStaticSearchResults {} {
    set returnedList [list]
    return $returnedList
}

proc FWExecuteSearchResultLine {commandString} {
    puts "testplugin FWExecuteSearchResultLine \"$commandString\""
}
