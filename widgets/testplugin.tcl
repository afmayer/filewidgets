variable selectedFiles

proc FWGetParameters {} {
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
