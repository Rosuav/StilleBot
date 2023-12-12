MustardScript
=============

StilleBot's command language, called MustardScript, is entirely equivalent to the JSON internal format.

Do I need one? Maybe?

- Come up with a grammar which can compile to the same array/mapping that the command executor runs
- This will confirm that this truly is an AST, and one that can be saved efficiently in JSON
- Go through the validator for features. It's okay if the grammar parses to an inefficient version,
  same as the GUI editor often does. That's what an AST optimization step is for.
- Design goals:
  - Be simple. Avoid unnecessary punctuation.
  - Be unambiguous. Don't omit *necessary* punctuation. This is a DSL not a shell command.
  - Be indentation-safe
    - Maybe have a one-liner version (like semicolon separation, Python style)?
  - Have complexity that scales as linearly as possible
  - Eschew boilerplate of any kind
  - Have all of the power of the command editor
  - Be compact enough to work with in chat
- Hello world should simply be "Hello, world!" - double quotes for a string, and a string is a message.
- Builtins should be entirely generic. Any builtin should be able to become any other.
- Other features (voices etc) may end up being custom syntax, but don't have syntax for everything if
  it's possible to combine some in sensible ways.
- First design a parser, completely external to the main bot. Use Parser.LR same as calc.
- Then design a decompiler that takes the AST and crafts viable source code
- It MAY be worth having a "saved source code" version of a command, which is discarded if you make
  any edit in any other form, but otherwise is retained.
- This might finally be able to replace the Classic editor, which can then be renamed Legacy
- Comments will be introduced with a double slash. If it looks like commented-out code and can
  round trip as such, it should be done accordingly when transformed into GUI mode. Otherwise,
  it's just text comments like anywhere else.

Syntax
------

* Top-level flags: access, visibility, automate, etc
  - Assignment style? eg: access=mod
* Grouping: Braces or square brackets. Must be correctly nested but otherwise behave identically?
* Comments begin with "//" and end at newline, or with "/*" and end at "*/" - nesting permitted?
* Mode (rotate/random/foreach), delay, voice
* Destination (whisper, web, variable, chain, reply)
* Builtins - function-like syntax?
* Conditions. These have three parts: condition type and parameters, if-true, if-false.

Broad structure: Nested groups, including top-level which is implicitly a group.
Inside any group, assignment statements affect that group and any subgroups.

Tokens:
name - an atom. Not sure yet what alphabet to support.
string - quoted string. If it contains quotes, they must be escaped. Use %q from Pike.
number - a string of digits, optionally a decimal point.

Limitations
-----------

Currently, flags have to be written as "#access=mod" to disambiguate the grammar. I would
like to be able to avoid that. Is it necessary to have two different types of "name", one
for flags and one for builtins? That could lead to very confusing error messages. Maybe
it's okay to write flags like this??

Future improvements
-------------------

Note that many of these will continue to be possible using the "naive" syntax, but the
preferred syntax will read better.

* dest, target, and destcfg
* Setting of variables, maybe that gets its own syntax??
* Per-user-ness of cooldowns and variables?
* Setting boolean attributes eg casefold - currently <<#casefold = "on">> which sucks

Currently strings don't break at end of line. Should they? Errors become hard to read
when an unmatched quote suddenly consumes the whole rest of the file.


NOTE: There is a distinct semantic difference between these two statements:

    $var$ += -1
    $var$ -= 1

The latter is a "spend" operation, best used in a condition, and will never take the
variable below zero. The former is simple arithmetic, and uses both positive and
negative values freely.
