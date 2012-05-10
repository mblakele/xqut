xquery version "1.0-ml";

(:
 : Copyright (c) 2011-2012 Michael Blakeley. All Rights Reserved.
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

declare private variable $DEBUG := false();

declare private variable $NL := codepoints-to-string(10);

(: This function quotes an XML node,
 : and then reparses it with canonical indentation
 : and encoding. This is needed in order to compare nodes
 : that differ by indentation whitespace.
 :)
declare function t:canonicalize(
  $i as item())
as item()
{
  typeswitch($i)
  case attribute() return $i
  case binary() return $i
  case comment() return $i
  case document-node() return document { t:canonicalize($i/node()) }
  case element() return element { node-name($i) } {
    $i/namespace::*,
    t:canonicalize(($i/@*, $i/node())) }
  case processing-instruction() return $i
  case text() return (
    (: within XML, normalize whitespace that looks like indentation :)
    if (count($i/../node()) lt 1) then $i else
      let $nws := normalize-space($i)
      return if ($nws eq '') then $nws else $i)
  default return $i
};

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
      $new, 'options', concat(
        string-join(
          (map:get($old, 'options'),
            if (not($e/boundary-space)) then ()
            else 'declare boundary-space preserve;'),
          $NL))),
    map:put(
      $new, 'namespaces', concat(
        string-join(
          (map:get($old, 'namespaces'),
            for $i in $e/namespace
            return concat(
              'declare namespace ', $i/@prefix,
              '=', xdmp:describe($i/@ns/string(), 1024), ';')),
          $NL))),
    map:put(
      $new, 'imports', concat(
        string-join(
          (map:get($old, 'imports'),
            for $i in $e/import
            return concat(
              'import module namespace ', $i/@prefix,
              '=', xdmp:describe($i/@ns/string(), 1024),
              ' at ', xdmp:describe($i/@at/string(), 1024), ';')),
          $NL))),
    map:put(
      $new, 'variables', concat(
        string-join(
          (map:get($old, 'variables'),
            for $i in $e/variable
            return concat(
              'declare variable $', $i/@symbol,
              ' := ', $i/string(), ';')),
          $NL))))
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

(: The XML for cts:query can take on funny variations,
 : which aren't handled by deep-equal.
 : Comparing cts:query items is common enough
 : to include this code in the test framework.
 :
 : The signature for $n cannot be more specific because of recursion.
 :)
declare function t:cts-query-normalize(
  $n as node())
as node()
{
  typeswitch($n)
  case element(cts:element) return element cts:element {
    (: normalize namespace prefixes to match the evaluation context :)
    let $qn := try { resolve-QName($n/string(), $n) } catch ($e) {
      if ($e/error:code eq 'XDMP-NONAMESPACEBIND') then xs:QName($n)
      else xdmp:rethrow() }
    return QName(namespace-uri-from-QName($qn), local-name-from-QName($qn)) }
  case element() return element { node-name($n) } {
    $n/@*,
    t:cts-query-normalize($n/node()) }
  default return $n
};

declare private function t:eval-check2(
  $result as item()*,
  $pass as xs:string,
  $fail as xs:string,
  $assert as item()*)
as xs:string
{
  if (deep-equal($assert, $result)) then $pass else $fail
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
  (: enforce the assertion, whatever it might be :)
  else (
    typeswitch($assert)
    case attribute(result) return t:eval-check2(
      $result/string(), $pass, $fail, $assert/string())
    case element(setup) return $pass
    case element(teardown) return $pass
    (: clean up namespace prefixes for deep-equal :)
    case element(*,cts:query) return t:eval-check2(
      t:cts-query-normalize($result), $pass, $fail,
      t:cts-query-normalize($assert))
    (: deep-equal does not work with cts:query, so recurse with XML form :)
    (: NB - expect errors for cts:query $result and element() $assert :)
    case cts:query return t:eval-check(
      document { $result }/cts:query, $pass, $fail, $error,
      document { $assert }/cts:query)
    default return t:eval-check2($result, $pass, $fail, $assert))
};

declare private function t:eval-expr(
  $expr as xs:string,
  $context as map:map)
as item()*
{
  t:debug('eval-expr', $expr),
  xdmp:eval($expr, t:eval-vars($context), t:eval-options($context))
};

declare private function t:eval-expr(
  $expr as xs:string,
  $context as map:map,
  $fatal as xs:boolean,
  $note as xs:string,
  $error as xs:string,
  $pass as xs:string,
  $fail as xs:string,
  $assert as item()*)
as element()
{
  if (string-length(normalize-space($expr)) gt 0) then ()
  else t:fatal('EMPTYEXPR', xdmp:quote($expr))
  ,
  let $expr := string-join(
    (for $i in ('options', 'namespaces', 'imports', 'variables', 'functions')
      return map:get($context, $i),
      $expr), $NL)
  let $start := xdmp:elapsed-time()
  let $result := try {
    t:eval-expr($expr, $context) } catch ($ex) {
    if (not($fatal)) then $ex
    else t:fatal(
      'FATAL',
      ($expr, $ex/error:code, $ex/error:message,
        'line', $ex/error:stack/error:frame[1]/error:line)) }
  let $elapsed := xdmp:elapsed-time() - $start
  let $assert := t:canonicalize($assert)
  let $result := t:canonicalize($result)
  let $ln := t:eval-check($result, $pass, $fail, $error, $assert)
  return element { xs:QName($ln) } {
    attribute note { $note },
    if ($ln eq $pass) then attribute elapsed { $elapsed }
    else (
      element expr {
        attribute xml:space { 'preserve' },
        $expr },
      element assert {
        attribute description { xdmp:describe($assert) },
        $assert },
      element result {
        attribute description { xdmp:describe($result) },
        $result })}
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
  t:eval-expr(
    $e,
    t:environment($e/environment, $context),
    ($e/@fatal/xs:boolean(.), false())[1],
    ($e/@note, xdmp:path($e))[1],
    'setup-error', 'setup-ok', '__BUG', $e)
};

declare private function t:teardown(
  $e as element(teardown),
  $context as map:map)
as element()
{
  t:debug('teardown', $e),
  let $context := t:environment($e/environment, $context)
  return t:eval-expr(
    $e, $context, ($e/@fatal/xs:boolean(.), false())[1],
    ($e/@note, xdmp:path($e))[1],
    'teardown-error', 'teardown-ok', '__BUG', $e)
};

declare private function t:suite(
  $e as element(suite),
  $context as map:map)
 as element(results)
{
  let $context := t:environment($e/environment, $context)
  return element results {
    t:setup($e/setup, $context),
    t:walk($e/*, $context),
    t:teardown($e/teardown, $context)
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
    if (exists($e/expr/node() except $e/expr/text()))
    then xdmp:quote($e/expr/node())
    else if (exists($e/expr)) then $e/expr/string()
    else $e/string()
    ,
    t:environment($e/environment, $context),
    ($e/@fatal/xs:boolean(.), false())[1],
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
  (: NB - context, setup, and teardown need to be explicit :)
  case element(boundary-space) return ()
  case element(environment) return ()
  case element(import) return ()
  case element(setup) return ()
  case element(teardown) return ()
  case element(suite) return t:suite($n, $context)
  case element(unit) return t:unit($n, $context)
  case element(variable) return ()
  default return t:fatal('UNEXPECTED', $n)
};

(: lib-xqut.xqy :)
