(:
    

declare namespace html = "http://www.w3.org/1999/xhtml";
declare namespace og = "http://opengraphprotocol.org/schema/";

declare variable $local:resourceAnnotations := doc("data/resourceAnnotations.xml");

declare function local:download-url($id,$format) {
 concat("https://opendata.bristol.gov.uk/api/views/",$id,"/rows.",$format,"?accessType=DOWNLOAD")
};

declare function local:page-url($id) {
 concat("https://opendata.bristol.gov.uk/d/",$id)
};

declare function local:toString($item) {
   concat( string($item),
           string-join( for $at in $item/@* return concat(name($at),"=",string($at))," ")
         )
};

declare function local:update-annotation($id) {
    let $annotations := $local:resourceAnnotations//annotation[id=$id]
    let $newannotations :=
        element annotation {
            element id {$id},
            element mtitle {request:get-parameter("mtitle",())},
            element title { request:get-parameter("title",())},
            element description {request:get-parameter("description",())},
            element comment {request:get-parameter("comment",())},
            element start { request:get-parameter("start",())},
            element end { request:get-parameter("end",())},            
            $annotations/view
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
       element category { tokenize($pageurl,"/")[4 ]}
     }  
};

declare function local:analyse-resource($meta) {
let $id := $meta/id
let $annotations :=$local:resourceAnnotations//annotation[id=$id]
let $rows := doc(local:download-url($id,"xml"))/response/row/row

let $rowCount := count($rows)
return
element resource  {
   $meta/*,
   $annotations,
   element rowCount{$rowCount},
   element columns {
      let $row1 := $rows[1]
      let $rown := $rows[position() = $rowCount]
      for $column at $i in $row1/*
      let $name := name($column)
      let $values := $rows/*[name(.)=$name]
      let $dvalues := for $v in distinct-values($values) order by $v return $v
      let $valueCount:= count($dvalues)
      let $unique:= if ($valueCount = $rowCount)
                     then true()
                     else false()
      let $isLocation := exists($column/@latitude) and  exists($column/@longitude)
      let $isInteger:= not ($isLocation ) and ( every $v in $dvalues satisfies $v castable as xs:integer   )         
      let $isFloat := not ($isLocation or $isInteger) and (every $v in $dvalues satisfies $v castable as xs:float  )            
      let $isDate := not ($isLocation or $isFloat or $isInteger) and (every $v in $dvalues satisfies $v castable as xs:date)           
      let $isDateTime := not ($isLocation or $isFloat or $isInteger or $isDate) and (every $v in $dvalues satisfies $v castable as xs:dateTime )            
      let $isNumber := $isFloat or $isInteger or $isDate
      let $locationCount := if ($isLocation) then count(distinct-values($values/string-join(./@*,","))) else ()
      return 
         element column {
            attribute i {$i},
            element name {name($column)},
            element valueCount {if ($isLocation) then $locationCount else $valueCount},
            if ($valueCount < 5) then 
            element values {string-join($dvalues,"|")}
            else( ),
            if ($unique) then element unique {} else (),
            element type {if ($isLocation) then "location" else if ($isInteger) then "integer" else if ($isFloat) then "float" else if ($isDateTime) then "dateTime" else if ($isDate) then "date" else "text"},
            element valueMin {if ($isLocation) then concat(max($rows/*[$i]/@latitude),",",min($rows/*[$i]/@longitude)) else if ($isNumber) then min($dvalues) else $dvalues[1]},
            element valueMax {if ($isLocation) then concat(min($rows/*[$i]/@latitude),",",max($rows/*[$i]/@longitude)) else if ($isNumber) then max($dvalues) else $dvalues[last()]},
            element missing {count(for $v in $values where $v = "" return $v)},
            element example {attribute i {1}, local:toString($column) },
            element example {attribute i {$rowCount}, local:toString($rown/*[$i]) }
         }
   }
  }
};

declare function local:render-resource($resource) {
let $id := $resource/id
let $annotation := $resource/annotation
return
<table>
  <tr><th>Category</th><td>{$resource/category/string()}</td></tr>
  <tr><th>id</th><td>{$id}</td></tr>
   <tr><th>title</th><td>{$resource/title/string()} 
           {if ($annotation/title != "") 
            then <div><em>{concat($annotation/title," ",$annotation/view/type)}</em></div> 
            else ()}</td></tr>
  <tr><th>Download</th><td><a href="{local:download-url($id,"xml")}">XML</a>  &#160;<a href="{local:download-url($id,"csv")}">csv</a></td></tr>
   {if (exists($annotation/view))
   then <tr><th>View</th>
     <td> {$annotation/view/type/string()} of <a href="?id={$annotation/view/base}">{$annotation/view/base/string()}</a>
          {string-join($annotation/view/filter ,":")}
          
     </td>
     </tr> else () }
  <tr><th>description</th><td>{$resource/description/string()} {if ($annotation/description) then <div><em>{$annotation/description/node()}</em></div> else ()}</td></tr>
  <tr><th>#rows</th><td>{$resource/rowCount/string()}</td></tr>
  <tr><th>date</th><td><em>{if (exists($annotation/end)) then concat($annotation/start, " - " ,$annotation/end) else $annotation/start/string()}</em></td></tr>
   {if ($annotation/comment) then 
   <tr><th>Comment</th><td><em>{$annotation/comment/node()}</em></td></tr>
   else ()
   }
  <tr><th>columns</th>
      <td>
      <table>
        <tr><th>pos</th><th>name</th><th>#values</th><th>Unique</th><th>Type</th><th>missing</th><th>Min</th><th>Max</th><th>Values</th></tr>
        {for $column in $resource/columns/column
          return 
         <tr> <th>{$column/@i/string()}</th>
              <td>{$column/name/string()}</td>
              <td>{$column/valueCount/string()}</td>
              <td>{if($column/unique) then "yes" else ()}</td>
              <td><b>{$column/type/string()}</b></td>
              <td>{$column/missing/string()}</td>
              <td>{if ($column/valueCount > 1) then $column/valueMin/string() else ()}</td>
              <td>{if ($column/valueCount > 1) then $column/valueMax/string() else ()}</td>
              
 <!--           <td>{$column/example[1]/string()}</td>  -->
              <td>{$column/values/string()}</td>
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
let $login := xmldb:login(...)
let $serialize := util:declare-option("exist:serialize","method=xhtml media-type=text/html")
return
if (exists($id) and $action="edit")
then 
  let $meta := local:gather-metadata($id) 
  let $annotations := $local:resourceAnnotations//annotation[id=$id]
  return
  <div>
     <h3> <a href="https://opendata.bristol.gov.uk/" target="_blank">OpenDataBristol</a> &#160;  <a href="?">Annotated Resources</a>    &#160; Editor</h3>
     Resource <a href="{$meta/pageurl}" target="_blank">View</a>
     <form action="?" method="post">
       <input type="hidden" name="id" value="{$id}"/>
       <input type="hidden" name="mtitle" value="{$meta/title}"/>
       <table>
         <tr><th>title</th><td>{$meta/title/string()}<br/><em><input type="text" name="title" value="{$annotations/title}" size="100"/></em></td></tr>
         <tr><th>description</th><td>{$meta/description/string()}<br/><em><input type="text" name="description" value="{$annotations/description}" size="100"/></em></td></tr>
         <tr><th>comment</th><td><textarea name="comment" rows="3" cols="80">{$annotations/comment/string()}</textarea></td></tr>
         <tr><th>start date</th><td><input type="text" name="start" value="{$annotations/start}"size ="20"/></td></tr>        
         <tr><th>end date</th><td><input type="text" name="end" value="{$annotations/end}"size ="20"/></td></tr>        
       </table>
       <input type="submit" name="action" value="update"/> <input type="submit" name="action" value="leave"/>
     </form>  
  </div> 
else 
if (exists($id))
then 
    let $update :=
        if ($action="update") 
        then  local:update-annotation($id)  
        else ()
    let $meta := local:gather-metadata($id)    
    let $xml := local:analyse-resource($meta)
    return
 <div>
   <h3> <a href="https://opendata.bristol.gov.uk/" target="_blank">OpenDataBristol</a> &#160;  <a href="?">Annotated Resources</a></h3>
   <form action="?">Resource <input name="pageurl" type="text" size="100"   value="{$meta/pageurl}" />  <input type="submit" value="analyse"/> 
   <a href="{$meta/pageurl}" target="_blank">View</a>&#160;
   <a href="?id={$meta/id}&amp;action=edit">Create/Edit Annotations</a>
   
   </form>
    {local:render-resource($xml)}
 </div>
else  
   <div>
   <h3>ODB resource analysis &#160; <a href="https://opendata.bristol.gov.uk/" target="_blank">OpenDataBristol</a>  </h3>
   <form action="?">Resource <input name="pageurl" type="text" size="100"/> <input type="submit" value="analyse"/> 
   </form>
   
   <h3>Annotated Resources</h3>
  
<table>
<tr><th>id</th><th>Title</th><th>Comment</th></tr>
{for $resource in $local:resourceAnnotations//annotation
 return 
 <tr><th><a href="?id={$resource/id}">{$resource/id}</a></th><td>{$resource/category/string()}</td><td>  {$resource/mtitle/string()}</td><td>{$resource/comment/node()}</td></tr>
 }
</table>
</div>
