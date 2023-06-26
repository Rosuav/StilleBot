inherit command;
constant featurename = "features";
constant access = "mod";

constant FEATURES = ({
	({"allcmds", "Default for features not specified"}),
	({"quotes", "Adding, deleting, and removing quotes"}),
	({"commands", "Chat commands for managing chat commands"}),
	({"features", "Feature management via chat"}),
	({"info", "General information and status commands"}),
});
constant FEATUREDESC = (mapping)FEATURES;

constant docstring = sprintf(#"
Enable or disable bot chat commands.

Usage: `!features featurename {enable|disable|default}`

Features set to the 'default' state follow the setting for allcmds, so in
general, you need only specify the features that are different from that.

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
	if (feature == "allcmds") return "@$$: Cannot change allcmds through the !features command - foot-guns not permitted";
	int send = 1;
	switch (active) {
		case "": send = 0; break;
		case "default": m_delete(feat, feature); break;
		case "enable": feat[feature] = 1; break;
		case "disable": feat[feature] = -1; break;
		default: return "@$$: Usage: !features " + feature + " enable/disable";
	}
	if (object handler = send && G->G->websocket_types->chan_features) {
		handler->update_one("control" + channel->name, feature);
		handler->update_one("view" + channel->name, feature);
	}
	if (feat[feature]) return sprintf("@$$: Feature is %sabled -- %s", feat[feature] > 0 ? "en" : "dis", FEATUREDESC[feature]);
	return sprintf("@$$: Feature is %sabled by default -- %s", channel->config->allcmds ? "en" : "dis", FEATUREDESC[feature]);
}
