xquery version "1.0-ml";

(:
 : Copyright (c) 2011 Michael Blakeley. All Rights Reserved.
 :
 : Licensed under the Apache License, Version 2.0 (the "License");
 : you may not use this file except in compliance with the License.
 : You may obtain a copy of the License at
 :
 : http://www.apache.org/licenses/LICENSE-2.0
 :
 : Unless required by applicable law or agreed to in writing, software
 : distributed under the License is distributed on an "AS IS" BASIS,
 : WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 : See the License for the specific language governing permissions and
 : limitations under the License.
 :
 : The use of the Apache License does not indicate that this project is
 : affiliated with the Apache Software Foundation.
 :
 :)

(:~ lib-xqut.xqy
 :
 : This library provides XQuery unit test functionality.
 :)

module namespace t = "com.blakeley.xqut";

declare default element namespace "com.blakeley.xqut";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

declare boundary-space strip;

declare private variable $CONTEXT-DEFAULTS := (
  let $m := map:map()
  let $put := (
    map:put($m, 'database', xdmp:database()),
    map:put($m, 'default-collation', default-collation()),
    map:put($m, 'default-xquery-version', xdmp:xquery-version()),
    map:put($m, 'modules', xdmp:modules-database()),
    map:put($m, 'user-id', xdmp:get-request-user()),
    map:put($m, 'root', xdmp:modules-root())
  )
  return $m
);

declare private variable $DEBUG := true();

declare private function t:environment(
  $e as element(environment)*,
  $old as map:map)
as map:map
{
  if (empty($e) or empty($e/@*)) then $old else
  (: make a copy :)
  let $new := map:map(document { $old }/map:map)
  let $put := (
    for $a in $e/@*
    return typeswitch($a)
    case attribute(database-name) return map:put(
      $new, 'database', xdmp:database($a))
    default return (
      let $k := local-name($a)
      return (
        if (empty(map:get($new, $k))) then t:fatal('UNEXPECTED-ENV', $k)
        else map:put($new, $k, $a/string()) ))
    ,
    map:put(
      $new, 'imports', concat(
        map:get($old, 'imports'),
        for $i in $e/import
        return concat(
          'import module namespace ', $i/@prefix,
          '=', xdmp:describe($i/@ns/string(), 1024),
          ' at ', xdmp:describe($i/@at/string(), 1024), '; ')))
  )
  return $new
};

declare private function t:debug(
  $label as xs:string,
  $body as item()*)
as empty-sequence()
{
  if (not($DEBUG)) then ()
  else xdmp:log((concat('[XQUT/', $label, ']'), $body), 'debug')
};

declare private function t:eval-check(
  $result as item()*,
  $pass as xs:string,
  $fail as xs:string,
  $error as xs:string,
  $assert as item()*)
as xs:string
{
  if ($result instance of element(error:error)) then $error
  else if (empty($assert)) then $pass
  (: enforce the assertion, whatever it might be :)
  else typeswitch($assert)
  (: TODO - implement more complex behavior :)
  case attribute(result) return (
    if (deep-equal($assert/string(), string($result))) then $pass else $fail)
  case element(setup) return $pass
  case xs:anyAtomicType return (
    if (deep-equal($assert, $result)) then $pass else $fail)
  default return (
    if (deep-equal($assert, $result)) then $pass else $fail)
};

declare private function t:eval-expr(
  $expr as xs:string,
  $context as map:map)
as item()*
{
  xdmp:eval(
    concat(map:get($context, 'imports'), $expr),
    t:eval-vars($context),
    t:eval-options($context))
};

declare private function t:eval-expr(
  $expr as xs:string,
  $context as map:map,
  $note as xs:string,
  $error as xs:string,
  $pass as xs:string,
  $fail as xs:string,
  $assert as item()*)
as element()
{
  let $start := xdmp:elapsed-time()
  let $result := try { t:eval-expr($expr, $context) } catch ($ex) { $ex }
  let $ln := t:eval-check($result, $pass, $fail, $error, $assert)
  return element { xs:QName($ln) } {
    attribute note { $note },
    attribute elapsed { xdmp:elapsed-time() - $start },
    if ($ln eq $pass) then () else (
      element assert { $assert },
      $result ) }
};

declare private function t:eval-options(
  $context as map:map)
as element()
{
  <options xmlns="xdmp:eval">
  {
    for $i in (
      'database', 'default-collation', 'default-xquery-version',
      'modules', 'user-id', 'root')
    return element { $i } { map:get($context, $i) }
  }
  </options>
};

declare private function t:eval-path(
  $path as xs:string,
  $context as map:map)
as item()*
{
  t:eval-expr(xdmp:document-get($path), $context)
};

declare private function t:eval-vars(
  $context as map:map)
as element()*
{
  (: TODO - support passing external variables :)
  ()
};

declare private function t:fatal(
  $code as xs:string,
  $body as item()*)
{
  error((), concat('XQUT-', $code), $body)
};

declare private function t:setup(
  $e as element(setup),
  $context as map:map)
as element()
{
  t:debug('setup', $e),
  let $context := t:environment($e/environment, $context)
  return t:eval-expr(
    $e, $context, ($e/@note, xdmp:path($e))[1],
    'setup-error', 'setup-ok', '__BUG', $e)
};

declare private function t:suite(
  $e as element(suite),
  $context as map:map)
 as element(results)
{
  let $context := t:environment($e/environment, $context)
  return element results {
    t:setup($e/setup, $context),
    t:walk($e/*, $context)
  }
};

declare function t:test(
  $n as node())
 as element(results)
{
  t:walk($n, $CONTEXT-DEFAULTS)
};

declare function t:test-all(
  $path as xs:string)
 as element(results)*
{
  (: TODO is the path a file or a directory?
   : Read in the file(s) and call t:test on any t:suite elements.
   :)
  t:fatal('UNIMPLEMENTED', $path),
  t:walk((), $CONTEXT-DEFAULTS)
};

declare private function t:unit(
  $e as element(unit),
  $context as map:map)
as element()
{
  t:eval-expr(
    text { ($e/expr, $e)[1] },
    t:environment($e/environment, $context),
    ($e/@note, xdmp:path($e))[1],
    'error', 'pass', 'fail',
    (: attributes are always atomic :)
    if (exists($e/@result)) then $e/@result/data(.)
    (: elements may be atomic :)
    else if (empty($e/result/(
          comment()
          |element()
          |processing-instruction()))) then $e/result/data(.)
    (: Looks like XML structure,
     : but exclude empty text nodes to allow intended XML.
     : This introduces a limitation...
     : we may not catch some differences in pretty-printed output.
     :)
    else $e/result/node()[
      not(. instance of text() and string-length(normalize-space(.)) eq 0)]
  )
};

declare private function t:walk(
  $n as node(),
  $context as map:map)
as element()*
{
  typeswitch($n)
  case document-node() return t:walk($n/*, $context)
  (: NB - context and setup need to be explicit :)
  case element(environment) return ()
  case element(import) return ()
  case element(setup) return ()
  case element(suite) return t:suite($n, $context)
  case element(unit) return t:unit($n, $context)
  default return t:fatal('UNEXPECTED', $n)
};

(: lib-xqut.xqy :)
