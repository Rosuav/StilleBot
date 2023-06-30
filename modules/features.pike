inherit command;
constant featurename = "features";
constant access = "mod";

constant FEATURES = ({
	({"quotes", "Adding, deleting, and removing quotes"}),
	({"commands", "Chat commands for managing chat commands"}),
	({"features", "Feature management via chat"}),
	({"info", "General information and status commands"}),
	//({"unknown", "Problems"}), //If any show up in this list, it's a bug to be fixed.
});
constant FEATUREDESC = (mapping)FEATURES;

constant docstring = sprintf(#"
Enable or disable bot chat commands.

Usage: `!features featurename {enable|disable}`

Note that features disabled here may still be available via the bot's web
interface; this governs only the commands available in chat, usually to
moderators.

Feature name | Effect
-------------|-------------
%{%s | %s
%}
", FEATURES);

echoable_message process(object channel, mapping person, string param) {
	if (!persist_config->has_path("channels", channel->name[1..])) return 0; //No channel, don't manage features
	mapping feat = persist_config->path("channels", channel->name[1..], "features");
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
