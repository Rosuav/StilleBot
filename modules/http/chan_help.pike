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
</style>
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

//When the intrinsic user goes online or offline, notify.
@hook_channel_online: @hook_channel_offline:
int recheck(string chan, int uptime, int chanid) {
	if (chanid == G->G->bot_uid) send_updates_all("");
}
