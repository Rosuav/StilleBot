inherit command;
constant access = "mod";

//TODO: Make a web interface to this
//In the web UI, also have some shorthands for creating other features:
//- Autoban buy-follows
//- Giveaway triggers?? Maybe?
//- Transcoding on stream start
//- VLC track reporting
//- VLC !song command (and link to the VLC page, of course)
//- Shoutout command, and link to the main commands page ("others here")
//- Hype train status?
//Note that these will not necessarily report whether they're active; they'll just have a "Create" button.
//Maybe also a "Delete" button for some, where plausible.

constant FEATURES = ({
	({"quotes", "Adding, deleting, and removing quotes"}),
});
mapping FEATUREDESC = mkmapping(FEATURES[*][0], FEATURES[*][1]); //For some reason, mkmapping doesn't count as constant. Whatever.

constant docstring = sprintf(#"
Enable or disable bot features.

Usage: `!features featurename {enable|disable|default}`

Setting a feature to 'default' state will enable it if all-cmds, disable if
http-only. TODO: Make this flag visible and possibly mutable.

Feature name | Effect
-------------|-------------
%{{%s} | %s
%}
", FEATURES);

echoable_message process(object channel, mapping person, string param) {
	mapping feat = persist_config->path("channels", channel->name[1..], "features");
	sscanf(param, "%s %s", string feature, string active);
	if (!FEATUREDESC[feature]) return "@$$: Valid feature names are: " + FEATURES[*][0] * ", ";
	switch (active) {
		case "": {
			if (feat[feature]) return sprintf("@$$: Feature is %sabled -- %s", feature > 0 ? "en" : "dis", FEATUREDESC[feature]);
			return sprintf("@$$: Feature is %sabled by default -- %s", channel->config->allcmds ? "en" : "dis", FEATUREDESC[feature]);
		}
		case "default": {
			m_delete(feat, feature);
			return sprintf("@$$: %sabled by default -- %s", channel->config->allcmds ? "En" : "Dis", FEATUREDESC[feature]);
		}
		case "enable": feat[feature] = 1; return "@$$: Enabled feature -- " + FEATUREDESC[feature];
		case "disable": feat[feature] = -1; return "@$$: Disabled feature -- " + FEATUREDESC[feature];
		default: return "@$$: Usage: !features " + feature + " enable/disable";
	}
}
