import {lindt, replace_content as set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, IMG, INPUT, LABEL, LI, OPTION, SELECT, SPAN, TD, TEXTAREA, TIME, TR} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

let day_based = false;

const may_request_options = {
	none: "closed", any: "open",
	//TODO: Have an option for "approved persons" or "team members" or something
	//TODO maybe: Have an option for "streamers", defined by "people with at least one VOD, at least a day old"?
	//That would effectively require 2FA.
};

const pad = n => ("0" + n).slice(-2);
//Note that the user-facing controls show local time, but the server works in UTC.
//Unless we're in day mode, in which case everyone sees UTC.
function makedate(val, id) {
	const opts = [];
	for (let hour = 0; hour < 24; ++hour) opts.push(OPTION(pad(hour)));
	//Weird hack: For the end date, when working day-based, subtract one second
	//so it shows inclusive-inclusive, the way humans want to see it.
	const date = val ? new Date(val * 1000 - (day_based && id === "edit_enddate")) : new Date();
	const get = day_based ? "getUTC" : "get";
	return [
		INPUT({id, type: "date", value: date[get + "FullYear"]() + "-" + pad(date[get + "Month"]()+1) + "-" + pad(date[get + "Date"]())}),
		!day_based && SELECT({id: id + "_time", value: pad(date[get + "Hours"]())}, opts),
		!day_based && ":00",
	];
}
function getdate(elem) {
	if (elem.value === "") return 0;
	//In day mode, ignore any time, and use UTC. Also reverse the "subtract one
	//second" hack from above, so that the back end can find the right end mark.
	const date = day_based ? new Date(elem.value) : new Date(elem.value + "T" + DOM("#" + elem.id + "_time").value + ":00");
	return Math.floor((+date)/1000 + (day_based && elem.id === "edit_enddate"));
}

const cfg_vars = [
	{key: "title", label: "Title", render: (value, id) => INPUT({value, id, size: 40})},
	{key: "description", label: "Description\n(Markdown)", render: (val, id) => TEXTAREA({id, rows: 4, cols: 35}, val)},
	{key: "raidcall", label: "Raid call", render: (val, id) => TEXTAREA({id, rows: 4, cols: 35}, val)},
	{key: "startdate", label: "Start date", render: makedate, getvalue: getdate},
	{key: "enddate", label: "End date", render: makedate, getvalue: getdate},
	{key: "slotsize", label: "Slot size", render: (value, id) => SELECT({value, id}, [
		OPTION({value: "1"}, "One hour"),
		OPTION({value: "2"}, "Two hours"),
		OPTION({value: "3"}, "Three hours"),
		OPTION({value: "4"}, "Four hours"),
		OPTION({value: "8"}, "Eight hours"),
		OPTION({value: "12"}, "Twelve hours"),
		OPTION({value: "24"}, "One day"),
	])},
	{key: "may_request", label: "Slot requests", render: (value, id) => SELECT({value, id},
		Object.entries(may_request_options).map(([k,v]) => OPTION({value: k}, v)))},
];

function DATE(d, timeonly) {
	if (!d) return "(unspecified)";
	const date = new Date(d * 1000);
	const get = day_based ? "getUTC" : "get";
	let day = date[get + "Date"]();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English. The hover will be in your locale.
		!timeonly && "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date[get + "Month"]()] + " " + day,
		!timeonly && !day_based && ", ",
		!day_based && pad(date[get + "Hours"]()) + ":00",
	]);
}

let need_follow_check = false, followed_casters = { };
function channel_profile(chan) {
	if (!chan) return "";
	if (typeof followed_casters[chan.id] === "undefined") need_follow_check = true;
	return [
		A({href: "https://twitch.tv/" + chan.login, target: "_blank"}, [
			IMG({className: "avatar", src: chan.profile_image_url}),
			chan.display_name,
		]),
		//If you ARE following the person, it'll have a string there, otherwise the integer zero
		typeof followed_casters[chan.id] === "number" && SPAN({class: "new_frond", title: "Might be a new frond!"}, " \u{1f334}"),
	];
}

//HACK: Make this available in the console, since I don't have a proper button anywhere
window.bulk_manage = function() {
	DOM("#all_slots").value = slots.map(slot => {
		const person = people[slot.broadcasterid] || {};
		const name = person.login || person.display_name || slot.broadcasterid || "";
		const notes = (slot.notes||"").replaceAll("\n", " "); //Yes, you lose information if you had newlines, but they wouldn't render anyway.
		if (notes !== "") return name + " " + notes;
		return name;
	}).join("\n");
	DOM("#bulkmgmt_dlg").showModal();
};
on("submit", "#bulkmgmt_dlg form", e => {
	DOM("#all_slots").value.split("\n").forEach((line, slotidx) => {
		const space = line.indexOf(" ");
		const name = space === -1 ? line : line.slice(0, space);
		const notes = space === -1 ? "" : line.slice(space + 1);
		if (name === "") ws_sync.send({cmd: "streamerslot", slotidx, broadcasterid: 0});
		else ws_sync.send({cmd: "streamerslot", slotidx, broadcasterlogin: name});
		ws_sync.send({cmd: "slotnotes", slotidx, notes});
	});
});

let owner_id = { }, slots = [], people = { }, is_mod = false, may_request = "none", online_streams = { };
export function render(data) {
	day_based = data.cfg.slotsize === 24;
	set_content("#configdlg tbody", cfg_vars.map(v => {
		const input = v.render(data.cfg[v.key] || "", "edit_" + v.key);
		//Split the label into lines as required
		const lbl = v.label.split("\n").map((l,i) => i ? [BR(), l] : l);
		return TR([
			TD(LABEL({for: input.id}, lbl)),
			TD(input),
		]);
	}));
	if (data.desc_html) DOM("#cfg_description").innerHTML = data.desc_html;
	set_content("#cfg_title", data.cfg.title || "Raid train settings");
	DOM("#cfg_raidcall").value = data.cfg.raidcall || "";
	set_content("#cfg_dates", [
		"From ", DATE(data.cfg.startdate),
		//As above, hack the end date backwards by one second in day mode, so we get inc-inc range display.
		" until ", DATE(data.cfg.enddate - day_based),
	]);
	if (day_based) set_content("#cfg_slotsize", "Day");
	else set_content("#cfg_slotsize", (data.cfg.slotsize||1) + " hour(s)");
	set_content("#cfg_may_request", may_request_options[data.cfg.may_request||"none"]);
	people = data.people; owner_id = data.owner_id; is_mod = data.is_mod;
	may_request = data.cfg.may_request; online_streams = data.online_streams;
	if (data.slots) {slots = data.slots; update_schedule();}
	const casters = data.cfg.all_casters || [];
	set_content("#streamer_count", ""+casters.length);
	set_content("#raidfinder_link a", "See all streamers currently live for " + data.cfg.title).href = "/raidfinder?train=" + data.owner_id; //Might be nice to use the name, but both work
}

function update_schedule() {
	let lastdate = 0;
	function abbrevdate(d) {
		//If the two dates are on the same day (simplified down to just "same
		//day of month" since it'll be progressing sequentially), leave out the
		//date and just show the time. The hover still has everything.
		const date = new Date(d * 1000).getDate();
		const sameday = date === lastdate;
		lastdate = date;
		return DATE(d, sameday);
	}
	const self = ws_sync.get_userid();
	const now = +new Date / 1000;
	const have_requests = may_request !== "none" || is_mod;
	DOM("#timeslots thead th:nth-of-type(3)").hidden = have_requests ? "" : "hidden";
	set_content("#timeslots tbody", slots.map((slot,i) => TR(
	{class: slot.start <= now && slot.end > now ? "now" :
		slot.broadcasterid === self ? "your_slot" : ""
	}, [
		TD({colspan: day_based ? 2 : 1}, abbrevdate(slot.start)),
		!day_based && TD(DATE(slot.end, 1)),
		TD([
			online_streams[slot.broadcasterid] && online_streams[slot.broadcasterid].online &&
				SPAN({class: "recording", title: "Live now!"}, "⏺"),
			channel_profile(people[slot.broadcasterid]),
		]),
		have_requests && TD([
			!slot.broadcasterid && slot.claims && DIV(slot.claims.map(id => DIV(channel_profile(people[id])))),
			" ",
			is_mod ? BUTTON({class: "streamerslot", "data-slotidx": i}, "Manage")
			: !self ? ""
				//TODO: Handle may_request other than none/any
			: !slot.broadcasterid && may_request === "any" ?
				BUTTON({class: "requestslot", "data-slotidx": i},
					slot.claims && slot.claims.indexOf(self) > -1 ? "Unrequest" : "Request")
			: "",
		]),
		TD([
			slot.notes || "",
			(is_mod || slot.broadcasterid === self) &&
				BUTTON({class: "slotnotes", "data-slotidx": i, title: "Edit notes"}, "✍"),
		]),
		TD({class: "schedule"}, (slot.schedule || []).map(sched => {
			if (sched.cancelled_until) return null;
			const online = new Date(sched.start_time);
			const offline = new Date(sched.end_time);
			//NOTE: The end_time can be null, resulting in offline being zero.

			//In day mode, see if the scheduled stream overlaps with the given day in the
			//viewer's timezone. Otherwise, see if it overlaps in absolute time.
			let start = slot.start, end = slot.end;
			if (day_based) {
				start += new Date(start * 1000).getTimezoneOffset() * 60;
				end += new Date(end * 1000).getTimezoneOffset() * 60;
			}
			let need_day = false;
			function abbrevtime(ts, date) {
				if (day_based && (date/1000 < start || date/1000 >= end)) need_day = true;
				return TIME({datetime: ts, title: date.toLocaleString()}, [
					need_day && "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + date.getDate() + ", ",
					pad(date.getHours()) + ":" + pad(date.getMinutes()),
				]);
			}
			if (online/1000 < end && (!sched.end_time || offline/1000 >= start)) return DIV([
				//choc.PRE(JSON.stringify(sched, null, 4))
				abbrevtime(sched.start_time, online),
				" to ",
				sched.end_time ? abbrevtime(sched.end_time, offline) : "whenever",
			]);
		})),
	])));
	if (need_follow_check) {need_follow_check = false; ws_sync.send({cmd: "checkfollowing"});}
}
setInterval(update_schedule, 60000); //Repaint every minute to update the "now" marker

let selectedslot = { }, slotidx = -1;
on("click", ".streamerslot", e => {
	selectedslot = slots[slotidx = (e.match.dataset.slotidx|0)];
	const seen = { };
	function RB(person, deletable) {
		if (!person || seen[person.id]) return "";
		seen[person.id] = 1;
		return LI([
			LABEL([ //FIXME: Labelling the input with an anchor creates a click conflict.
				INPUT({type: "radio", name: "slotselection", value: person.id}),
				channel_profile(person),
			]),
			" ",
			deletable && BUTTON({type: "button", class: "revokeclaim", "data-broadcasterid": person.id, title: "Remove request"}, "🗑"),
		]);
	}
	set_content("#streamerslot_options", [
		RB(people[selectedslot.broadcasterid]),
		RB(people[owner_id]),
		//TODO: This doesn't work if you have no claims. May need an explicit call to get profile for self.
		RB(people[ws_sync.get_userid()]),
		selectedslot.claims && selectedslot.claims.map(id => RB(people[id], 1)),
		LI([
			//Note that the checkbox has no label. Clicking the text puts the cursor in the text field.
			INPUT({type: "radio", name: "slotselection", value: "login", id: "streamerslot_loginrb"}),
			LABEL({style: "display: inline-block; vertical-align: top"}, [
				"Enter user name or Twitch link:", BR(),
				INPUT({id: "streamerslot_login", size: 30, autocomplete: "off"}),
			]),
		]),
		LI(LABEL([INPUT({type: "radio", name: "slotselection", value: "0"}),
			"Nobody (for now)"])),
	]);
	set_content("#streamerslot_start", DATE(selectedslot.start));
	set_content("#streamerslot_end", DATE(selectedslot.end));
	DOM("#streamerslot_login").value = "";
	const rb = DOM('[name="slotselection"][value="' + selectedslot.broadcasterid + '"]')
		|| DOM('[name="slotselection"][value="0"]');
	rb.checked = true;
	DOM("#streamerslot_dlg").showModal();
});

on("submit", "#streamerslot_dlg form", e => {
	const rb = DOM("#streamerslot_options input[type=radio]:checked");
	const broadcasterid = rb ? rb.value : "0"; //Shouldn't ever be absent but whatever
	if (broadcasterid === "login") ws_sync.send({cmd: "streamerslot", slotidx, broadcasterlogin: DOM("#streamerslot_login").value});
	else ws_sync.send({cmd: "streamerslot", slotidx, broadcasterid});
	selectedslot = { }; slotidx = -1;
});

on("click", ".revokeclaim", simpleconfirm("Revoke this claim?", e =>
	ws_sync.send({cmd: "revokeclaim", slotidx, broadcasterid: e.match.dataset.broadcasterid})));

on("input", "#streamerslot_login", e => DOM("#streamerslot_loginrb").checked = true);

on("click", ".requestslot", e => ws_sync.send({cmd: "requestslot", slotidx: e.match.dataset.slotidx|0}));

on("click", ".slotnotes", e => {
	selectedslot = slots[slotidx = (e.match.dataset.slotidx|0)];
	DOM("#slotnotes_content").value = selectedslot.notes || "";
	set_content("#slotnotes_start", DATE(selectedslot.start));
	set_content("#slotnotes_end", DATE(selectedslot.end));
	DOM("#slotnotes_dlg").showModal();
});

on("submit", "#slotnotes_dlg form", e => {
	ws_sync.send({cmd: "slotnotes", slotidx, notes: DOM("#slotnotes_content").value});
	selectedslot = { }; slotidx = -1;
});

on("submit", "#configdlg form", e => {
	const el = e.match.elements;
	const msg = {cmd: "update"};
	cfg_vars.forEach(v => {
		const elem = el["edit_" + v.key];
		msg[v.key] = v.getvalue ? v.getvalue(elem) : elem.value;
	});
	ws_sync.send(msg);
});

on("click", "#reset_schedule", simpleconfirm(
	"Resetting the schedule removes all slots, assignments, requests, notes, etc. This cannot be undone!",
	e => ws_sync.send({cmd: "resetschedule"})));

export function sockmsg_checkfollowing(msg) {
	followed_casters = msg.casters;
	update_schedule();
}
