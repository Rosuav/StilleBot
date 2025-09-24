Notes
=====

Random notes about internals so they don't get forgotten
(and most of them not about Christine, how about that).

Creating new command functionality
----------------------------------

* Core functionality (message attributes etc) is all handled in connection.pike
  `_send_recursive()`. The order things are checked determines precedence.
* Commands can be directly manipulated in the config mapping with no
  validation checks. This is unsupported behaviour but will probably work.
* From the front end, commands are filtered by chan_commands.pike `validate()`,
  with the majority of flags being checked in the recursive `_validate()`.
* For completely new functionality, the command GUI will need a new type of
  element, possibly with a new colour.
  - This element needs a method of distinguishment, most commonly an attribute
    with a fixed value.
* For any kind of newish feature, the command GUI probably needs a new tray
  item to make it easily accessible. This may also require enhancing the
  type to allow more flexibility. (Optional for new builtins.)
* The classic editor needs to be enhanced.
  - Simple features can be added to the flags mapping at the top
  - More complicated features need ad-hoc code in `render_command()`


Commonly-used emoji
-------------------

* Gear: BUTTON({type: "button", title: "Configure"}, "\u2699")


Hopping the Bot
---------------

Transferring the primary instance of the bot between Gideon and Sikorsky is
simple in theory, but in practice, I have some safeguards to make sure that
nothing goes wrong. Follow these steps to hop the bot back and forth.

Normal operation has the active bot on Sikorsky, the active database on
Sikorsky, and a read-only replica database on Gideon with an inactive bot.
(Note that "inactive" does not mean idle; an inactive bot will continue to
respond to web requests etc, but is not the primary bot, and will reject
any websockets.) In such a situation, running `./dbctl stat` should give
output something like this:

    rosuav@sikorsky:~/stillebot$ ./dbctl stat
    * Database is read/write
    * Active bot is on sikorsky.mustardmine.com
    * Incoming replication active
      192.168.0.19 Active bot [idle] 
     37.61.205.138 Outgoing replication [active] 
     37.61.205.138 Active bot [idle] 
    rosuav@gideon:~/stillebot$ ./dbctl stat
    * Database is read-only
    * Active bot is on sikorsky.mustardmine.com
    * Incoming replication active
     37.61.205.138 Read-only bot [idle] 
     159.196.70.86 Outgoing replication [active] 

Note that both instances of the bot MUST connect to the read/write database,
and both instances will connect to the local database, but there may or may
not be the other cross-connection.

To hop the bot from Sikorsky to Gideon:

1. On both ends, verify that `./dbctl stat` looks good.
2. Sikorsky: `./dbctl dn` to set both databases read-only. We are now in a
   degraded state, with nothing able to be saved yet.
3. Gideon: `./dbctl repl` to ensure that all three LSNs are the same.
   If they aren't, wait a second or two and try again (final transactions
   getting settled).
4. Gideon: `./dbctl up` to bring up the database there. We will now be in a
   fully functional state again, but with Gideon's database being the primary
   instead of Sikorsky's. Check `./dbctl stat` and `./dbctl repl` if desired.
5. Gideon: `./dbctl ac` to activate the bot there. We are now in a safe state
   with both the database and the bot primarily on Gideon. If Sikorsky becomes
   unavailable at this time, the impact will be minimized.

Hopping back is the same with the roles reversed.
