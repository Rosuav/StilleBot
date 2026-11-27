inherit http_websocket;

//Most of this info will need to be changed if another instance of the bot is run, but the
//core code should still be applicable.
constant contact_button = #"
Need help with the bot? Here are some ways to [contact Rosuav](:.opendlg data-dlg=contactdlg),
the bot's creator and maintainer.

> ### Contacting Rosuav
>
> Rosuav can be reached on Discord or Twitch using that same user name. To avoid spam, be<br>
> sure to include in your opening message that you use Mustard Mine and what your issue is.
>
> You can also [join the Discord](https://discord.gg/dbw4KYE :target=_blank) for general questions,
> updates, and other information.
>
> Rosuav is currently live! The quickest and easiest way to get help will be to<br>
> [jump into chat](https://twitch.tv/rosuav :target=_blank) and ask there. He's always happy to help!
> {:#is_live hidden}
>
> <form id=whisperform>
> Need to send a quick message right now?<br>
> <input id=whisper size=60> [Whisper](:type=submit)
> </form>
>
> [Close](:.dialog_close)
{: tag=dialog #contactdlg}

<style>
#is_live {
	margin: 1em;
	border: 3px double green;
	padding: 0.25em 2em;
	background: aliceblue;
}
#tip {
	margin: 0.5em;
	border: 1px solid green;
	padding: 0.25em 1em;
	background: aliceblue;
}
#avatar {
	max-height: 1.2em;
	vertical-align: middle;
}
</style>

Tip loading...<br>[Another tip](:#newtip)
{:#tip hidden}

* Your mods can help you. Link them to these same pages, and they can work on your behalf.
* The same command can be invoked by chat, automated, and even triggered by a channel point reward!
* Bothered by those follower-selling bots? Hop over to [Features](features) and enable auto-banning of them!
* Do you use the Twitch ad scheduler and want to warn people in advance? [Ad-Vance Warning](snoozeads) can put a message in chat.
* Already got a bot account and want to use its name instead of MustardMine? [Authenticate it](voices) and I can use that voice!
* Link your [online shops and other platforms](integrations) to have [goal bars](monitors) update with that support!
* Increase user engagement with some fun [minigames](minigames)!
* Got ideas but don't know how to make them happen? Ask Rosuav for help - chances are it can be done somehow!
* Do you stream similar content often, but different things on different days? [Save your setups](streamsetup) and let the bot remember for you!
* The more work there is of mine, the less there is of yours. ![Mustard Mine's motto](/static/MustardMineAvatar.png :#avatar)
{:#tips hidden}
";

constant bcaster_info = #"# Channel services

The Mustard Mine serves this channel in a variety of ways. As broadcaster, you have full
access to all of these settings; a good place to start is [Feature Activation](features).
After that, the sidebar has a list of the most common sections, many of which can be
enabled with default settings for a quick start, and then can be further configured as
needed.

Your mods are able to help you with most of the pages here. A small number of
broadcaster-only settings can be found on the [Master Control Panel](mastercontrol).
" + contact_button;

constant mod_info = #"# Channel services

The Mustard Mine serves this channel in a variety of ways. As a moderator, you have full
access to the majority of these settings; since the broadcaster has trusted you with a
sword, the bot will respect that trust and let you do whatever is needed! A good place to
start is [Feature Activation](features); after that, the sidebar has a list of the most
common sections, which you can activate and configure just as the broadcaster would.

Note that, in a few places, moderator access is slightly different from the broadcaster's;
for example, you are able to send test alerts in the [Alert Box](alertbox) without affecting
an ongoing broadcast, as your tests are sent only to you.
" + contact_button;

constant viewer_info = #"# Channel services

The Mustard Mine serves this channel in a variety of ways. As a viewer, you have access to
a number of informational pages. These same pages offer configuration and control for mods;
if you are a mod, [log in and you can make changes](:.twitchlogin).

The sidebar has a number of pages available for you to browse, depending on which features
the broadcaster has decided to use.
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping params = ([]);
	if (req->misc->is_mod) params->vars = (["ws_group": ""]);
	return render(req,
		!req->misc->is_mod ? viewer_info
		: req->misc->channel->userid == (int)req->misc->session->user->id ? bcaster_info
		: mod_info,
	params | req->misc->chaninfo);
}

mapping get_state(string group) {
	//If the bot's intrinsic user is live, say so. (Note: If the intrinsic user is not
	//the operator, this may need to be changed.)
	return (["online": G->G->stream_online_since[G->G->bot_uid]->?unix_time()]);
}

@hook_channel_online: int online(string chan, int uptime, int chanid) {
	if (chanid == G->G->bot_uid) broadcast((["cmd": "update", "online": time() - uptime])); //This time_t might be off by a second or two, so there may be slight discrepancies in the display.
}
@hook_channel_offline: int offline(string chan, int uptime, int chanid) {
	if (chanid == G->G->bot_uid) broadcast((["cmd": "update", "online": 0]));
}

@"is_mod": mapping wscmd_whisper(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string from = "channel https://twitch.tv/" + channel->login;
	string user = conn->session->user->login;
	if (user != channel->login) from += " mod " + user;
	string message = "Site message from " + from + ": " + msg->message;
	if (G->G->stream_online_since[G->G->bot_uid]) {
		//If I'm currently live, send the message in chat rather than as a whisper.
		//It's more reliable, and probably will be noticed quicker.
		G->G->irc->id[G->G->bot_uid]->send(0, "maayaKey " + message);
	} else {
		//Send a whisper from MustardMine to Rosuav. If you're running your own copy of the
		//bot, figure out two users that you can use for this, since you can't whisper yourself.
		int voiceid = 279141671;
		twitch_api_request(sprintf(
			"https://api.twitch.tv/helix/whispers?from_user_id=%d&to_user_id=%d",
				voiceid, G->G->bot_uid),
			(["Authorization": voiceid]), ([
				"method": "POST",
				"json": (["message": message]),
			]),
		);
	}
}
