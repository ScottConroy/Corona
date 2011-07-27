(:
Copyright 2011 MarkLogic Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
:)

xquery version "1.0-ml";

module namespace manage="http://marklogic.com/mljson/manage";

import module namespace json="http://marklogic.com/json" at "json.xqy";
import module namespace prop="http://xqdev.com/prop" at "properties.xqy";
import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";

declare namespace db="http://marklogic.com/xdmp/database";
declare default function namespace "http://www.w3.org/2005/xpath-functions";



declare function manage:validateIndexName(
    $name as xs:string?
) as xs:string?
{
    if(empty($name) or string-length($name) = 0)
    then "Must provide a name for the index"
    else if(not(matches($name, "^[0-9A-Za-z_-]+$")))
    then "Index names can only contain alphanumeric, dash and underscore characters"
    else if(exists(prop:get(concat("index-", $name))))
    then concat("An index, field or alias with the name '", $name, "' already exists")
    else ()
};


declare function manage:createField(
    $name as xs:string,
    $includeKeys as xs:string*,
    $excludeKeys as xs:string*,
    $includeElements as xs:string*,
    $excludeElements as xs:string*,
    $config as element()
) as empty-sequence()
{
    let $database := xdmp:database()
    let $config := admin:database-add-field($config, $database, admin:database-field($name, false()))
    let $add :=
        for $include in $includeKeys[string-length(.) > 0]
        let $include := json:escapeNCName($include)
        let $el := admin:database-included-element("http://marklogic.com/json", $include, 1, (), "", "")
        return xdmp:set($config, admin:database-add-field-included-element($config, $database, $name, $el))
    let $add :=
        for $exclude in $excludeKeys[string-length(.) > 0]
        let $exclude := json:escapeNCName($exclude)
        let $el := admin:database-excluded-element("http://marklogic.com/json", $exclude)
        return xdmp:set($config, admin:database-add-field-excluded-element($config, $database, $name, $el))

    let $add :=
        for $include in $includeElements[string-length(.) > 0]
        let $namespace :=
            if(contains($include, ":"))
            then namespace-uri(element { $include } { () })
            else ""
        let $include := 
            if(contains($include, ":"))
            then tokenize($include, ":")[2]
            else $include
        let $el := admin:database-included-element($namespace, $include, 1, (), "", "")
        return xdmp:set($config, admin:database-add-field-included-element($config, $database, $name, $el))
    let $add :=
        for $exclude in $excludeElements[string-length(.) > 0]
        let $namespace :=
            if(contains($exclude, ":"))
            then namespace-uri(element { $exclude } { () })
            else ""
        let $el := admin:database-excluded-element($namespace, $exclude)
        return xdmp:set($config, admin:database-add-field-excluded-element($config, $database, $name, $el))
    return admin:save-configuration($config)
    ,
    prop:set(concat("index-", $name), concat("field/", $name))
};

declare function manage:deleteField(
    $name as xs:string,
    $config as element()
) as empty-sequence()
{
    admin:save-configuration(admin:database-delete-field($config, xdmp:database(), $name)),
    prop:delete(concat("index-", $name))
};

declare function manage:getField(
    $name as xs:string,
    $config as element()
) as element(json:item)?
{
    let $database := xdmp:database()
    let $def :=
        try {
            admin:database-get-field($config, $database, $name)
        }
        catch ($e) {()}
    where exists($def)
    return manage:fieldDefinitionToJsonXml($def)
};

declare function manage:getAllFields(
    $config as element()
) as element(json:item)*
{
    let $database := xdmp:database()
    let $config := admin:get-configuration()
    for $field in admin:database-get-fields($config, $database)
    where string-length($field/*:field-name) > 0
    return manage:fieldDefinitionToJsonXml($field)
};


declare function manage:createJSONMap(
    $name as xs:string,
    $key as xs:string,
    $mode as xs:string
) as empty-sequence()
{
    prop:set(concat("index-", $name), concat("map/json/", $name, "/", json:escapeNCName($key), "/", $mode))
};

declare function manage:createXMLMap(
    $name as xs:string,
    $element as xs:string,
    $mode as xs:string
) as empty-sequence()
{
    prop:set(concat("index-", $name), concat("map/xml/", $name, "/", $element, "/", $mode))
};

declare function manage:deleteMap(
    $name as xs:string
) as empty-sequence()
{
    prop:delete(concat("index-", $name))
};

declare function manage:getMap(
    $name as xs:string
) as element(json:item)?
{
    let $property := prop:get(concat("index-", $name))
    let $bits := tokenize($property, "/")
    let $type := $bits[2]
    let $name := $bits[3]
    let $key := json:unescapeNCName($bits[4])
    let $element := $bits[4]
    let $mode := $bits[5]
    where $bits[1] = "map"
    return
        if($type = "json")
        then json:object((
            "name", $name,
            "type", $type,
            "key", $key,
            "mode", $mode
        ))
        else json:object((
            "name", $name,
            "type", $type,
            "element", $element,
            "mode", $mode
        ))
};

declare function manage:getAllMaps(
) as element(json:item)*
{
    for $key in prop:all()
    let $value := prop:get($key)
    where starts-with($key, "index-") and starts-with($value, "map/")
    return manage:getMap(substring-after($key, "index-"))
};


declare function manage:createRange(
    $name as xs:string,
    $key as xs:string,
    $type as xs:string,
    $operator as xs:string,
    $config as element()
) as empty-sequence()
{
    let $key := json:escapeNCName($key)
    let $operator :=
        if($type = "boolean")
        then "eq"
        else $operator
    return
        if($type = "string")
        then
            let $index := admin:database-range-element-index("string", "http://marklogic.com/json", $key, "http://marklogic.com/collation/", false())
            let $config := admin:database-add-range-element-index($config, xdmp:database(), $index)
            return admin:save-configuration($config)
        else if($type = "date")
        then
            let $index := admin:database-range-element-attribute-index("dateTime", "http://marklogic.com/json", $key, "", "normalized-date", "", false())
            let $config := admin:database-add-range-element-attribute-index($config, xdmp:database(), $index)
            return admin:save-configuration($config)
        else if($type = "number")
        then
            let $index := admin:database-range-element-index("decimal", "http://marklogic.com/json", $key, "", false())
            let $config := admin:database-add-range-element-index($config, xdmp:database(), $index)
            return admin:save-configuration($config)
        else if($type = "boolean")
        then
            (: XXX - don't think we can create range indexes of type boolean :)
            let $index := admin:database-range-element-attribute-index("boolean", "http://marklogic.com/json", $key, "", "boolean", "", false())
            let $config := admin:database-add-range-element-attribute-index($config, xdmp:database(), $index)
            return admin:save-configuration($config)
        else
            ()
    ,
    prop:set(concat("index-", $name), concat("range/", $name, "/", json:escapeNCName($key), "/", $type, "/", $operator))
};

declare function manage:deleteRange(
    $name as xs:string,
    $config as element()
) as empty-sequence()
{
    let $database := xdmp:database()
    let $property := prop:get(concat("index-", $name))
    let $bits := tokenize($property, "/")
    let $key := $bits[3]
    let $type := manage:jsonTypeToSchemaType($bits[4])
    let $existing := manage:getRangeDefinition($key, $type, $config)
    where $bits[1] = "range"
    return (
        if(exists($existing))
        then (
            if(local-name($existing) = "range-element-index")
            then admin:save-configuration(admin:database-delete-range-element-index($config, $database, $existing))
            else admin:save-configuration(admin:database-delete-range-element-attribute-index($config, $database, $existing))
        )
        else ()
        ,
        prop:delete(concat("index-", $name))
    )
};

declare function manage:getRange(
    $name as xs:string
) as element(json:item)?
{
    let $property := prop:get(concat("index-", $name))
    let $bits := tokenize($property, "/")
    let $key := $bits[3]
    let $type := $bits[4]
    let $operator :=
        if($type = "boolean")
        then "eq"
        else $bits[5]
    where $bits[1] = "range"
    return json:object((
        "name", $name,
        "key", json:unescapeNCName($key),
        "type", $type,
        "operator", $operator
    ))
};

declare function manage:getAllRanges(
) as element(json:item)*
{
    for $value in manage:getRangeIndexProperties()
    let $bits := tokenize($value, "/")
    return manage:getRange($bits[2])
};


declare function manage:setNamespaceURI(
    $prefix as xs:string,
    $uri as xs:string
) as empty-sequence()
{
    let $config := admin:get-configuration()
    let $group := xdmp:group()
    let $existing := admin:group-get-namespaces($config, $group)[*:prefix = $prefix]
    let $config :=
        if(exists($existing))
        then admin:group-delete-namespace($config, $group, $existing)
        else $config

    let $namespace := admin:group-namespace($prefix, $uri)
    return admin:save-configuration(admin:group-add-namespace($config, $group, $namespace))
};

declare function manage:deleteNamespace(
    $prefix as xs:string
) as empty-sequence()
{
    let $config := admin:get-configuration()
    let $group := xdmp:group()
    let $namespace := admin:group-get-namespaces($config, $group)[*:prefix = $prefix]
    where exists($namespace)
    return admin:save-configuration(admin:group-delete-namespace($config, $group, $namespace))
};

declare function manage:getNamespaceURI(
    $prefix as xs:string
) as element(json:item)*
{
    let $uri :=
        try {
            namespace-uri(element { concat($prefix, ":foo") } { () })
        }
        catch($e) {
            ()
        }
    where exists($uri) and not(starts-with($prefix, "index-"))
    return
        json:object((
            "prefix", $prefix,
            "uri", $uri
        ))
};

declare function manage:getAllNamespaces(
) as element(json:item)*
{
    let $config := admin:get-configuration()
    let $group := xdmp:group()
    for $namespace in admin:group-get-namespaces($config, $group)
    where not(starts-with(string($namespace/*:namespace-uri), "http://xqdev.com/prop/"))
    return json:object((
        "prefix", string($namespace/*:prefix),
        "uri", string($namespace/*:namespace-uri)
    ))
};



(: Private functions :)

declare private function manage:getPrefixForNamespaceURI(
    $uri as xs:string
) as xs:string?
{
    let $config := admin:get-configuration()
    let $group := xdmp:group()
    for $namespace in admin:group-get-namespaces($config, $group)
    where string($namespace/*:namespace-uri) = $uri
    return string($namespace/*:prefix)
};

declare private function manage:fieldDefinitionToJsonXml(
    $field as element(db:field)
) as element(json:item)
{
    json:object((
        "name", string($field/db:field-name),
        "includedKeys", json:array(
            for $include in $field/db:included-elements/db:included-element
            for $key in tokenize(string($include/db:localname), " ")
            return
                if($include/db:namespace-uri = "http://marklogic.com/json")
                then json:object((
                    "type", "key",
                    "name", json:unescapeNCName($key)
                ))
                else json:object((
                    "type", "element",
                    "name", if(string-length($include/db:namespace-uri)) then concat(manage:getPrefixForNamespaceURI(string($include/db:namespace-uri)), ":", $key) else $key
                ))
        ),
        "excludedKeys", json:array(
            for $exclude in $field/db:excluded-elements/db:excluded-element
            for $key in tokenize(string($exclude/db:localname), " ")
            return
                if($exclude/db:namespace-uri = "http://marklogic.com/json")
                then json:object((
                    "type", "key",
                    "name", json:unescapeNCName($key)
                ))
                else json:object((
                    "type", "element",
                    "name", if(string-length($exclude/db:namespace-uri)) then concat(manage:getPrefixForNamespaceURI(string($exclude/db:namespace-uri)), ":", $key) else $key
                ))
        )
    ))
};

declare private function manage:getRangeDefinition(
    $key as xs:string,
    $xsType as xs:string,
    $config as element()
) as element()?
{
    (
        for $index in admin:database-get-range-element-indexes($config, xdmp:database())
        where $index/*:scalar-type = $xsType and $index/*:namespace-uri = "http://marklogic.com/json" and $index/*:localname = $key
        return $index
        ,
        for $index in admin:database-get-range-element-attribute-indexes($config, xdmp:database())
        where $index/*:scalar-type = $xsType and $index/*:parent-namespace-uri = "http://marklogic.com/json" and $index/*:parent-localname = $key
        return $index
    )[1]
};

declare private function manage:getRangeIndexProperties(
) as xs:string*
{
    for $key in prop:all()
    let $value := prop:get($key)
    where starts-with($key, "index-") and starts-with($value, "range/")
    return $value
};

declare private function manage:jsonTypeToSchemaType(
    $type as xs:string?
) as xs:string?
{
    if(empty($type))
    then ()
    else if($type = "string")
    then "string"
    else if($type = "date")
    then "dateTime"
    else "decimal"
};

declare private function manage:schemaTypeToJsonType(
    $type as xs:string?
) as xs:string?
{
    if(empty($type))
    then ()
    else if($type = "string")
    then "string"
    else if($type = "dateTime")
    then "date"
    else if($type = "boolean")
    then "boolean"
    else "decimal"
};
