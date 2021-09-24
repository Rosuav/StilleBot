# Regular Expressions

Regular expressions offer a powerful text matching syntax, which you can use to
make decisions in your commands and triggers. If you're familiar with PCRE syntax,
[this cheat sheet](https://www.debuggex.com/cheatsheet/regex/pcre) lists all the
special symbols that have meaning in a regexp.

<form action="#" autocomplete="off">
<table border>
<tr><td><label for=regexp>Reg Exp:</label></td><td><input id=regexp value="[Hh]ello"></td></tr>
<tr><td><label for=text>Text:</label></td><td><input id=text></td></tr>
<tr><td>Result:</td><td><span id=result></span></td></tr>
</table>
</form>

<style>
#result {display: inline-block;}
.regex-error {background: #fcc;}
.regex-match {background: #cfc;}
.regex-nomatch {background: #ccf;}

code {background: #f0a0f0;}
strong {background: #a0f0c0;}
</style>

## Regexp Features

Normal text in a regular expression matches that exact text. In these examples,
`[Hh]ello` is a regexp, and **hello** is text that matches it.

### This

### That

### the Other

----

Test out your regular expressions above and then use them in conditionals in commands and triggers.
