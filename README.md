# XQUT

## Warning - Experimental

The interface and syntax described in this document are experimental
and subject to change. Don't let that scare you off, but don't be
surprised if the furniture moves around.

## Introduction

XQUT is a simple unit test framework in pure XQuery. It is designed to
operate in a standalone fashion, called using `xdmp:invoke` or
`xdmp:eval`. You can, of course, wrap these functions in a module of
your own.

The public entry point is the function `test` or the module `xqut.xqy`.
Pass it an XML element representing a suite of unit tests. Here is an example:

```xquery
    xquery version "1.0-ml";
    xdmp:invoke(
      'xqut.xqy',
      (xs:QName('SUITE'),
    <suite xmlns="com.blakeley.xqut">
      <unit result="1">1 + 1</unit>
      <unit>
        <expr>1 + 1</expr>
        <result>2</result>
      </unit>
    </suite>),
      <options xmlns="xdmp:eval">
        <root>/Users/nemo/Source/mblakele-xqut/src/</root>
      </options>)
```

This example shows that the test XML should have a root `suite`
element in the `com.blakeley.xqut` namespace, and that it may have any
number of `unit` children. Each unit should have either a `result`
attribute, in which case the element text will be evaluated as XQuery,
or a pair of `expr` and `result` child elements.

You may declare test XML directly, or supply test XML from a document
in the database using `doc`,  or on the filesystem or network using
`xdmp:document-load`. The results are XML, so we can use XPath as
normal. To see only the failures, for example:

```xquery
    xquery version "1.0-ml";
    xdmp:invoke(
      'xqut.xqy',
      (xs:QName('SUITE'),
    <suite xmlns="com.blakeley.xqut">
      <unit result="1">1 + 1</unit>
      <unit>
        <expr>1 + 1</expr>
        <result>2</result>
      </unit>
    </suite>),
      <options xmlns="xdmp:eval">
        <root>/Users/nemo/Source/mblakele-xqut/src/</root>
      </options>)
```

## Options

An environment element can appear inside a `suite` or `unit` element,
and can be used to specify how each test will be evaluated. These
options, expressed as attributes on `environment`, are passed directly
to `xdmp:eval`.

* `database`
* `default-collation`
* `default-xquery-version`
* `modules`
* `user-id`
* `root`

The attribute `database-name` is resolved to a database id, and then
treated as if the `database` option were set.

Besides these `xdmp:eval` options, each environment element may
include any number of library module imports. Each `import` element
must include the following attributes:

* `prefix`
* `ns`
* `at`

For example, we might declare this XML and pass it to `test`:

```xml
    <suite xmlns="com.blakeley.xqut"
      <import
       prefix="foo" ns="com.example.foo" at="lib-foo.xqy"/>
      <unit result="2">1 * 2</unit>
    </suite>
```
This would cause XQUT to evaluate the following XQuery and compare it to
the value of `unit/@result`:

```xquery
    import module namespace foo = "com.example.foo" at "lib-foo.xqy";
    1 * 2
```

There may also be any number of `setup` elements. The text of each
`setup` element will be evaluated before any `unit` elements are
evaluated. The `environment` options and imports also apply to `setup`
expressions.

## Example

This is a more complex example.

```xquery
    <suite xmlns="com.blakeley.xqut">
      <environment
       root="/Users/nemo/Source/myproject-xquery/src/"
       database-name="my-database" >
        <import prefix="foo" ns="http://example.com/foo"
                at="/lib-foo.xqy"/>
        <import prefix="bar" ns="http://example.com/bar"
                at="/lib-bar.xqy"/>
      </environment>
      <setup>xdmp:collection-delete('TEST')</setup>
      <setup note="load sample documents">
        for $e in xdmp:filesystem-directory(
          concat(xdmp:modules-root(), '../dist'))/dir:entry[
            ends-with(dir:filename, '.xml')]
        let $uri := concat('/lorem-ipsum/', $e/dir:filename)
        return xdmp:document-load(
        $e/dir:pathname,
        &lt;options xmlns="xdmp:document-load"&gt;
          &lt;uri&gt;{ $uri }&lt;/uri&gt;
          &lt;collections&gt;
            &lt;collection&gt;TEST&lt;/collection&gt;&lt;/collections&gt;
        &lt;/options&gt;)
      </setup>
      <unit result="1" note="check library module imports">1</unit>
      <unit result="23">xdmp:estimate(collection('TEST'))</unit>
      <unit result="17">count(foo:bar('baz'))</unit>
      <unit>
        <expr>foo:bar('baz')[1]</expr>
        <result><fubar><foo/><bar/><baz/></fubar></result>
      </unit>
    </suite>
```

## Limitations

At this time, XQUT does not provide a way to insert other prolog
declarations. Patches are welcome.

## License Information

Copyright (c) 2011 Michael Blakeley. All Rights Reserved.
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
