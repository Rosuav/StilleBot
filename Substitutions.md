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
* {param}, {emotedparam} - extra text on the end of the command. They can
  also be accessed via shorthands "%s" and "%e". For regular commands, this
  comes from chat (so in "!so username", "{param}" is "username"); for
  triggers, it's the text that triggered it; etcetera. The shortforms are
  exactly equivalent to the named forms if no filter or default is needed.
* {username} - the name of the person who invoked or caused this action.
  Can be accessed via shorthand "$$".

All substitutions can be modified with a filter and/or a default. For
instance, a token of {uptime} will be a number (represented with decimal
digits); using {uptime|hms|offline} will use the uptime if it exists,
otherwise will use the string "offline".

TODO: Are there any others that don't come through that way?
