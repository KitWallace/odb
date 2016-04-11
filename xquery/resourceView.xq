import module namespace date = "http://kitwallace.me/date" at "/db/lib/date.xqm";

declare namespace html = "http://www.w3.org/1999/xhtml";
declare namespace og = "http://opengraphprotocol.org/schema/";

declare variable $local:resourceAnnotations := doc("data/resourceAnnotations.xml");
declare variable $local:resourceMetadata := doc("data/resourceMetadata.xml")/resources;


declare function local:download-url($id,$format) {
 concat("https://opendata.bristol.gov.uk/api/views/",$id,"/rows.",$format,"?accessType=DOWNLOAD")
};

declare function local:page-url($id) {
 concat("https://opendata.bristol.gov.uk/d/",$id)
};

declare function local:get-meta($id,$refresh){
 let $storedMeta := $local:resourceMetadata/resource[id=$id]
 return 
   if ($refresh) 
   then let $temp := local:analyse-resource($id)
        let $store := if (exists($storedMeta))
                      then update replace $storedMeta with $temp
                      else update insert $temp into $local:resourceMetadata
        return $temp
   else 
       if (exists($storedMeta))
       then $storedMeta
       else 
             let $temp := local:analyse-resource($id)
             let $store := update insert $temp into $local:resourceMetadata
             return $temp
};

declare function local:get-annotation($id) {
    $local:resourceAnnotations//annotation[id=$id]
};
declare function local:toString($item) {
   concat( string($item),
           string-join( for $at in $item/@* return concat(name($at),"=",string($at))," ")
         )
};

declare function local:update-annotation($meta) {
    let $id := $meta/id
    let $annotations := local:get-annotation($id)
    let $fdata := request:get-parameter("frequency","")
    let $newannotations :=
        element annotation {
            $id,
            element title { request:get-parameter("title",())},
            element description {request:get-parameter("description",())},
            element comment {request:get-parameter("comment",())},
            element start { request:get-parameter("start",())},
            element end { request:get-parameter("end",())}, 
            let $frequency := request:get-parameter("frequency","")
            return if ($frequency != "") then element frequency {$frequency} else (),
            element dimensions {request:get-parameter("dimensions",())},
            for $column at $i in $meta//column
            let $comment := request:get-parameter(concat("comment_",$i),())
            let $name := request:get-parameter(concat("name_",$i),())
            let $description := request:get-parameter(concat("description_",$i),())
            return
              if (concat($comment,$name,$description) != "")
              then 
                 element column {
                       attribute i  {$i},
                       element name {$name},
                       element comment {$comment},
                       element description {$description}
                }
              else ()

        }
     let $update := if ($annotations) 
                   then update replace $annotations with $newannotations
                   else update insert $newannotations into $local:resourceAnnotations/annotations
     return $update
};

declare function local:gather-metadata($id) {
   let $directurl := local:page-url($id)
   let $page := httpclient:get(xs:anyURI($directurl),false(),())/httpclient:body/html:html  
   let $pageurl := $page//html:meta[@property="og:url"]/@content/string()
   return
     element resource {
       element id {$id},
       element pageurl {$pageurl},
       element title {substring-before($page//html:meta[@property="og:title"]/@content,"|")},
       element description {$page//html:meta[@name="description"]/@content/string()},
       element category { tokenize($pageurl,"/")[4 ]},
       element type {$page//html:div[@id="datasetIcon"]/html:span[1]/string()}
     }  
};

declare function local:analyse-resource($id) {
let $meta := local:gather-metadata($id)
let $annotation := local:get-annotation($id)
let $rows := doc(local:download-url($id,"xml"))/response/row/row
let $unixtimes := ("status_time","currentvaluetime")
let $rowCount := count($rows)
return
element resource  {
   $meta/*,
   element rowCount{$rowCount},
   element columns {
      let $row1 := $rows[4]
      let $rown := $rows[position() = $rowCount]
      for $column at $i in $row1/*
      let $colannotation := $annotation/column[@i=$i]
      let $name := name($column)
      let $values := if ($name = "status_time" or $colannotation/name= "status_time")
                     then $rows/*[name(.)=$name]/string(date:epoch-seconds-to-dateTime(.))
                     else $rows/*[name(.)=$name]
      let $dvalues := distinct-values($values)
      let $valueCount:= count($dvalues)
      let $unique:= if ($valueCount = $rowCount)
                     then true()
                     else false()
      let $isLocation := exists($column/@latitude) and  exists($column/@longitude)
      let $isInteger:= not ($isLocation ) and ( every $v in $dvalues satisfies $v castable as xs:integer   )         
      let $isFloat := not ($isLocation or $isInteger) and (every $v in $dvalues satisfies $v castable as xs:float  )            
      let $isDate := not ($isLocation or $isFloat or $isInteger) and (every $v in $dvalues satisfies $v castable as xs:date)           
      let $isDateTime := not ($isLocation or $isFloat or $isInteger or $isDate) and (every $v in $dvalues satisfies $v castable as xs:dateTime )      
      let $isURL :=  not ($isLocation or $isFloat or $isInteger or $isDate or $isDateTime) and (every $v in $dvalues satisfies starts-with($v,"http" ) ) 
      let $isNumber := $isFloat or $isInteger or $isDate
      let $locationCount := if ($isLocation) then count(distinct-values($values/string-join(./@*,","))) else ()
      let $svalues := if ($isFloat or $isInteger)
                      then for $v in $dvalues order by number($v) return $v
                      else for $v in $dvalues order by $v return $v
      return 
         element column {
            attribute i {$i},
            element name {name($column)},
            element valueCount {if ($isLocation) then $locationCount else $valueCount},
            if ($valueCount < 20) then 
            element values {string-join($svalues,"|")}
            else( ),
            if ($unique) then element unique {} else (),
            element type {if ($isLocation) then "location" else if ($isInteger) then "integer" else if ($isFloat) then "float" else if ($isDateTime) then "dateTime" else if ($isDate) then "date" else if($isURL) then "URL" else "text"},
            element valueMin {if ($isLocation) then concat(max($values/@latitude),",",min($values/@longitude)) else  $svalues[1]},
            element valueMax {if ($isLocation) then concat(min($values/@latitude),",",max($values/@longitude)) else  $svalues[last()]},
            element missing {$rowCount - count($values) }
            
     (:       count(for $v in $values where $v = "" return $v)  :)

         }
   }
  }
};

declare function local:annotation-form($meta,$annotation ){
<form action="?" method="post">
       <input type="hidden" name="id" value="{$meta/id}"/>
       <input type="hidden" name="mtitle" value="{$meta/title}"/>
       <table>
         <tr><th>title</th><td>{$meta/title/string()}<br/><em><input type="text" name="title" value="{$annotation/title}" size="100"/></em></td></tr>
         <tr><th>description</th><td>{$meta/description/string()}<br/><em><input type="text" name="description" value="{$annotation/description}" size="100"/></em></td></tr>
         <tr><th>comment</th><td><textarea name="comment" rows="3" cols="80">{$annotation/comment/string()}</textarea></td></tr>
         <tr><th>start date</th><td><input type="text" name="start" value="{$annotation/start}"size ="20"/></td></tr>        
         <tr><th>end date</th><td><input type="text" name="end" value="{$annotation/end}"size ="20"/></td></tr>    
         <tr><th>frequency (realtime)</th><td><input type="text" name="frequency" value="{$annotation/frequency}"/></td></tr>
         <tr><th>dimensions</th><td><input type="text" name="dimensions" value="{$annotation/dimensions}"size ="20"/></td></tr>     
         <tr><th>Columns</th>
         <td><table>
         <tr><th>name</th><th>rename</th><th>description</th><th>comment</th></tr>
             {for $column at $i in $meta//column
              let $colannotation := $annotation//column[@i= $i]
              return
               <tr><td>{$column/name/string()}</td>
                   <td><input name="{concat("name_",$i)}" value = "{$colannotation/name/string()}"/></td>
                   <td><input name="{concat("description_",$i)}" value = "{$colannotation/description/string()}"/></td>
                   <td><input name="{concat("comment_",$i)}" value = "{$colannotation/comment/string()}"/></td>
              </tr>
             }
         </table>
         </td></tr>
       </table>
       <input type="submit" name="action" value="update"/> <input type="submit" name="action" value="leave"/>
     </form>  

};

declare function local:resource-list() {
<div><h5>Click on a column title to re-order the list</h5>
<table class="sortable">
<tr><th>Category</th><th width="400">Title</th><th>Type</th><th>Dimensions</th><th>Start</th><th>End</th><th>Comment</th></tr>
{for $resource at $i in $local:resourceMetadata//resource
 let $id := $resource/id
 let $annotation := local:get-annotation($id)
 let $title := $resource/title
 order by $resource/category, $title
 return 
 <tr class="alternate"> 
     <td>{$resource/category/string()}</td>
     <td align="left"><a href="?id={$id}">{$title/string()}</a></td>
     <td>{if ($annotation/frequency) then "real time" else $resource/type/string()}</td>
     <td>{$annotation/dimensions/string()}</td>
     <td width="15">{$annotation/start/substring(.,1,4)}</td>
     <td width="15">{if ($annotation/end != "") then $annotation/end/substring(.,1,4) else $annotation/start/substring(.,1,4)}</td>
     <td>{$annotation/comment/node()}</td>
 </tr>
 }
</table>
</div>

};
declare function local:render-resource($resource, $annotation) {
let $id := $resource/id
return
<table>
  <tr><th>Category</th><td>{$resource/category/string()}</td></tr>
  <tr><th>id</th><td>{$id/string()}</td></tr>
  <tr><th>Type</th><td>{$resource/type/string()}</td></tr>
  
   <tr><th>title</th><td>{$resource/title/string()} 
           {if ($annotation/title != "") 
            then <div><em>{concat($annotation/title," ",$annotation/view/type)}</em></div> 
            else ()}</td></tr>
   {if (exists($annotation/view))
   then <tr><th>View</th>
     <td> {$annotation/view/type/string()} of <a href="?id={$annotation/view/base}">{$annotation/view/base/string()}</a>
          {string-join($annotation/view/filter ,":")}
          
     </td>
     </tr> else () }
  <tr><th>description</th><td>{$resource/description/string()} {if ($annotation/description) then <div><em>{$annotation/description/node()}</em></div> else ()}</td></tr>
  <tr><th>#rows</th><td>{$resource/rowCount/string()}</td></tr>
  <tr><th>date</th><td><em>{if ($annotation/end != "") then concat($annotation/start, " - " ,$annotation/end) else $annotation/start/string()}</em></td></tr>
  <tr><th>frequency (realtime)</th><td>{$annotation/frequency/string()}</td></tr>
  {if ($annotation/dimensions !="")
   then <tr><th>Dimensions</th><td>{$annotation/dimensions/string()}</td></tr>
   else ()
   }
   {if ($annotation/comment) then 
   <tr><th>Comment</th><td><em>{$annotation/comment/node()}</em></td></tr>
   else ()
   }
  <tr><th>columns</th>
      <td>
      <table>
        <tr><th>pos</th><th>name</th><th># distinct values <br/>(hover for values)</th><th>Unique</th><th>Type</th><th>missing</th><th>Min</th><th>Max</th><th>Rename</th><th>Comment</th></tr>
        {for $column at $i in $resource/columns/column
         let $colannotation := $annotation/column[@i=$i]
          return 
         <tr> <th>{$column/@i/string()}</th>
              <td>{$column/name/string()}</td>
              <td title="{$column/values/string()}">{$column/valueCount/string()}</td>
              <td>{if($column/unique) then "yes" else ()}</td>
              <td><b>{$column/type/string()}</b></td>
              <td>{$column/missing/string()}</td>
              <td>{$column/valueMin/string()}</td>
              <td>{if ($column/valueCount > 1) then $column/valueMax/string() else ()}</td>
              <td>{$colannotation/name/string()}</td>
              <td>{$colannotation/comment/string()}</td>
          </tr>
         }
      </table>
     </td>
    </tr>
 </table>
};

let $pageurl := request:get-parameter("pageurl",())
let $id := if ($pageurl) then tokenize($pageurl,"/")[last()] else request:get-parameter("id",())
let $action := request:get-parameter("action",())
let $login := xmldb:login(....)
let $serialize := util:declare-option("exist:serialize","method=xhtml media-type=text/html")

return 
<html>
   <head>
      <script src="jscripts/sorttable.js"></script>
      <style>
      tr.alternate:nth-child(even) {{background: lightgreen}}
      </style>
      </head>
      <body>

{
if ($action="about")
then 
  <div>
   Independant analysis of  <a href="https://opendata.bristol.gov.uk/" target="_blank">OpenDataBristol</a> resources -  created by <a href="http://kitwallace.co.uk">Kit Wallace</a> using XQuery and eXistdb.
   
  </div> 
else 
if (exists($id) and $action="edit")
then 
  let $meta := local:get-meta($id, false())
  let $annotation := $local:resourceAnnotations//annotation[id=$id]
  let $form := local:annotation-form($meta,$annotation)
  return
  <div>
     <h3><a href="?">Analyzed ODB Resources</a>  &#160; <a href="?id={$id}">{$meta/title/string()}</a> Annotation editor </h3>
     {$form}
  </div> 
else 
if (exists($id))
then 
    let $meta := local:get-meta($id, $action="refresh")
    let $update :=
        if ($action="update") 
        then  local:update-annotation($meta)  
        else ()
    let $annotation := local:get-annotation($id)
    return
 <div>
   <h3> <a href="?">Analyzed ODB Resources</a> &#160; {$meta/title/string()}&#160; <a href="https://opendata.bristol.gov.uk/" target="_blank">OpenDataBristol</a> </h3>
    <form action="?">Resource <input name="pageurl" type="text" size="100"/> <input type="submit" value="analyse"/> 
   </form>
   <h4>   <a href="{$meta/pageurl}" target="_blank">View</a>&#160;
   <a href="?id={$meta/id}&amp;action=edit">Create/Edit Annotations</a>&#160;
   <a href="?id={$meta/id}&amp;action=refresh">Refresh analysis</a>&#160;
   Download <a href="{local:download-url($id,"xml")}">XML</a>  &#160;
   <a href="{local:download-url($id,"csv")}">csv</a>

   </h4>
    {local:render-resource($meta,$annotation)}
 </div>
else 
   <div>
   <h3>Analyzed ODB Resources &#160; <a href="https://opendata.bristol.gov.uk/" target="_blank">OpenDataBristol</a> &#160;<a href="?action=about">About</a> </h3>
   <form action="?">Resource <input name="pageurl" type="text" size="100"/> <input type="submit" value="analyse"/> 
   </form>
   {local:resource-list()}
</div>
}
</body>
</html>
