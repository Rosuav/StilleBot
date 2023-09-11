inherit command;
constant active_channels = ({""}); //Deprecated, slated for removal.
constant access = "mod";

constant FEATURES = ({
	({"commands", "Chat commands for managing chat commands"}),
});
constant FEATUREDESC = (mapping)FEATURES;

constant docstring = #"
Enable or disable bot chat commands.

Usage: `!features featurename {enable|disable}`

Note that features disabled here may still be available via the bot's web
interface; this governs only the commands available in chat, usually to
moderators.
";

echoable_message process(object channel, mapping person, string param) {
	mapping feat = channel->path("features");
	sscanf(param, "%s %s", string feature, string active);
	if (FEATUREDESC[param]) {feature = param; active = "";}
	if (!FEATUREDESC[feature]) return "@$$: Valid feature names are: " + FEATURES[*][0] * ", ";
	int send = 1;
	switch (active) {
		case "": send = 0; break;
		case "enable": feat[feature] = 1; break;
		case "disable": m_delete(feat, feature); break;
		default: return "@$$: Usage: !features " + feature + " enable/disable";
	}
	if (object handler = send && G->G->websocket_types->chan_features) {
		handler->update_one("control" + channel->name, feature);
		handler->update_one("view" + channel->name, feature);
	}
	return sprintf("@$$: Feature is %sabled -- %s", feat[feature] ? "en" : "dis", FEATUREDESC[feature]);
}
