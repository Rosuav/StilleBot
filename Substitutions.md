Variable substitutions in command execution
===========================================

(Note: "Command execution" refers also to triggers, specials, and any other
related features.)

Commands in StilleBot have access to a variety of extra information. These
notations can be used to include this information in your messages:

* $varname$ - variables created by and for your own channel. For example,
  you might have a counter for the number of times you've died: $deaths$
* {token} - information provided by a builtin or special trigger. When a
  command calls on a builtin, it will receive a specific set of keywords
  which can be used in this way.
* %s, %e - extra text on the end of the command. For regular commands, this
  comes from chat (so in "!so username", "%s" is "username"); for triggers,
  it's the text that triggered it; etcetera.
* $$ - the name of the person who invoked or caused this action.

TODO: Are there any others that don't come through that way?
