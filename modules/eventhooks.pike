//Twitch's EventSub chaining into special triggers
inherit annotated;

//For each special, list the scopesets it requires, separated with pipes.
//If any listed scopeset is present, the special is considered available. If none are,
//the first scopeset will be used for the authenticate button. Note that this does not
//support "moderator auth", which can be used for follower lookups; as a simplification,
//we support either "broadcaster auth" or "bot intrinsic mod auth" but no other mods.
//A "scopeset" is a blank-delimited set of scopes which must ALL be present. Most often,
//a single scope will be sufficient. Question: Should there be support for *optional*
//scopesets, which could be granted in order to enhance functionality in some way?

//NOTE: To actually add the special triggers, update modules/addcmd.pike and ensure that
//the parameters are all listed correctly. The scopes are automatically provided by this
//file but the special and its description come from addcmd.

//TODO: Prediction ended, to match it
@retain: multiset polls_ended = (<>); //Twitch sends me double notifications. Suppress the duplicates.
@"channel:read:polls|channel:manage:polls":
EventSub pollbegin = EventSub("pollbegin", "channel.poll.begin", "1") {[string chan, mapping info] = __ARGS__;
	object channel = G->G->irc->channels["#" + chan];
	if (!channel) return;
	mapping params = ([
		"{title}": info->title,
		"{choices}": (string)sizeof(info->choices),
		"{points_per_vote}": (string)(info->channel_points_voting->enabled && info->channel_points_voting->amount_per_vote),
	]);
	foreach (info->choices; int i; mapping ch)
		params["{choice_" + (i+1) + "_title}"] = ch->title;
	channel->trigger_special("!pollbegin", ([
		"user": chan,
		"displayname": channel->config->display_name,
		"uid": channel->userid,
	]), params);
};

@"channel:read:polls|channel:manage:polls":
EventSub pollended = EventSub("pollended", "channel.poll.end", "1") {[string chan, mapping info] = __ARGS__;
	if (polls_ended[info->id]) return;
	polls_ended[info->id] = 1;
	object channel = G->G->irc->channels["#" + chan];
	if (!channel) return;
	mapping params = ([
		"{title}": info->title,
		"{choices}": (string)sizeof(info->choices),
		"{points_per_vote}": (string)(info->channel_points_voting->enabled && info->channel_points_voting->amount_per_vote),
	]);
	int top = 0;
	foreach (info->choices; int i; mapping ch) {
		string pfx = "{choice_" + (i+1) + "_";
		params[pfx + "title}"] = ch->title;
		params[pfx + "votes}"] = (string)ch->votes;
		params[pfx + "pointsvotes}"] = (string)ch->channel_points_votes;
		if (ch->votes > info->choices[top]->votes) top = i;
	}
	params["{winner_title}"] = info->choices[top]->title;
	channel->trigger_special("!pollended", ([
		"user": chan,
		"displayname": channel->config->display_name,
		"uid": channel->userid,
	]), params);
};

//Ensure that we have all appropriate hooks for this channel (provide channel->config or equivalent)
void check_hooks(mapping cfg) {
	string chan = cfg->login;
	multiset scopes = (multiset)((persist_status->path("bcaster_token_scopes")[chan]||"") / " ");
	foreach (G->G->SPECIALS_SCOPES; string special; array scopesets) {
		foreach (scopesets, array scopeset) {
			if (!has_value(scopes[scopeset[*]], 0)) {
				//TODO: What if this isn't the correct condition parameters?
				this[special](chan, (["broadcaster_user_id": (string)cfg->userid]));
				break;
			}
		}
	}
}

protected void create(string name) {
	::create(name);
	G->G->SPECIALS_SCOPES = ([]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (stringp(anno)) G->G->SPECIALS_SCOPES[key] = (anno / "|")[*] / " ";
		}
	}
	check_hooks(list_channel_configs()[*]);
}
