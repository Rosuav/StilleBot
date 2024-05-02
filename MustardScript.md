MustardScript
=============

Mustard Mine's command language, called MustardScript, is a human-editable text representation of a
command. Like Raw mode, it turns the entire command into simple text; unlike Raw mode, it's actually
something you would want to read and write.

The language is designed with simplicity in mind. Simple commands are simple; complex commands are
no more complex than they need to be.

Syntax
------

* Comments begin with "//" and end at the end of the current line. Aside from this, line breaks
  are meaningless, and you could collapse an entire command onto one line if you wanted to!
* A string in quotes `"like this"` will normally be sent as a message.
* Builtin functionality such as the calculator can be called on using function-like syntax:
  `calc("1 + 2 + 3") "{result}"`
* Flags are set on any message or group as directives:
  `#access mod`
  If the flag/setting is not a simple word or number, it can be put in quotes:
  `#automate "10-15"`
* Grouping of messages: Use either braces or square brackets.
  `["Hello" "world"]`
  This will send both messages. Useful when applying settings to a group.
* Variables are set by giving their names:
  `$variable$ = "some value"`
  - This includes ephemeral and per-user variables `$*somevar$ = 123`
  - To add to a variable: `$variable$ += 1`
  - To spend from a variable: `$variable$ -= 1` Note that this will silently fail if
    the variable's prior content is insufficient for the spend. This is not very useful
    on its own, but can be used in an `if` statement.
* Conditional statements use the `if` and `else` keywords.
  `if ("{param}" == "hello") "Hello to you too!" else "Goodbye."`
  - Using groups here is generally good for readability.
  - Valid types of condition:
    - String comparison: `if ("this" == "that")`
    - String inclusion: `if ("word" in "this has words in it")`
    - Regular expression: `if ("([0-9]+)" =~ "{param}")`
    - Spend: `if ($variable$ -= 5)` Equivalent to doing the variable spend, but if
      the spend fails due to insufficient value, the `else` clause will be run instead
      of the `if` block.
* Exception handling
  `try {"/shoutout {param}"} catch {"Can't shout out now, {error}"}`
  - Leaving the catch block empty will silently suppress errors
  - Uncaught errors will be logged to your channel's Error Log
  - Use `chan_errors("THROW", "Whoopsie") {}` to raise errors for testing.

To try out different forms of syntax, create them using the graphical editor, then
switch to script view to see how they look. You can then edit the script and return
to graphical view to see the effect.

Future improvements
-------------------

As the language evolves, new syntax may be created which will improve readability.
Existing notation will continue to be valid, but will be equivalent to the newer form.

* dest, target, and destcfg
* Per-user-ness of cooldowns and variables?
* Setting boolean attributes eg casefold - currently `#casefold = "on"` which sucks

Currently strings don't break at end of line. Should they? Errors become hard to read
when an unmatched quote suddenly consumes the whole rest of the file.
