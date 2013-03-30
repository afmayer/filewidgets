variable activeDir
variable repositoryDir

proc FWGetParameters {} {
    return [list]
}

proc FWSetFiles {actDir inactDir actCaret inactCaret actSel inactSel} {
    variable activeDir $actDir
    return
}

proc FWGetWidgetHeightList {} {
    variable activeDir
    variable repositoryDir

    set widgetActive 0
    set pathComponents [file split $activeDir]
    for {set i [expr {[llength $pathComponents] - 1}]} {$i >= 0} {incr i -1} {
        set probedDir [file join {*}[lrange $pathComponents 0 $i] ".git"]
        if [file isdirectory $probedDir] {
            set widgetActive 1
            set repositoryDir $probedDir
            break
        }
    }

    if {$widgetActive != 0} {
        return [list 80]
    } else {
        return [list]
    }
}
