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

@({"channel:read:polls|channel:manage:polls", "channel.poll.begin", "1"}):
mapping pollbegin(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	mapping params = ([
		"{title}": info->title,
		"{choices}": (string)sizeof(info->choices),
		"{points_per_vote}": (string)(info->channel_points_voting->enabled && info->channel_points_voting->amount_per_vote),
	]);
	foreach (info->choices; int i; mapping ch)
		params["{choice_" + (i+1) + "_title}"] = ch->title;
	return params;
}

@retain: multiset polls_ended = (<>); //Twitch sends me double notifications. Suppress the duplicates.
@({"channel:read:polls|channel:manage:polls", "channel.poll.end", "1"}):
mapping pollended(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	if (polls_ended[info->id]) return 0;
	polls_ended[info->id] = 1;
	mapping params = pollbegin(channel, info);
	int top = 0;
	foreach (info->choices; int i; mapping ch) {
		string pfx = "{choice_" + (i+1) + "_";
		params[pfx + "votes}"] = (string)ch->votes;
		params[pfx + "pointsvotes}"] = (string)ch->channel_points_votes;
		if (ch->votes > info->choices[top]->votes) top = i;
	}
	params["{winner_title}"] = info->choices[top]->title;
	return params;
}

@({"channel:read:predictions|channel:manage:predictions", "channel.prediction.end", "1"}):
mapping predictionended(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	mapping params = ([
		"{title}": info->title,
		"{choices}": (string)sizeof(info->outcomes),
		"{status}": info->status, //"resolved" or "canceled"
	]);
	string winner_pfx, loser_pfx;
	foreach (info->outcomes; int i; mapping ch) {
		string pfx = "{choice_" + (i+1) + "_";
		if (ch->id == info->winning_outcome_id) winner_pfx = pfx;
		else if (sizeof(info->outcomes) == 2) loser_pfx = pfx;
		params[pfx + "title}"] = ch->title;
		params[pfx + "users}"] = (string)ch->users;
		params[pfx + "points}"] = (string)ch->channel_points;
		foreach (ch->top_predictors; int j; mapping person) {
			string pfx = pfx + "top_" + (j+1) + "_";
			params[pfx + "user}"] = person->user_name;
			params[pfx + "userid}"] = person->user_id;
			params[pfx + "points_used}"] = (string)person->channel_points_used;
			params[pfx + "points_won}"] = (string)person->channel_points_won; //0 if you were on the losing side
		}
	}
	if (winner_pfx) foreach (params; string kwd; string val)
		if (has_prefix(kwd, winner_pfx)) params["{winner_" + kwd - winner_pfx] = val;
	if (winner_pfx) foreach (params; string kwd; string val)
		if (has_prefix(kwd, loser_pfx)) params["{loser_" + kwd - loser_pfx] = val;
	return params;
}

mapping eventsubs = ([]);

//Ensure that we have all appropriate hooks for this channel (provide channel->config or equivalent)
void specials_check_hooks(mapping cfg) {
	string chan = cfg->login;
	multiset scopes = (multiset)((persist_status->path("bcaster_token_scopes")[chan]||"") / " ");
	foreach (G->G->SPECIALS_SCOPES; string special; array scopesets) {
		foreach (scopesets, array scopeset) {
			if (!has_value(scopes[scopeset[*]], 0)) { //If there isn't any case of a scope that we don't have... then we have them all!
				if (cfg->commands[?"!" + special]) //If there's a special of this name, we need the hook. Otherwise no.
					eventsubs[special](chan, this[special](0, (["__condition": cfg])));
				break;
			}
		}
	}
}

class EventSubSpecial(function get_params) {
	inherit EventSub;
	protected void create(string hookname, string type, string version) {
		::create(hookname, type, version, send_special);
	}
	void send_special(string chan, mapping info) {
		object channel = G->G->irc->channels["#" + chan];
		if (!channel) return;
		mapping params = get_params(channel, info);
		if (params) channel->trigger_special("!" + hookname, ([
			"user": chan,
			"displayname": channel->config->display_name,
			"uid": channel->userid,
		]), params);
	}
}

protected void create(string name) {
	::create(name);
	G->G->SPECIALS_SCOPES = ([]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (arrayp(anno)) {
				G->G->SPECIALS_SCOPES[key] = (anno[0] / "|")[*] / " ";
				eventsubs[key] = EventSubSpecial(this[key], key, @anno[1..]);
			}
		}
	}
	specials_check_hooks(list_channel_configs()[*]);
	G->G->specials_check_hooks = specials_check_hooks;
}
