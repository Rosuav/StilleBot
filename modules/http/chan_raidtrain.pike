inherit http_websocket;
constant markdown = #"# Raid train organized by $$channel$$

## Raid train settings
{:#cfg_title}

<div id=cfg_description markdown=1>
$$description||The owner can fill out a description here.$$
</div>

Raid call: <textarea rows=4 cols=35 readonly id=cfg_raidcall></textarea>

Schedule:
* <span id=cfg_dates></span>
* Slot size: <span id=cfg_slotsize>1 hour</span>
* Unique streamers: <span id=streamer_count>(unknown)</span>

$$login_or_edit$$

## Schedule

This is who's going to be part of the train when. They may be live earlier than this. Slot requesting
is currently <span id=cfg_may_request>closed</span>.

Start   | End | Streamer | Requests | Notes
--------|-----|----------|----------|-------
loading | - | - | - | -
{:#timeslots}

> ### Configuration
> Plan out your raid train!
>
> Configuration | -
> - | -
> loading... | loading...
>
> [Save](:#save type=submit) [Close](:.dialog_close) [Reset schedule](:#reset_schedule)
{: tag=formdialog #configdlg}

<style>
time {font-weight: bold;}
#cfg_may_request {font-weight: bold;}
.avatar {max-width: 40px; vertical-align: middle; margin: 0 8px;}
#streamerslot_options {list-style-type: none;}
textarea {vertical-align: top;}
.revokeclaim {
	width: 20px; height: 23px;
	padding: 0;
}
tr.now {background: #a0f0c0;}
</style>

> ### Select Streamer
> Who should take time slot <span id=streamerslot_start></span> to <span id=streamerslot_end></span>?
>
> * loading...
> {:#streamerslot_options}
>
> [Select](:type=submit) [Close](:.dialog_close)
{: tag=formdialog #streamerslot_dlg}

<!-- -->

> ### Edit Notes
> Notes for time slot <span id=slotnotes_start></span> to <span id=slotnotes_end></span>
>
> Plain text (no Markdown).
>
> <textarea rows=5 cols=40 id=slotnotes_content></textarea>
>
> [Save](:type=submit) [Close](:.dialog_close)
{: tag=formdialog #slotnotes_dlg}
";

/* Raid train organization
- Maximum slots per streamer?
- Requests visible (y/n) - currently has to be Yes as claims are in the public info
- If the current time is within the raid train period, highlight "NOW".
- If the current user is on the schedule, highlight "YOU".

All configuration is stored in persist_status->raidtrain->USERID, with public
info (anything that can be shared with any client regardless of authentication)
in ->cfg; this should include the vast majority of information.

TODO: Now that slot width is configurable, test various combinations:
* Two-hour slots, starting on an even hour; starting on an odd hour
* Two-hour slots, 15-hour span
* Change width after schedule established
* Two-hour slots, move start by one hour
* Four-hour slots, shorten span by three hours, change slot size to two hours
* Etc

Next steps:
* Delayed-load list of who's currently live (regardless of schedule)
  - Can the raid finder grow a parameter to show "train=ownername"?

*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping trn = persist_status->path("raidtrain", (string)req->misc->channel->userid);
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view", "logged_in_as": (int)req->misc->session->user->?id]),
		"login_or_edit":
			req->misc->is_mod ? "[Edit configuration](:#editconfig)"
			: req->misc->session->user ? "Logged in as " + req->misc->session->user->display_name
			: "[Log in to make changes or request slots](:.twitchlogin)",
		"description": trn->cfg->?description, //Because it will be parsed as Markdown
	]) | req->misc->chaninfo);
}

void add_person(mapping people, int|string id) {
	id = (int)id; if (!id) return;
	mapping person = G->G->user_info[id];
	constant keys = ({"id", "login", "display_name", "profile_image_url"});
	if (person) people[(string)id] = mkmapping(keys, map(keys, person));
	else people[""][id] = 1;
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("raidtrain", (string)channel->userid, "cfg");
	//Populate a mapping of people info for the front end. It contains only what we
	//already have in cache.
	mapping people = (["": (<>)]);
	add_person(people, channel->userid); //First up, the owner. Nice and easy.
	//Then, everyone who's been allocated a slot.
	if (cfg->slots) foreach (cfg->slots, mapping slot) {
		add_person(people, slot->broadcasterid);
		//If you are a mod, also add info for everyone who's placed a request.
		//If you are not a mod but requests are public, do it anyway.
		//NOTE: Currently requests are always public.
		if (slot->claims) add_person(people, slot->claims[*]);
	}
	multiset still_need = m_delete(people, "");
	if (sizeof(still_need)) get_users_info((array)still_need)->then() {
		send_updates_all("control" + channel->name);
		send_updates_all("view" + channel->name);
	};
	return ([
		"cfg": cfg,
		"owner_id": channel->userid,
		"people": people,
		"is_mod": grp == "control",
		"desc_html": Tools.Markdown.parse(cfg->description || "", ([
			"renderer": Renderer, "lexer": Lexer,
		])),
	]);
}

mapping get_slot(object channel, mapping(string:mixed) msg) {
	mapping trn = persist_status->path("raidtrain", (string)channel->userid);
	array slots = trn->cfg->slots || ({ });
	if (!intp(msg->slotidx) || msg->slotidx < 0 || msg->slotidx >= sizeof(slots)) return 0;
	return slots[msg->slotidx];
}

void save_and_send(mapping(string:mixed) conn) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	persist_status->save();
	send_updates_all("control#" + chan);
	send_updates_all("view#" + chan);
}

void wscmd_streamerslot(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping slot = get_slot(channel, msg); if (!slot) return;
	if (!conn->is_mod) return; //Should streamers be allowed to revoke their own slots??
	slot->broadcasterid = (int)msg->broadcasterid;
	if (!slot->broadcasterid && msg->broadcasterlogin) {
		string login = replace(msg->broadcasterlogin, ({"https://", "www.twitch.tv/", "twitch.tv/"}), "");
		sscanf(login, "%s%*[/?]", login); //Remove any "?referrer=raid" or "/popout/chat" from the URL
		get_user_id(login)->then() {
			slot->broadcasterid = __ARGS__[0];
			save_and_send(conn);
		}->thencatch() { }; //TODO: Report errors back to the conn
		return;
	}
	//TODO: Recalculate stats like "number of unique streamers"
	if (slot->broadcasterid) get_user_info(slot->broadcasterid); //Populate cache just in case
	save_and_send(conn);
}

@"is_mod": void wscmd_revokeclaim(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping slot = get_slot(channel, msg); if (!slot) return;
	if (slot->claims) slot->claims -= ({(int)msg->broadcasterid});
	save_and_send(conn);
}

void wscmd_requestslot(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping slot = get_slot(channel, msg); if (!slot) return;
	if (slot->broadcasterid) return; //Don't request slots that are taken
	if (!slot->claims) slot->claims = ({ });
	int id = (int)conn->session->user->?id; if (!id) return;
	slot->claims ^= ({id});
	save_and_send(conn);
}

void wscmd_slotnotes(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping slot = get_slot(channel, msg); if (!slot) return;
	int userid = (int)conn->session->user->?id; if (!userid) return; //You don't have to be a mod, but you have to be logged in
	if (!stringp(msg->notes)) return;
	if (!conn->is_mod && slot->broadcasterid != userid) return; //If you're not a mod, you have to be the streamer in that slot.
	slot->notes = msg->notes;
	save_and_send(conn);
}

@"is_mod": void wscmd_resetschedule(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping trn = persist_status->path("raidtrain", (string)channel->userid);
	trn->cfg->slots = ({ });
	save_and_send(conn);
}

@"is_mod": void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping trn = persist_status->path("raidtrain", (string)channel->userid);
	foreach ("title description raidcall may_request" / " ", string str)
		if (msg[str]) trn->cfg[str] = msg[str];
	foreach ("startdate enddate slotsize" / " ", string num)
		if ((int)msg[num]) trn->cfg[num] = (int)msg[num];
	if (!(<"none", "any">)[trn->cfg->may_request]) trn->cfg->may_request = "none";

	if (trn->cfg->startdate && trn->cfg->enddate > trn->cfg->startdate) {
		int tcstart = trn->cfg->startdate, tcend = trn->cfg->enddate;
		int slotwidth = (trn->cfg->slotsize || 1) * 3600;
		array slots = trn->cfg->slots || ({ });
		//Trim the array down to the limits, stopping at any non-empty slot.
		//That way, if someone has claimed a slot, you won't unclaim it for
		//them simply by miskeying something. Or looking at it the other way
		//around: any reduction of the date span can be undone safely.
		//Note that it may be helpful to close slot requests if you need to
		//shift the start date/time by less than the slot width. If that ever
		//happens at all, that is, which it probably won't.
		int trim = 0;
		foreach (slots; int i; mapping s)
			if (s->end <= tcstart && !s->broadcasterid && (!s->claims || !sizeof(s->claims)))
				++trim;
			else break;
		if (trim) slots = slots[trim..];
		//If the first slot ends after the start date, but starts before it,
		//make it a short slot.
		if (sizeof(slots) && slots[0]->end > tcstart && slots[0]->start < tcstart)
			slots[0]->start = tcstart;
		//Now trim the end, similarly. The check is done in reverse though,
		//and no early break. And yes, that means we're doing less-than
		//comparisons in both - the above is removing anything that ends
		//before we start, this keeps anything that starts before we end.
		trim = -1;
		foreach (slots; int i; mapping s)
			if (s->start < tcend || s->broadcasterid || (s->claims && sizeof(s->claims)))
				trim = i;
		slots = slots[..trim];
		//Another possible short slot.
		if (sizeof(slots) && slots[0]->end > tcend && slots[0]->start < tcend)
			slots[0]->end = tcend;
		//Alright. Now to add slots. First, to properly define "left" and
		//"right", ensure that we have at least one slot.
		if (!sizeof(slots)) slots = ({(["start": tcstart, "end": min(tcstart + slotwidth, tcend)])});
		//Next, widen the first and/or last slots to the slot width. To
		//simplify the arithmetic, keep track of the slot start offset;
		//if all slots start precisely slotwidth apart, starting at the
		//start time, their Unix times will all be congruent modulo the
		//slotwidth.
		int slot_offset = tcstart % slotwidth; //Will often be zero.
		int wid = slots[0]->end - slots[0]->start;
		if (wid < slotwidth && slots[0]->start % slotwidth != slot_offset)
			//Expand the slot, to no more than...
			slots[0]->start -= min(0, //... its current size,
				slotwidth - wid, //... the size of one normal slot,
				slots[0]->start - tcstart, //... and not past the defined start.
			);
		//Same with the last slot.
		wid = slots[-1]->end - slots[-1]->start;
		if (wid < slotwidth && slots[0]->end % slotwidth != slot_offset)
			slots[0]->end += min(0, slotwidth - wid, tcend - slots[0]->end);
		//If the first slot doesn't begin on the slot offset, insert a short slot.
		if (slots[0]->start % slotwidth != slot_offset && slots[0]->start > tcstart) {
			//Always subtract a positive number of seconds, regardless of
			//whether the slot_offset is above or below start's offset.
			int delta = (slots[0]->start - slot_offset) % slotwidth;
			slots = ({(["start": slots[0]->start - delta, "end": slots[0]->start])}) + slots;
		}
		//Scan the slots for combinables. Two slots can be combined if:
		//1) They have the same broadcasterid
		//2) The combined width is no more than the slotwidth
		//3) The start is aligned on the slot_offset. It might be possible to
		//   allow these also if the preceding slot is full width (that is, if
		//   slot[n-1]->end - slot[n-1]->start == slotwidth), but it's probably
		//   not worth it. Just merge on the alignment. Most likely, these will
		//   be merging empty slots, so there'll be a sea of valid options to
		//   choose from, and forcing the alignment will make it tidier.
		if (slotwidth > 3600) { //Don't bother if we're on one-hour slots
			for (int i = 0; i < sizeof(slots) - 1; ++i) {
				mapping slot1 = slots[i], slot2 = slots[i + 1];
				if (slot1->broadcasterid != slot2->broadcasterid) continue; //Maybe if one is zero, merge anyway??
				if (slot2->end - slot1->start > slotwidth) continue;
				if ((slot1->start - slot_offset) % slotwidth) continue; //First one has to be aligned
				//Okay. Let's merge. Leave slot1 empty and merge into slot2; that
				//way, if the following slot could also merge in, we'll catch it.
				slot2->start = slot1->start;
				//It might not be fully appropriate, but combine the claims. Try
				//to keep them in order if possible, and avoid duplicates.
				array c1 = slot1->claims || ({ }), c2 = slot2->claims || ({ });
				slot2->claims = c1 + (c2 - c1);
				if (!slot2->broadcasterid) slot2->broadcasterid = slot1->broadcasterid; //In case we allow one-and-none merges
				//Combine notes. If both exist, separate with a newline, although
				//the main display will just show a space. But if they're the same,
				//one is enough.
				if (slot1->notes != slot2->notes)
					slot2->notes = String.trim((slot1->notes||"") + "\n" + (slot2->notes||""));
				//Done. Take out slot1, but leave a shim until we're done looping.
				slots[i] = 0;
			}
			slots -= ({0});
		}
		//Similarly, see if any slots need to be split. Things could get a bit messy
		//if you change from three-hour slots to two-hour, or vice versa, so... uhh,
		//don't do that when people have been assigned to slots.
		for (int i = 0; i < sizeof(slots); ++i) { //Don't foreach here - we may mutate the array
			mapping s = slots[i];
			if (s->end - s->start <= slotwidth) continue;
			mapping s2 = s | (["start": s->start + slotwidth]);
			s->end = s2->start;
			slots = slots[..i] + ({s2}) + slots[i+1..];
		}

		//Extend to the right. Each slot begins where the previous one left off,
		//is no more than slotwidth in width, and ends on the slot_offset. If we
		//end up mismatching with the configured end, make a short slot.
		int end = slots[-1]->end - (slots[-1]->end - slot_offset) % slotwidth;
		while (end < tcend) slots += ({([
			"start": slots[-1]->end,
			"end": min(end += slotwidth, tcend),
		])});
		//Rather than extend to the left, we build up a new set of pristine slots
		//from the start point, stopping once we don't need to make more.
		array fresh = ({ });
		for (int tm = tcstart; tm < slots[0]->start; tm += slotwidth) {
			fresh += ({([
				"start": tm, "end": min(tm + slotwidth, slots[0]->start),
			])});
		}
		//Whew. That's a lot of chopping and changing, most of which will probably
		//never happen. Recommendation: Only ever expand/contract in multiples of
		//the slot width, never change the slot width, and all should be easy.
		//Also: most of the above code is probably buggy. I have not tested it at
		//all thoroughly.
		trn->cfg->slots = fresh + slots;
	}
	save_and_send(conn);
}
