inherit http_websocket;
constant markdown = #"# Minigames for $$channel$$

Want to add some fun minigames to your channel? These are all built using Twitch
channel points and other related bot features. Note that these will require that
the channel be affiliated/partnered in order to use channel points.

Bit Boss
--------

Not yet implemented.

Seize the Crown
---------------

Coming soon!

First!
------

This might be the last thing I implement.
";

/*
Bit Boss
- Alternate display mode for a goal bar: "Hitpoints".
- As the value advances toward the goal, the display reduces, ie it is inverted
- Use the "level up command" to advance to a new person
- Have an enableable feature that gives:
  - Goal bar, with variable "bitbosshp" and goal "bitbossmaxhp"
  - Level up command that sets "bitbossuser" to $$, resets bitbosshp to bitbossmaxhp,
    and maybe changes bitbossmaxhp in some way
    - Note that "overkill" mode can be done by querying the goal bar before making changes
  - Stream online special that initializes everything
  - Secondary monitor that shows the user's name and avatar??? Or should there be two
    effective monitors in the same page?

First, and optionally Second, Third, and Last
- Second/Third/Last are enabled by First/Second/Third
- Last can be had w/o Second/Third, so you can have anywhere from 1 to 4 redemptions
- Each one puts the person's name into the description and puts a message in chat
- You're not allowed to claim more than one. If you do, the message shames you.
*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

mapping get_chan_state(object channel, string grp, string|void id) {
	return ([]);
}
