Notes
=====

Random notes about internals so they don't get forgotten
(and most of them not about Christine, how about that).

Creating new command functionality
----------------------------------

* Core functionality (message attributes etc) is all handled in connection.pike
  _send_recursive(). The order things are checked determines precedence.
* Commands can be directly manipulated in twitchbot_commands.json with no
  validation checks; they will take effect on next update of modules/addcmd.
* From the front end, commands are filtered by chan_commands.pike validate(),
  with the majority of flags being checked in the recursive _validate().
* For completely new functionality, the command GUI will need a new type of
  element, possibly with a new colour.
  - This element needs a method of distinguishment, most commonly an attribute
    with a fixed value.
* For any kind of newish feature, the command GUI probably needs a new tray
  item to make it easily accessible. This may also require enhancing the
  type to allow more flexibility.
* The classic editor needs to be enhanced.
  - Simple features can be added to the flags mapping at the top
  - More complicated features need ad-hoc code in render_command()
