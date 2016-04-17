declare option exist:serialize "method=xhtml media-type=text/html";

declare function local:epoch-seconds-to-dateTime($v) as xs:dateTime{  
    xs:dateTime("1970-01-01T00:00:00-00:00")
  + xs:dayTimeDuration(concat("PT", $v, "S"))
};

declare function local:minutes_to_days_hrs_min($mins) {
    if ($mins < 60) 
    then concat($mins, " mins")
    else let $hours := $mins div 60
         let $full_hours := floor($hours)
         let $full_mins := $mins - $full_hours * 60
         return
            if ($full_hours >24) 
            then 
                let $days := $full_hours div 24
                let $full_days := floor($days)
                let $rem_hours := $full_hours - $full_days * 24
                return concat($full_days," days,",$rem_hours," hrs,",$full_mins," mins")
            else 
                concat($full_hours," hrs, ",$full_mins, " mins")
};
   <html>
    <head>
          <script src="jscripts/sorttable.js"></script>
      <style>
      tr.alternate:nth-child(even) {{background: lightgreen}}
      a.external {{
    background-image: url('images/Icon_External_Link.png');
    padding-right: 12px;
    text-decoration: none;
    background-position: right;
    background-repeat:no-repeat;
}}
      </style>
            <meta name="viewport" content="width=device-width, initial-scale=1"/>
            <link href="http://kitwallace.co.uk/odb/images/icon128.PNG" rel="icon" sizes="128x128" />
            <link rel="shortcut icon" type="image/png" href="http://kitwallace.co.uk/odb/images/icon128.PNG"/>

    </head>
    <body>
    <h3>Real time data streams from <a href="https://opendata.bristol.gov.uk/">Open Data Bristol</a> at {format-dateTime(current-dateTime() + xs:dayTimeDuration("PT1H"),"[H01]:[m01] on [D01]/[M01]/[Y0001]")}</h3>

 
<table>
  <tr>
    <th>Stream</th>
    <th colspan="2">Rows</th>
    <th>Frequency</th>
    <th colspan="2">Minimum</th>
    <th colspan="2">Maximum</th>
    <th>All ages in minutes</th>

  </tr>  
  <tr>
    <th/>
    <th>Count</th>
    <th>Health</th>
    <th/>
    <th>Age</th>
    <th>Health</th>
    <th>Age</th>
    <th>Health</th>
    <th><em>hover for list</em></th>
  </tr>

  {
 let $config := doc("./data/realtimefeeds.xml")
 for $feed in $config//feed
 let $dataurl := concat("https://opendata.bristol.gov.uk/api/views/",$feed/id,"/rows.xml?accessType=DOWNLOAD")
 let $data := doc($dataurl)
 let $rows := $data//row[@_id]
 let $dateTimeCode := $feed/dateTime/code
 let $allAges := 
     if (exists($dateTimeCode))
     then
        for $row in $rows
        let $dateTime := util:eval($dateTimeCode)
        let $age_min := if(exists($dateTime)) then round((current-dateTime() - xs:dateTime($dateTime)) div xs:dayTimeDuration("PT1M")) else ()
        order by $age_min 
        return $age_min
      else ()
 let $ages := distinct-values($allAges)
 let $freqmin := if ($feed/frequency/@unit="hours") 
                 then 60 * number($feed/frequency)
                 else  if ($feed/frequency/@unit="minutes") 
                 then  number($feed/frequency)
                 else ()
 let $minage := $ages[1]
 let $maxage := $ages[last()]
 return
     <tr>
      <th  style="text-align:left"><a class="external" href="{$feed/pageurl}">{$feed/title/string()}</a></th> 
      <td>{count($rows)} {if (exists($feed/rows)) then concat (" of ",$feed/rows) else ()}</td>
      <td>{if (empty($feed/rows)) 
           then ()
           else if ($feed/rows = count($rows)) 
           then  <span style="background-color: green">good</span>
           else if (count($rows) < $feed/rows  )
           then  <span style="background-color: red">missing</span>
           else  <span style="background-color: yellow">extra</span>
           }
      </td>     
      <td>{concat($feed/frequency," ",$feed/frequency/@unit)}</td>
      <td> {if (exists($minage)) then local:minutes_to_days_hrs_min($minage) else ()} </td>
      <td> {if (not (exists($freqmin)) or (not (exists($ages))))
            then <span style="background-color: pink"> unknown</span> 
            else if ($minage <= $freqmin) 
            then <span style="background-color: green"> current</span>
            else if ($minage <= 1.5* $freqmin) 
            then <span style="background-color: yellow"> &lt;= 50% late</span>
            else if ($minage <= 2* $freqmin)
            then <span style="background-color: orange"> &lt;= 100% late</span>
            else <span style="background-color: red"> &gt;= 100% late</span>
           }
      </td>
      <td>{if (exists($maxage)) then local:minutes_to_days_hrs_min($maxage) else () } </td>
      <td>{if (not (exists($freqmin)) or (not (exists($ages))))
           then <span style="background-color: pink"> unknown</span> 
           else if ($maxage <= $freqmin) 
            then <span style="background-color: green"> current</span>
            else if ($maxage <= 1.5* $freqmin) 
            then <span style="background-color: yellow"> &lt;= 50% late</span>
            else if ($maxage <= 2* $freqmin)
            then <span style="background-color: orange"> &lt;= 100% late</span>
            else <span style="background-color: red"> &gt;= 100% late</span>
            }
       </td> 
       <td title="{string-join($allAges,",")}">All Ages</td>
     </tr>
 }
 </table>
 <hr/>
 <div>Configuration and stream metadata <a href="data/realtimefeeds.xml">XML</a></div>
 <div>This dashboard was made by <a href="http://kitwallace.co.uk"> Chris Wallace </a> on 23 March 2016 using XQuery 
 <a href="https://github.com/KitWallace/odb/blob/master/xquery/realtimedashboard.xq">(source on Github)</a> on an <a href="http://exist-db.org">eXist-db</a> database.  </div>
 </body>
 </html>
