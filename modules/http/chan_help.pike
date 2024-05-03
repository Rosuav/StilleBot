inherit http_endpoint;

constant bcaster_info = #"# Channel services

The Mustard Mine serves this channel in a variety of ways. As broadcaster, you have full
access to all of these settings; a good place to start is [Feature Activation](features).
After that, the sidebar has a list of the most common sections, many of which can be
enabled with default settings for a quick start, and then can be further configured as
needed.

Your mods are able to help you with most of the pages here. A small number of
broadcaster-only settings can be found on the [Master Control Panel](mastercontrol).
";

constant mod_info = #"# Channel services

The Mustard Mine serves this channel in a variety of ways. As a moderator, you have full
access to the majority of these settings; since the broadcaster has trusted you with a
sword, the bot will respect that trust and let you do whatever is needed! A good place to
start is [Feature Activation](features); after that, the sidebar has a list of the most
common sections, which you can activate and configure just as the broadcaster would.

Note that, in a few places, moderator access is slightly different from the broadcaster's;
for example, you are able to send test alerts in the [Alert Box](alertbox) without affecting
an ongoing broadcast, as your tests are sent only to you.
";

constant viewer_info = #"# Channel services

The Mustard Mine serves this channel in a variety of ways. As a viewer, you have access to
a number of informational pages. These same pages offer configuration and control for mods;
if you are a mod, [log in and you can make changes](:.twitchlogin).

The sidebar has a number of pages available for you to browse, depending on which features
the broadcaster has decided to use.
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return render_template(
		!req->misc->is_mod ? viewer_info
		: req->misc->channel->userid == (int)req->misc->session->user->id ? bcaster_info
		: mod_info,
	([]) | req->misc->chaninfo);
}
