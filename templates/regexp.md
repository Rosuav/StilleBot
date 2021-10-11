# Regular Expressions

Regular expressions offer a powerful text matching syntax, which you can use to
make decisions in your commands and triggers. If you're already familiar with PCREs,
[this cheat sheet](https://www.debuggex.com/cheatsheet/regex/pcre) lists all the
special symbols that have meaning in a regexp.

<form action="#" autocomplete="off">
<table border>
<tr><td><label for=regexp>Reg&nbsp;Exp:</label></td><td><input id=regexp value="^[Hh]ello$" size=60></td></tr>
<tr><td><label for=text>Text:</label></td><td><input id=text value="hello" size=60></td></tr>
<tr><td>Result:</td><td><span id=result></span></td></tr>
</table>
</form>

<style>
#result {display: inline-block;}
.regex-error {background: #fcc;}
.regex-match {background: #cfc;}
.regex-nomatch {background: #ccf;}

code {background: #f0d0f0; margin: 0 0.25em}
strong {background: #c0f0d0; margin: 0 0.25em}

form {font-size: 125%;}
input {font-size: 100%; width: 100%;}
</style>

## Regexp Features

Normal text in a regular expression matches that exact text. In these examples,
`[Hh]ello` is a regexp, and **hello** is text that matches it.

A regexp conditional succeeds if *any part of* the string matches it. The condition
`[Hh]ello` would match on the input "Why, **hello** there!", and would set
<samp>{regexp0}</samp> to **hello**.

### Anchors

A regexp will match anywhere in the text, unless it is anchored with a `^` at the
start and/or a `$` at the end. You can also match entire words (including emote
names) by anchoring with `\b`.

* `yes` ==> **yes** **yesterday** **eyesore** **dyes**
* `^yes` ==> **yes** **yesterday**
* `yes$` ==> **yes** **dyes**
* `^yes$` ==> **yes**
* `\byes\b` ==> **yes** **i said yes**

### Sets of characters

To match any of a group of characters, use square brackets.

* `abc[xyz]` ==> **abcx** **abcy** **abcz**
* `cheer[0-9]` ==> **cheer1** **cheer7** **cheer0**
* `[A-Za-z0-9]` ==> **Q** **l** **3**

For alternatives that are more than one character long, use either-or notation:

* `a (foo|bar) b` ==> **a foo b** **a bar b**

### Matching multiple of something

To match more than one of the same group of characters, add a marker after the group.

* Optional: `a[0-9]?b` ==> **ab** **a1b**
* Any number, including none at all: `a[0-9]*b` ==> **a123b** **ab** **a1b**
* At least one: `a[0-9]+b` ==> **a11111b** **a0b**
* Exactly N: `a[0-9]{3}b` ==> **a123b** **a234b** **a345b**
* At least, and at most: `a[0-9]{2,5}b` ==> **a11b** **a44444b**

----

Test out your regular expressions above and then use them in conditionals in commands and triggers.
