//Deprecated in favour of chan_streamsetup, kept as a bouncer
inherit builtin_command;

constant builtin_name = "Setup (deprecated)";
constant builtin_param = ({"/Action/query/title/category/tags/ccls", "New value"});
constant scope_required = "channel:manage:broadcast"; //If you only use "query", it could be done without privilege, though.
constant vars_provided = ([
	"{prevtitle}": "Stream title prior to any update",
	"{newtitle}": "Stream title after any update",
	"{prevcat}": "Stream category prior to any update",
	"{newcat}": "Stream category after any update",
	"{prevtags}": "All tags (space-separated) prior to any update",
	"{newtags}": "All tags after any update",
	"{prevccls}": "Active CCLs prior to any update",
	"{newccls}": "Active CCLs after any update",
]);

Concurrent.Future message_params(object channel, mapping person, array param) {
	return G->G->builtins->chan_streamsetup->message_params(channel, person, param);
}
