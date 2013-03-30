variable activeDir
variable repositoryDir
variable widgetFrame

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

proc FWAnnounceWidgetFrames {widgetFrames} {
    variable widgetFrame [lindex $widgetFrames 0]
    variable path

    image create photo gitlogo -data {
        R0lGODlhMAAwAPcAAAQCBFRubExKTES6TPQiFNQ2LOwuHFzGZNxSTHR2dOQmJPw+NDTGTFxydHRa
        XNQ+NNQyLGRqbDzCROwqHOQ2LGRiZNQ6LDy+TOwmHOwuJOQqLGxeXOQuLGxubFxubPQmFNw2LFzO
        ZHx6fOwmJPRCNDTKTNwyLGxqbETCTPQqHGRmZNw6LES+TOQyJHReXAUAAKAAALcAACIAAAUAAFD/
        EAH/fm8AjwABdmmg8SrJfQh3jwAAdgCYVAADFm8AAQAA+Ti8D6jnAHQBAAABAAC0GADmAAAYAAAA
        AAVALwCoAAB0AAUAAFDMIAH76m8YGAAAALDV4qtx63Q8GAB3AFgzAFczAHjGJQACALj+AAj/AHT/
        AAD/ACiaMAA46QA4GAB3AACSaAA0Fm84vgB3dZgAVAMAFgAAAQAA+TgxAKjOAHQaAAB2AJQAxOcB
        0BgAGgAAdr4A2zgAXDgAbncAezjgAAHnAG8YAAAAAJo/ADhiADg4AHd3APdE0BxiYOk4cnV3AACD
        AAAcYADpcgB1AAAAqAAA6G8AGAAAAEAAL6gBAHQAAAAAAAAxBADO6QAaGAB2AAC4IwDnQQAYIgAA
        dgAxxwDOZAAabAB2DXzM/gH7/28Y/wAA/wDVxABx0AA8GgB3dlDbAQE10W/GGgACdqD+0Mn/YHf/
        cgD/AFDwSAHn0G8YGQAAdiCAG6EWXSEYbgV2ewACAAAAAG8AAAAAAFAAAAEBAG8AAAAAAFsIAADo
        AAAYAAAAAABuIADNAAAaAAB2AFA0AQEAAG8AAADAAALZ5ADp6AAYGAIAANgMAQLxAABPAgAAAHMA
        zAAA+wAAGHMAAHMwIwDpQQAYIgAAdgcCXwDOZAAabwB2Dayo/ucN/xhQ/wAA/wPoSAAY0ABQGQAA
        dnM0eAAAiAAAQnPAAHMs0ADoYAAYcgAAAHMAAAABAAAAAAAAAJIj2TTO6TgaGHd2AGkBUCoAAAgA
        AEsAAHMAPwAAXQAAbgAAeyBUUKEWACEBAAX5AKAuidxnjClpSAVmACH5BAEAAAAALAAAAAAwADAA
        Bwj/AAEIHEiwoEEWF1AkvGCwocOHEAVeQEgxosWLBheiQIix48WJF0Ki8EjyIQuFGxmWXEkwJEiV
        LCMiRHlSY82UM0NKOBBzIEiEISm6BIoy6ACePQHY3Fg0Jc6TCHcmVQrU5c+rEqwiRNqTIouvX5uK
        BAtWalKraIV+RauT69SDCzm+9Tg05FyPElJmvdtxwIALfgfwxchAAoPDDAYrXsy4YYEVBR6AKGCC
        g4YRGjJr5sBhMmQICKYWsACCtGQLKyyoXr0aMuQCoZM+9jy6wOjJtkGkXl0a9NTSrC08eGChQAsD
        E5JP+LA8+QcSolsYB9GCeosWGZZ/ILCdgPfuCxqL4h+ftEGAAAMrbHDgYD379+v5qohQoYLACvNV
        nMCvH/9+FXN18J8KAN5HoH/8EUjgXCrgV8EJBRI4IIL/zSWCfgqeIFCGCSpY4FsenpDAhwcWWF+D
        C06VIH4FPZgiAAqyOBWKMqaH4ocw9qdhUhjWuKGHBN2II0so7mdQBwoSdAKEDc54I0ZIMqlif0M+
        NOFUTDZ50ZJJ8sgffRZJ2OCOXsYI0YVM+hjTjfjRh+MGDlJZ5Zr1RXBglvtB6OKJd3no4YMdljhn
        T/ht0GAFdvY4ZpeKVSCAoX5CmOV4/MXJKHl8BQQAOw==}

    label $widgetFrame.logo -image gitlogo
    grid $widgetFrame.logo -sticky ns
    grid rowconfigure $widgetFrame $widgetFrame.logo -weight 1
}
