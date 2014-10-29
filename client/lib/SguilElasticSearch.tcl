# Preprocess query requests from the right click menu and then launch the GUI
# 
# type of query (Sguil_httplog, Sguil_flow, etc)
# default conditions (src_ip, dst_ip, both)
# Time manipulation (hours ago)
proc ESQueryRequest { type term { start { 1 hour ago } } { end { now } } } { 

    global CUR_SEL_PANE

    set i [$CUR_SEL_PANE(name) curselection]
    set src_ip [$CUR_SEL_PANE(name) getcells $i,srcip]
    set dst_ip [$CUR_SEL_PANE(name) getcells $i,dstip]

    set q ""

    if { $term == "srcip" } { 

        set q "src_ip:$src_ip"

    } elseif { $term == "dstip" } { 

        set q "dst_ip:$dst_ip"

    } else {

        set q "src_ip:$src_ip AND dst_ip:$dst_ip"

    }
    
    ESQueryBuilder $type $q $start $end

}

proc ESQueryBuilder { type {rawquery {}} {start {}} {end {}} } {

    global ES_PROFILE ES_QUERY ES_RETURN_FLAG

    if { ![info exists ES_QUERY(size)] } { set ES_QUERY(size) 500 }

    # Pointer location
    set pointerxy [winfo pointerxy .]

    set esb .esBuilder
    # If the bldr exists, bounce it to the foreground
    if { [winfo exists $esb] } {

        wm withdraw $esb
        wm deiconify $esb

    } else {

        # Create the win
        toplevel $esb
        wm title $esb "ElasticSearch Query Builder"
 
        # Place the window in a good spot on the screen
        set h [winfo height .]
        set w [winfo width .] 
        set y [expr (($h / 2) - 200)]
        if { $y < 0 } { set y 0 }
        set x [expr (($w / 2) - 300)] 
        if { $x < 0 } { set x 0 }
        wm geometry $esb +$x+$y
        
        set mFrame [frame $esb.mainFrame -background #dcdcdc -borderwidth 1]
        set qFrame [frame $mFrame.queryFrame]

        set ES_QUERY(type) [iwidgets::optionmenu $qFrame.type \
            -labeltext "_type: " \
            -command { UpdateESQuery } \
        ]

        # Populate our optionss: Sguil_httplog, Sguil_flow
        foreach t { Sguil_httplog Sguil_flow } { $ES_QUERY(type) insert end $t }
        $ES_QUERY(type) select $type

        set hEntry [iwidgets::entryfield $qFrame.host \
            -labeltext "ES Host: " \
            -width 10 \
            -textvariable ES_PROFILE(host) \
        ]
        #$sEntry delete 0 end
        #$sEntry insert 0 $start

        set sEntry [iwidgets::entryfield $qFrame.start \
            -labeltext "Start: " \
            -width 10 \
            -command { UpdateESQuery } \
            -focuscommand { UpdateESQuery } \
            -textvariable ES_QUERY(start) \
        ]
        $sEntry delete 0 end
        $sEntry insert 0 $start

        set eEntry [iwidgets::entryfield $qFrame.end \
            -labeltext "End: " \
            -width 10 \
            -command { UpdateESQuery } \
            -focuscommand { UpdateESQuery } \
            -textvariable ES_QUERY(end) \
        ]
        $eEntry delete 0 end
        $eEntry insert 0 $end

        set ES_QUERY(query) [iwidgets::scrolledtext $qFrame.query \
            -labeltext "Query: " -labelpos w \
            -vscrollmode dynamic \
            -hscrollmode none \
            -wrap word \
            -relief sunken \
            -visibleitems 60x4 \
            -sbwidth 10 \
            -borderwidth 1 \
        ]
        $ES_QUERY(query) insert 0.0 $rawquery
        bind [$ES_QUERY(query) component text] <KeyRelease> { UpdateESQuery }

        set lEntry [iwidgets::entryfield $qFrame.limit \
            -labeltext "Limit: " \
            -width 5 \
            -command { UpdateESQuery } \
            -focuscommand { UpdateESQuery } \
            -textvariable ES_QUERY(size) \
        ]
        if { ![info exists ES_QUERY(size)] } { $lEntry insert 0 500 }

        iwidgets::Labeledwidget::alignlabels $hEntry $sEntry $eEntry $ES_QUERY(query) $lEntry

        pack $ES_QUERY(type) -side top -expand false
        pack $hEntry $sEntry $eEntry $lEntry -side top -fill x -expand false
        pack $ES_QUERY(query) -side top -fill both -expand true

        set ES_QUERY(json) [iwidgets::scrolledtext $mFrame.searchText \
            -labeltext "JSON Search" \
            -wrap word \
            -vscrollmode dynamic \
            -hscrollmode none \
            -visibleitems 60x20 \
            -relief groove \
            -textbackground lightblue \
            -textfont ourFixedFont \
        ]

        set bFrame [frame $mFrame.buttons]

        set sButton [button $bFrame.submit \
            -text "Submit" \
            -command "set ES_RETURN_FLAG 1" \
        ]

        set cButton [button $bFrame.cancel \
            -text "Cancel" \
            -command "set ES_RETURN_FLAG 0" \
        ]

        pack $sButton $cButton -side left -expand true

        pack $qFrame -side top -fill both -expand true
        pack $ES_QUERY(json) -side top -fill both -expand true
        pack $bFrame -side top -expand false
        
        pack $mFrame -side top -fill both -expand true

        UpdateESQuery

        tkwait variable ES_RETURN_FLAG

        if { $ES_RETURN_FLAG } {

            UpdateESQuery
            set type [$ES_QUERY(type) get]
            set query [$ES_QUERY(json) get 0.0 end]
            set rawquery [$ES_QUERY(query) get 0.0 end]

            PrepESQuery $type $query $rawquery $ES_QUERY(start) $ES_QUERY(end)

        }

        destroy $esb

    }

}

proc UpdateESQuery {} {

    global ES_PROFILE ES_QUERY

    #json::write indented 0

    if { $ES_QUERY(start) != "now" } { 

        set stime "[clock scan $ES_QUERY(start)]000"

    } else {

        set stime [json::write string now]

    }

    if  { $ES_QUERY(end) != "now" } { 

       set etime "[clock scan $ES_QUERY(start)]000"

    } else {

        set etime [json::write string now] 

    }

    # The filter part
    set ts [json::write object @timestamp [json::write object from $stime to $etime]]
    set range [json::write object range $ts]

    set type [$ES_QUERY(type) get]

    # Grab the query from the entry
    if { [info exists ES_QUERY(query)] } {

        regsub -all {\n} [$ES_QUERY(query) get 0.0 end] {} query
        set query "_type:$type AND ($query)"

    } else {

        set query "_type:$type"

    }

   

    # The query part
    set q [json::write object query_string [json::write object query [json::write string $query]]]

    set filtered [json::write object filtered [json::write object query $q filter $range]]

    # The sorting
    set sort [json::write array [json::write object @timestamp [json::write object order [json::write string desc]]]]

    set fq [json::write object query $filtered size $ES_QUERY(size) sort $sort]

    $ES_QUERY(json) clear
    $ES_QUERY(json) insert 0.0  $fq

}


proc PrepESQuery { type query rawquery start end } {

    global ES_PROFILE ES_QUERY_NUMBER DEBUG eventTabs

    incr ES_QUERY_NUMBER

    # Add the tab to the main window
    $eventTabs add -label "ES Query $ES_QUERY_NUMBER"
    set currentTab [$eventTabs childsite end]
    set tabIndex [$eventTabs index end]

    # Create a container frame
    set queryFrame [frame $currentTab.esquery_${ES_QUERY_NUMBER} -background black -borderwidth 1]
    $eventTabs select end

    # Build the multi lists
    CreateESLists $queryFrame

    # Build the actions (close, export, re-submit, and edit)

    # Frame for the actions
    set aFrame [frame $currentTab.aFrame]

    # Close and export on the left
    set lbuttonsFrame [frame $aFrame.lbuttons]
    set closeButton [button $lbuttonsFrame.close -text "Close" \
            -relief raised -borderwidth 2 -pady 0 \
            -command "DeleteTab $eventTabs $currentTab"]
    set exportButton [button $lbuttonsFrame.export -text "Export " \
            -relief raised -borderwidth 2 -pady 0 \
            -command "ExportResults $queryFrame sguil_http"]
    pack $closeButton $exportButton -side top -fill x

    # Query text in the middle
    set queryText [scrolledtext $aFrame.text -textbackground white -visibleitems 30x3 -wrap word \
      -vscrollmode dynamic -hscrollmode none -sbwidth 10]
    $queryText insert 0.0 $query
    $queryText configure -state disabled

    # Submit and edit buttons on the right
    set rbuttonsFrame [frame $aFrame.rbuttons]
    set rsubmitButton [button $rbuttonsFrame.rsubmit -text "Submit " \
            -relief raised -borderwidth 2 -pady 0 \
            -command "[list PrepESQuery $type $query $rawquery $start $end]"]
    set editButton [button $rbuttonsFrame.edit -text "Edit " \
            -relief raised -borderwidth 2 -pady 0 \
            -command "[list ESQueryBuilder $type $rawquery $start $end]"]
    pack $rsubmitButton $editButton -side top -fill x

    # Pack them left to right
    pack $lbuttonsFrame  -side left
    pack $queryText -side left -fill both -expand true
    pack $rbuttonsFrame  -side left
    pack $aFrame -side top -fill x
    pack $queryFrame -side bottom -fill both

    # Run the query
    ESQuery $type $query $queryFrame

}

proc ESQuery { type query queryFrame } {

    global ES_PROFILE ES_QUERY_NUMBER DEBUG eventTabs

    set url "$ES_PROFILE(host)/_search?pretty"
   
    puts "q -> $query"

    puts "Making request to $url"

    if { $ES_PROFILE(auth) } { 
    
        set authcreds "Basic [base64::encode $ES_PROFILE(user):$ES_PROFILE(pass)]"
        set authhdr [list Authorization $authcreds]

        set cmd [list http::geturl $url -query $query -headers $authhdr]

    } else {

        set cmd [list http::geturl $url -query $query]

    }

    lappend cmd "-command" "QueryFinished $queryFrame $type $query"

    if { [catch { eval $cmd } tmpError] } {

        ErrorMessage $tmpError
        return 0

    } else {

        return 1

    }

}

proc QueryFinished { queryFrame type query token } {

    global ES_PROFILE

    set tablewin $queryFrame.tablelist

    puts "QueryFinished{}."
    flush stdout

    # Make sure the cnx did not timeout/etc
    if  { [http::status $token] == "ok" } {

        # Verify we had a good HTTP status code
        if { [http::ncode $token] == "200" } {

            set hits [dict get [json::json2dict [http::data $token] ] hits]
            InfoMessage "ElasticSearch total rows: [dict get $hits total]"

            foreach row [dict get $hits hits] { 

                set id [dict get $row _id]
                set _source [dict get $row _source]
                dict with _source { 

                    # message @version @timestamp type host src_ip src_port dst_ip dst_port x-fwd-for http_method http_host
                    # uri http_referrer http_user_agent http_accept_language http_status vendor

                    # Convert the time
                    regexp {^(\d+-\d+-\d+)T(\d+\:\d+\:\d+)} ${@timestamp} match date time
                    set timestamp "$date $time"

                    set rList [list \
                      $host \
                      $net_name \
                      $id \
                      $timestamp \
                      $src_ip \
                      $src_port \
                      $dst_ip \
                      $dst_port \
                      $http_host \
                      $http_method \
                      $uri \
                      $http_status \
                      $http_referrer \
                      $http_user_agent \
                      $http_accept_language \
                   ]

                    $tablewin insert end $rList

                }

            }

            puts "Query finished"

        } else {

            # Not a 200. Check if auth is required
            if { [http::ncode $token] == "401" } {

                puts "Authentication Required"
                # Rerun the query if auth is provided
                if [ESBasicAuth] { 

                    ESQuery $type [list $query] $queryFrame 

                } 

            } else {

                set errorMsg [http::code $token]
                puts "Error: $errorMsg"

            }

        }

        http::cleanup $token

    } else {

        # An error code was returned
        set httpError [http::error $token]
        puts "error: $httpError"
        http::cleanup $token

        #return -code error $httpError

    }
  

} 

proc ESBasicAuth {} {

    global SGUILLIB ES_PROFILE

    set ES_PROFILE(auth) false

    set esAuth [toplevel .auth]
    wm title $esAuth "Authentication Required"
    set w [winfo width .]
    set h [winfo height .]
    set y [expr ( ( $h / 2 ) - 150)]
    if { $y < 0 } { set y 0 }
    set x [expr ( ( $w / 2 ) - 250)]
    if { $x < 0 } { set x 0 }
    wm geometry $esAuth +$x+$y

    set hl [ label $esAuth.label -text "$ES_PROFILE(host)" ]

    set uEntry [ entryfield $esAuth.username \
        -labeltext "Username:" \
        -textvariable ES_PROFILE(user)
    ]

    set pEntry [ entryfield $esAuth.passwd \
        -labeltext "Password:" \
        -show * \
        -textvariable ES_PROFILE(pass)
    ]

    iwidgets::Labeledwidget::alignlabels $uEntry $pEntry

    set bb [buttonbox $esAuth.bb]
    $bb add ok -text "Ok" -command "set ES_PROFILE(auth) true; destroy $esAuth"
    $bb add cancel -text "Cancel" -command "set ES_PROFILE(auth) false; destroy $esAuth"

    if { [file exists $SGUILLIB/images/elasticsearch-logo.gif] } {

        set esLogo [image create photo -file $SGUILLIB/images/elasticsearch-logo.gif]
        set lLabel [label $esAuth.logo -image $esLogo]
        #if { [info exists lLabel] } { pack $lLabel -side top -fill both -expand true }
        pack $lLabel -side top -fill both -expand true

    }

    pack $hl $uEntry $pEntry $bb -side top -fill both -expand true

    bind [$pEntry component entry] <Return> { set ES_PROFILE(auth) true; destroy .auth }
    focus -force $uEntry

    tkwait window $esAuth

    # This updates the users sguilrc
    SaveNewFonts

    return $ES_PROFILE(auth)

}
 
proc CreateESLists { baseFrame } { 

    global SCROLL_HOME MiddleButton RightButton

    #set SCROLL_HOME($baseFrame) 0

    set currentPane $baseFrame.tablelist
    set currentYSB $baseFrame.ysb
    set currentHSB $baseFrame.hsb

    #puts "${@timestamp} $src_ip $src_port $dst_ip $dst_port $http_host $http_method $uri $http_referrer \
    # $http_user_agent $http_accept_language $http_status $vendor"

    # Build the table
    tablelist::tablelist $currentPane \
        -columns {15 "Sensor"             left
                  15 "Net Name"           left
                  25 "_id"                left
                  18 "Timestamp"          center
                  16 "Src IP"             left
                  6  "SPort"              left
                  16 "Dst IP"             left
                  6  "DPort"              left
                  16 "Host"               left
                  6  "Method"             left
                  20 "URI"                left
                  6  "Status"             left
                  20 "Referer"            left
                  20 "User-Agent"         left
                  20 "Accept-Language"    left
         } \
         -selectmode browse \
         -width 40 \
         -yscrollcommand [list $currentYSB set] \
         -xscrollcommand [list $currentHSB set]

    $currentPane columnconfigure 0 -name sensor -resizable 1 -stretchable 0 -sortmode dictionary
    $currentPane columnconfigure 1 -name net_name -resizable 1 -stretchable 0 -sortmode dictionary
    $currentPane columnconfigure 2 -name alertID -resizable 1 -stretchable 0 -sortmode real
    $currentPane columnconfigure 3 -name date -resizable 1 -stretchable 0 -sortmode dictionary
    $currentPane columnconfigure 4 -name srcip -resizable 1 -stretchable 0 -sortmode dictionary
    $currentPane columnconfigure 5 -name srcport -resizable 1 -stretchable 0 -sortmode integer
    $currentPane columnconfigure 6 -name dstip -resizable 1 -stretchable 0 -sortmode dictionary
    $currentPane columnconfigure 7 -name dstport -resizable 1 -stretchable 0 -sortmode integer
    $currentPane columnconfigure 9 -name method -resizable 1 -stretchable 1 -sortmode dictionary
    $currentPane columnconfigure 9 -name host -resizable 1 -stretchable 1 -sortmode dictionary
    $currentPane columnconfigure 10 -name uri -resizable 1 -stretchable 1 -sortmode dictionary
    $currentPane columnconfigure 11 -name status -resizable 1 -stretchable 1 -sortmode dictionary
    $currentPane columnconfigure 12 -name referer -resizable 1 -stretchable 1 -sortmode dictionary
    $currentPane columnconfigure 13 -name ua -resizable 1 -stretchable 1 -sortmode dictionary
    $currentPane columnconfigure 14 -name lang -resizable 1 -stretchable 1 -sortmode dictionary

    scrollbar $currentYSB -orient vertical -command [list $currentPane yview]
    scrollbar $currentHSB -orient horizontal -command [list $currentPane xview]

    pack $currentYSB -side right -fill y
    pack $currentPane -side top -fill both -expand true
    pack $currentHSB -side bottom -fill x
    pack $baseFrame -expand true -fill both

    set bindWin [$currentPane bodytag]

    # Grab button press/motion and make sure we aren't busy
    bind $bindWin <ButtonPress-1> { global BUSY; if { $BUSY } { bell; break } }
    bind $bindWin <Button1-Motion> { global BUSY; if { $BUSY } { break } }

    # Left button was released on a list.
    bind $bindWin <ButtonRelease-1> {

        global BUSY

        if { $BUSY } { bell; break }

        foreach {tablelist::W tablelist::x tablelist::y} \
            [tablelist::convEventFields %W %x %y] {}

        SelectSguil_HttpPane $tablelist::W SGUIL_HTTP SGUIL_HTTP

    }

    # Right mouse button
    bind $bindWin <$RightButton> {

        foreach {tablelist::W tablelist::x tablelist::y} \
            [tablelist::convEventFields %W %x %y] {}

        ManualSelectRow $tablelist::W $tablelist::x $tablelist::y
        SelectSguil_HttpPane $tablelist::W SGUIL_HTTP SGUIL_HTTP
        LaunchRightClickMenu $tablelist::W $tablelist::x $tablelist::y %W

    }

}

proc SelectSguil_HttpPane { win type format } {

    global CUR_SEL_PANE CUR_SEL_EVENT ACTIVE_EVENT BUSY MULTI_SELECT DISPLAYEDDETAIL
    global portscanDataFrame packetDataFrame padsFrame sguil_httpFrame

    set CUR_SEL_PANE(name) $win
    set CUR_SEL_PANE(type) $type
    set CUR_SEL_PANE(format) $format

    set ACTIVE_EVENT 1

    # ES panes are single select only
    set MULTI_SELECT 0
    set selectedIndex [$win curselection]

    # Nothing selected
    if { $selectedIndex == "" } { return }

    # Get the eventID
    set eventID [$CUR_SEL_PANE(name) getcells $selectedIndex,alertID]

    # If we clicked on an already active event, do nothing.
    if { [info exists CUR_SEL_EVENT] && $CUR_SEL_EVENT == $eventID } {
        return
    }

    set CUR_SEL_EVENT $eventID

    if { $DISPLAYEDDETAIL != $sguil_httpFrame } {

        pack forget $DISPLAYEDDETAIL
        pack $sguil_httpFrame -fill both -expand true
        set DISPLAYEDDETAIL $sguil_httpFrame

    }

    DisplaySguil_HttpDetail
    ResolveHosts
    GetWhoisData

}

proc DisplaySguil_HttpDetail {} {

    global sguil_httpFrame DISPLAY_SGUIL_HTTP ACTIVE_EVENT MULTI_SELECT CUR_SEL_PANE sguil_httpDetailTable

    # Clear the current data
    $sguil_httpDetailTable delete 0 end

    if { $ACTIVE_EVENT && $DISPLAY_SGUIL_HTTP && !$MULTI_SELECT } {

        set selectedIndex [$CUR_SEL_PANE(name) curselection]
        set data [$CUR_SEL_PANE(name) get $selectedIndex]

        set i 0

        foreach title [list \
          host \
          net_name \
          _id \
          @timestamp \
          src_ip \
          src_port \
          dst_ip \
          dst_port \
          http_host \
          http_method \
          uri \
          http_status \
          http_referrer \
          http_user_agent \
          http_accept_language \
        ] {

            $sguil_httpDetailTable insert end [list $title [lindex $data $i]]
            incr i

        }

    }
   
}
