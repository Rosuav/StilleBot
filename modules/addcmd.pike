//Note: Each special with the same-named parameter is assumed to use it in the same way.
//It's good to maintain this for the sake of humans anyway, but also the display makes
//this assumption, and has only a single description for any given name.
constant SPECIALS = ({
	({"!follower", ({"Someone follows the channel", "The new follower", ""}), "Stream support"}),
	({"!sub", ({"Someone subscribes for the first time", "The subscriber", "tier, multimonth"}), "Stream support"}),
	({"!resub", ({"Someone announces a resubscription", "The subscriber", "tier, months, streak, multimonth, msg"}), "Stream support"}),
	({"!subgift", ({"Someone gives a sub", "The giver", "tier, months, streak, recipient, multimonth, from_subbomb"}), "Stream support"}),
	({"!subbomb", ({"Someone gives random subgifts", "The giver", "tier, gifts"}), "Stream support"}),
	({"!cheer", ({"Any bits are cheered (including anonymously)", "The cheerer", "bits, msg, msgid"}), "Stream support"}),
	({"!cheerbadge", ({"A viewer attains a new cheer badge", "The cheerer", "level"}), "Stream support"}),
	({"!raided", ({"Another broadcaster raided you", "The raiding broadcaster", "viewers"}), "Stream support"}),
	({"!charity", ({"Someone donates to the charity you're supporting", "The donor", "amount, msgid"}), "Stream support"}),

	({"!channelonline", ({"The channel has recently gone online (started streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!channelsetup", ({"The channel is online and has recently changed its category/title/tags", "The broadcaster", "category, title, tag_names, ccls"}), "Status"}),
	({"!channeloffline", ({"The channel has recently gone offline (stopped streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!musictrack", ({"A track just started playing (see VLC integration)", "VLC", "desc, blockpath, block, track, playing"}), "Status"}),
	({"!pollbegin", ({"A channel poll just began", "The broadcaster", "title, choices, points_per_vote, choice_N_title"}), "Status"}),
	({"!pollended", ({"A channel poll just ended", "The broadcaster", "title, choices, points_per_vote, choice_N_title, choice_N_votes, choice_N_pointsvotes, winner_title"}), "Status"}),
	({"!predictionlocked", ({"A channel prediction no longer accepts entries", "The broadcaster", "title, choices, choice_N_title, choice_N_users, choice_N_points, choice_N_top_M_user, choice_N_top_M_points_used"}), "Status"}),
	({"!predictionended", ({"A channel prediction just ended", "The broadcaster", "title, choices, choice_N_title, choice_N_users, choice_N_points, choice_N_top_M_user, choice_N_top_M_points_used, choice_N_top_M_points_won, winner_*, loser_*"}), "Status"}),
	//Should this go into some other category?
	({"!timeout", ({"A user got timed out or banned", "The victim", "ban_duration"}), "Status"}),

	({"!giveaway_started", ({"A giveaway just opened, and people can buy tickets", "The broadcaster", "title, duration, duration_hms, duration_english"}), "Giveaways"}),
	({"!giveaway_ticket", ({"Someone bought ticket(s) in the giveaway", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_toomany", ({"Ticket purchase attempt failed", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_closed", ({"The giveaway just closed; people can no longer buy tickets", "The broadcaster", "title, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_winner", ({"A giveaway winner has been chosen!", "The broadcaster", "title, winner_name, winner_tickets, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_ended", ({"The giveaway is fully concluded and all ticket purchases are nonrefundable.", "The broadcaster", "title, tickets_total, entries_total, giveaway_cancelled"}), "Giveaways"}),

	({"!kofi_dono", ({"Donation received on Ko-fi.", "The broadcaster", "amount, msg, from_name"}), "Ko-fi"}),
	({"!kofi_member", ({"New monthly membership on Ko-fi.", "The broadcaster", "amount, msg, from_name, tiername"}), "Ko-fi"}),
	({"!kofi_shop", ({"Shop sale on Ko-fi.", "The broadcaster", "amount, msg, from_name, shop_item_ids"}), "Ko-fi"}),
});
constant SPECIAL_NAMES = (multiset)SPECIALS[*][0];
constant SPECIAL_PARAMS = ({
	({"tier", "Subscription tier - 1, 2, or 3 (Prime subs show as tier 1)"}),
	({"months", "Cumulative months of subscription"}), //TODO: Check interaction with multimonth
	({"streak", "Consecutive months of subscription. If a sub is restarted after a delay, {months} continues, but {streak} resets."}),
	({"recipient", "Display name of the gift sub recipient"}),
	({"multimonth", "Number of consecutive months of subscription given"}),
	({"msg", "Any message included with the sub/cheer/dono (blank if none)"}),
	({"msgid", "UUID of the message, suitable for replies etc"}),
	({"from_subbomb", "1 if the gift was part of a sub bomb, 0 if not"}),
	({"gifts", "Number of randomly-assigned gifts. Can be 1."}),
	({"bits", "Total number of bits cheered in this message"}),
	({"level", "New badge level, eg 1000 if the 1K bits badge has just been attained"}),
	({"viewers", "Number of viewers arriving on the raid"}),
	({"uptime", "Stream broadcast duration - use {uptime|time_hms} or {uptime|time_english} for readable form"}),
	({"uptime_hms", "(deprecated) Equivalent to {uptime|time_hms}"}),
	({"uptime_english", "(deprecated) Equivalent to {uptime|time_english}"}),
	({"category", "English name of the game or category being streamed in"}),
	({"tag_names", "Stream tags eg '[English], [FamilyFriendly]' - should be searched case insensitively"}),
	({"ccls", "Content classification labels eg '[ProfanityVulgarity], [ViolentGraphic]'"}),
	({"track", "Name of the audio file that's currently playing"}),
	({"block", "Name of the section/album/block of tracks currently playing, if any"}),
	({"blockpath", "Full path to the current block"}),
	({"desc", "Human-readable description of what's playing (block and track names)"}),
	({"playing", "1 if music is playing, or 0 if paused, stopped, disconnected, etc"}),
	({"title", "Title of the stream or giveaway (eg the thing that can be won)"}),
	({"duration", "How long the giveaway will be open (seconds; 0 means open until explicitly closed)"}),
	({"duration_hms", "(deprecated) Equivalent to {duration|time_hms}"}),
	({"duration_english", "(deprecated) Equivalent to {duration|time_english}"}),
	({"tickets_bought", "Number of tickets just bought (or tried to)"}),
	({"tickets_total", "Total number of tickets bought"}),
	({"tickets_max", "Maximum number of tickets any single user may purchase"}),
	({"entries_total", "Total number of unique people who entered"}),
	({"winner_name", "Name of the person who won - blank if no tickets purchased"}),
	({"winner_tickets", "Number of tickets the winner had purchased"}),
	({"giveaway_cancelled", "1 if the giveaway was cancelled (refunding all tickets), 0 if not (normal ending)"}),
	({"amount", "Total amount given (with currency eg '3 USD')"}),
	({"from_name", "Name (possibly username) of the Ko-fi supporter. Not (necessarily) a Twitch username."}),
	({"shop_item_ids", "Blank-separated list of ten-digit hexadecimal item IDs bought."}),
	({"tiername", "Ko-fi subscription tier (if applicable)"}),
	({"choices", "Number of choices in the poll"}),
	({"points_per_vote", "Channel points to buy a vote (0 if not available)"}),
	({"choice_N_title", "For each N from 1 to {choices}, the title of the Nth choice"}),
	({"choice_N_votes", "The number of votes that the Nth choice received"}),
	({"choice_N_pointsvotes", "The number of votes bought for Nth choice with points"}),
	({"choice_N_users", "The number of users who selected this choice"}),
	({"choice_N_points", "The total number of points spent on this choice"}),
	({"winner_title", "The title of the choice that had the most votes"}),
	({"choice_N_top_M_user", "Name of the Mth top user for the Nth choice (1 = biggest spender)"}),
	({"choice_N_top_M_points_used", "Number of points the Mth user for the Nth choice spent"}),
	({"choice_N_top_M_points_won", "Number of points the Mth user for the Nth choice won (0 if lost)"}),
	({"winner_*", "Same as choice_N_* for N == {winner}"}),
	({"loser_*", "Same as choice_N_* for N != {winner} if there were precisely two options"}),
	({"ban_duration", "Number of seconds the person got timed out for, or 0 for ban"}),
});

void update_aliases(object channel, string aliases, echoable_message response, multiset updates) {
	foreach (aliases / " ", string alias) {
		sscanf(alias, "%*[!]%[^#\n]", string safealias);
		if (safealias && safealias != "" && (!mappingp(response) || safealias != response->alias_of)) {
			string cmd = safealias + channel->name;
			if (response) channel->commands[safealias] = response;
			else m_delete(channel->commands, safealias);
			updates[cmd] = 1;
		}
	}
}

void purge(object channel, string cmd, multiset updates) {
	echoable_message prev = m_delete(channel->commands, cmd);
	m_delete(channel->path("commands"), cmd);
	if (prev) updates[cmd + channel->name] = 1;
	if (!mappingp(prev)) return;
	if (prev->alias_of) purge(channel, prev->alias_of, updates);
	if (prev->aliases) update_aliases(channel, prev->aliases, 0, updates);
	if (prev->automate) {
		//Clear out the timer
		mixed id = m_delete(G->G->autocommands, cmd + channel->name);
		if (id) remove_call_out(id);
	}
	if (prev->redemption) {
		channel->redemption_commands[prev->redemption] -= ({cmd});
		if (!sizeof(channel->redemption_commands[prev->redemption])) m_delete(channel->redemption_commands, prev->redemption);
		updates["rew " + prev->redemption] = 1;
	}
	mapping prefs = persist_status->path("userprefs", (string)channel->userid); //FIXME: Use channel instead of channel->userid
	if (prefs->notif_perms) foreach (prefs->notif_perms; string perm; array reasons) {
		int removed = 0;
		foreach (reasons; int i; mapping r) if (r->reason == "cmd:" + cmd) {reasons[i] = 0; removed = 1;}
		if (removed) {
			prefs->notif_perms[perm] = reasons - ({0});
			persist_status->save();
			G->G->update_user_prefs(channel->userid, (["notif_perms": prefs->notif_perms]));
		}
	}
}

//Recursively scan a response for all needed permissions
void scan_for_permissions(echoable_message response, multiset need_perms) {
	if (stringp(response)) {
		//TODO: If it's a slash command, record the permission needed for that command
		//This will require recognition of the voice in use.
	}
	if (arrayp(response)) scan_for_permissions(response[*], need_perms);
	if (!mappingp(response)) return;
	if (response->builtin) {
		object builtin = G->G->builtins[response->builtin];
		if (builtin->scope_required) need_perms[builtin->scope_required] = 1;
	}
	scan_for_permissions(response->message, need_perms);
	scan_for_permissions(response->otherwise, need_perms);
}

//Update (or delete) a per-channel echo command and save to disk
//TODO: Migrate this (and the two helpers above) into cmdmgr
//Then, with the chan_commands handlers also in cmdmgr, turn update_command into the
//one and only externally-callable entrypoint.
void make_echocommand(string cmd, echoable_message response, mapping|void extra)
{
	sscanf(cmd || "", "%[!]%s#%s", string pfx, string basename, string chan);
	object channel = G->G->irc->channels["#" + chan]; if (!channel) error("Requires a channel name.\n");
	if (basename == "") error("Requires a command name.\n");
	multiset updates = (<cmd>);
	purge(channel, pfx + basename, updates);
	if (sscanf(extra->?original || "", "%s#", string oldname)) purge(channel, oldname, updates); //Renaming a command requires removal of what used to be.
	//Purge any iteration variables that begin with ".basename:" - anonymous rotations restart on
	//any edit. This ensures that none of the anonymous ones hang around. Named ones are regular
	//variables, though, and might be shared, so we don't delete those.
	mapping vars = persist_status->has_path("variables", channel);
	string remove = "$." + basename + ":";
	if (vars) foreach (indices(vars), string v) if (has_prefix(v, remove)) {
		m_delete(vars, v);
		if (object handler = G->G->websocket_types->chan_variables)
			handler->update_one(channel->name, v - "$");
	}
	if (response) channel->commands[pfx + basename] = channel->path("commands")[pfx + basename] = response;
	if (mappingp(response) && response->aliases) update_aliases(channel, response->aliases, (response - (<"aliases">)) | (["alias_of": basename]), updates);
	foreach (extra->?cooldowns || ([]); string cdname; int cdlength) {
		//If the cooldown delay is shorter than the cooldown timeout,
		//reset the timeout. That way, if you accidentally set a command
		//to have a really long timeout (eg an hour when you wanted a
		//minute), lowering the timeout will fix it. Note that any
		//cooldowns no longer part of the command won't be purged; at
		//worst, they'll linger in G->G until restart - no big deal.
		int timeout = G->G->cooldown_timeout[cdname + channel->name] - time();
		if (cdlength && timeout > cdlength) G->G->cooldown_timeout[cdname + channel->name] = cdlength + time();
	}
	if (mappingp(response) && response->automate && G->G->stream_online_since[channel->login]) {
		//Start a timer
		//Currently, a simple hack: notify repeat.pike to recheck everything.
		function repeat = G->G->commands->repeat;
		if (repeat) function_object(repeat)->connected(channel->login);
	}
	if (mappingp(response) && response->redemption) {
		channel->redemption_commands[response->redemption] += ({basename});
		updates["rew " + response->redemption] = 1;
	}
	persist_config->save(); //FIXME-SEPCHAN: Save the specific channel's config
	if (object handler = G->G->websocket_types->chan_commands) {
		//If the command name starts with "!", it's a special, to be
		//sent out to "!!#channel" and not to "#channel".
		foreach (updates; cmd;) {
			//TODO maybe: If a command has been renamed, notify clients to rename, rather than
			//deleting the old and creating the new.
			if (has_prefix(cmd, "rew ")) continue;
			if (has_prefix(cmd, "!trigger#")) handler->send_updates_all("!" + cmd);
			else handler->update_one(pfx + pfx + channel->name, cmd);
			handler->send_updates_all(cmd);
		}
	}
	if (object handler = G->G->websocket_types->chan_pointsrewards) {
		//Similarly to the above, notify changes to any redemption invocations.
		foreach (updates; cmd;) {
			if (!has_prefix(cmd, "rew ")) continue;
			//update_one not currently supported on this socket, so just
			//send a full update and then stop (so we don't multiupdate).
			handler->send_updates_all(channel->name); break;
		}
	}
	if (function handler = response && G->G->specials_check_hooks) {
		//If this is a special that requires a hook, ensure that we have the hook.
		foreach (updates; cmd;) {
			if (sscanf(cmd, "!%s#", string spec) && G->G->SPECIALS_SCOPES[spec]) {
				handler(channel->config);
				break; //No need to update more than once - it'll check all the hooks
			}
		}
	}
	//If this uses any builtins that require permissions, and we don't have those, flag the user.
	multiset need_perms = (<>); scan_for_permissions(response, need_perms);
	if (sizeof(need_perms)) {
		mapping prefs = persist_status->path("userprefs", channel);
		multiset scopes = (multiset)(token_for_user_login(channel->name[1..])[1] / " ");
		foreach (need_perms; string perm;) {
			if (!scopes[perm]) {
				if (!prefs->notif_perms) prefs->notif_perms = ([]);
				prefs->notif_perms[perm] += ({([
					"desc": "Command - " + basename, //or special/trigger?
					"reason": "cmd:" + basename,
				])});
				persist_status->save();
				G->G->update_user_prefs(channel->userid, (["notif_perms": prefs->notif_perms]));
			}
		}
	}
}

protected void create(string name) {add_constant("make_echocommand", make_echocommand);}
