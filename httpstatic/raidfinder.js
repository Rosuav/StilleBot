import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BR, BUTTON, DIV, IMG, INPUT, UL, LABEL, LI, SPAN} = choc; //autoimport

const chat_restrictions = [
	["emote_mode", "Emote-only mode", 1],
	["follower_mode", s => s.follower_mode_duration
		? "Follower-only mode (" + s.follower_mode_duration + " minutes)"
		: "Follower-only mode"
	],
	["slow_mode", s => "Slow mode (" + s.slow_mode_wait_time + " seconds)", 1],
	["subscriber_mode", "Subscriber-only mode"],
	["unique_chat_mode", "Unique chat (R9k) mode", 1],
];
const want_streaminfo = { }; //Channel IDs that we don't yet know about chat restrictions for

const sortfunc = {
	Magic: (s1, s2) => s2.recommend - s1.recommend,
	Viewers: (s1, s2) => s1.viewer_count - s2.viewer_count,
	Category: (s1, s2) => s1.category.localeCompare(s2.category),
	Uptime: (s1, s2) => new Date(s2.started_at) - new Date(s1.started_at),
	Raided: (s1, s2) => (s1.raids[s1.raids.length-1]||"").localeCompare(s2.raids[s2.raids.length-1]||""),
	"Channel Creation": (s1, s2) => s1.created_at.localeCompare(s2.created_at),
	"Follow Date": (s1, s2) => s1.order - s2.order,
	"Name": (s1, s2) => s1.user_name.localeCompare(s2.user_name),
}
let lastsort = "";
on("click", "#sort li", e => {
	const pred = sortfunc[e.match.innerText];
	if (!pred) {console.error("No predicate function for " + e.match.innerText); return;}
	if (e.match.innerText === lastsort) follows.reverse(); //Poor man's sort order toggle
	else {follows.sort(pred); lastsort = e.match.innerText;}
	document.querySelectorAll("#sort li.current").forEach(el => el.classList.remove("current"));
	e.match.classList.add("current");
	follows.forEach((stream, idx) => stream.element.style.order = idx);
});

DOM("#legend").onclick = e => DOM("#infodlg").showModal();

function hms(time) {
	if (time < 60) return time + " seconds";
	const hh = Math.floor((time / 3600) % 24);
	const mm = ("0" + Math.floor((time / 60) % 60)).slice(-2);
	const ss = ("0" + Math.floor(time % 60)).slice(-2);
	let ret = mm + ":" + ss;
	if (time >= 3600) ret = hh + ":" + ret;
	if (time >= 86400) ret = Math.floor(time / 86400) + " days, " + ret;
	return ret;
}
function uptime(startdate) {return hms(Math.floor((new Date() - new Date(startdate)) / 1000));}

async function show_vod_lengths(userid, vodid, startdate) {
	set_content("#is_following", "");
	set_content("#chat_restrictions", "");
	set_content("#vods", LI("... loading VODs ..."));
	DOM("#vodlengths").showModal();
	const info = typeof userid === "object" ? userid :
		await (await fetch(`/raidfinder?for=${on_behalf_of_userid}&streamlength=${userid}&ignore=${vodid}`)).json();
	console.log("VODs:", info);

	if (info.is_following) {
		if (info.is_following.followed_at) set_content("#is_following", [
			B(info.is_following.from_name),
			" has been following ",
			B(info.is_following.to_name),
			" for " + info.is_following.follow_length + ".",
		]).className = "is_following";
		else set_content("#is_following",
			"Not currently followed, might be a new frond!",
		).className = "not_following";
	}

	const s = info.chat_settings || { };
	set_content("#chat_restrictions", chat_restrictions.map(([key, desc]) => 
		s[key] ? LI(typeof desc === "string" ? desc : desc(s)) : ""
	));

	if (!info.max_duration || !info.vods.length) {
		//Might be there are no VODs recorded (maybe the streamer has them disabled).
		set_content("#vods", LI("No VODs found, unable to estimate stream duration"));
		return;
	}
	const uptime = startdate ? Math.floor((new Date() - new Date(startdate)) / 1000) : info.max_duration;
	const scale = Math.max(info.max_duration, uptime);
	if (startdate) info.vods.unshift({duration_seconds: uptime, week_correlation: 0});
	set_content("#vods", info.vods.map(vod => {
		let date = "Current stream";
		if (vod.created_at) {
			const tm = new Date(vod.created_at);
			date = "Sun Mon Tue Wed Thu Fri Sat Sun".split(" ")[tm.getDay()] + " " +
				"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[tm.getMonth()] + " " +
				tm.getDate() + ", " +
				((tm.getHours() % 12) || 12) + ":" +
				("0" + tm.getMinutes()).slice(-2) +
				(tm.getHours() >= 12 ? "pm" : "am");
		}
		const li = LI(hms(vod.duration_seconds) + " - " + date);
		//Based on the week_correlation, figure out a colour to fill the bar with.
		const correlation = vod.week_correlation / (604800/2); //Correlation is scaled to half a week
		const paleness = Math.floor(correlation * 160 + 64);
		let gradient = `rgb(${paleness}, 255, ${paleness}) `;
		if (!vod.created_at) gradient = "#fcf "; //For the current VOD line, show it in pale red instead
		const up = uptime / scale * 100, dur = vod.duration_seconds / scale * 100;
		if (uptime < vod.duration_seconds) {
			//Show the vod-length colour with an uptime hairline across it
			gradient += `${up}%, red ${up}% ${up + 0.25}%, ${gradient} ${up + 0.25}% ${dur}%, #ddd ${dur}%`;
		} else {
			//Show the uptime hairline after the vod-length colour stops
			gradient += `${dur}%, #ddd ${dur}% ${up}%, red ${up}% ${up + 0.25}%, #ddd ${up + 0.25}%`;
		}
		li.style.background = "linear-gradient(to right, " + gradient + ")";
		return li;
	}));
}

on("click", "#mydetails", e => show_vod_lengths(on_behalf_of_userid, your_stream && your_stream.id, your_stream && your_stream.started_at));

let precache_timer = 0;
function precache_streaminfo() {
	const now = Math.floor(new Date / 1000) - 86400;
	const streams = [], weights = [];
	let sum = 0;
	for (let stream of follows) {
		const cacheage = now - want_streaminfo[stream.user_id];
		if (cacheage <= 0) continue;
		weights.push(sum += cacheage);
		streams.push(stream);
	}
	if (!streams.length) return clearInterval(precache_timer); //Nothing to look up? We're done.
	//Pick a weighted random selection, such that older cache entries are picked
	//more frequently. Something not in cache at all will have a weight equal to
	//the time since 1970, which is a lot of weight. Quite a lot.
	const sel = Math.floor(Math.random() * sum);
	const index = weights.findIndex(w => w > sel);
	if (index === -1) index = 0; //Shouldn't happen. Whatever.
	const stream = streams[index];
	fetch(`/raidfinder?for=${on_behalf_of_userid}&streamlength=${stream.user_id}&ignore=${stream.id}&precache=1`);
}

function low_show_raids(raids) {
	const scrollme = set_content("#raids ul", raids).parentElement;
	DOM("#raids").showModal();
	scrollme.scrollTop = scrollme.scrollHeight;
}

function show_raids(raids) {
	low_show_raids(raids.map(desc => LI(
		{className: desc[0] === '>' ? "raid-outgoing" : "raid-incoming"},
		desc.slice(1),
	)));
}

function show_all_raids() {
	low_show_raids(all_raids.map(raid => {
		const tail = [" at ", new Date(raid.time * 1000).toLocaleDateString()];
		if (raid.viewers > 0) tail.push(` with ${raid.viewers} viewers`);
		return raid.outgoing
		? LI({className: "raid-outgoing"}, [raid.from, " raided ", A({href: "https://twitch.tv/" + raid.to}, raid.to), ...tail])
		: LI({className: "raid-incoming"}, [A({href: "https://twitch.tv/" + raid.from}, raid.from), " raided ", raid.to, ...tail]);
		//TODO: Change to URLs of "raidfinder?login=" + raid.{from|to} but only if the stream is live now
	}));
}
DOM("#allraids").onclick = show_all_raids;

function edit_notes(stream) {
	set_content("#notes_about_channel", [
		"Channel notes: ",
		adornment(stream.broadcaster_type),
		stream.user_name,
		BR(),
		IMG({className: "avatar", src: stream.profile_image_url}),
	]);
	DOM("#editnotes textarea").value = stream.notes || "";
	DOM("#editnotes").returnValue = "close";
	DOM("#editnotes").stream = stream;
	DOM("#editnotes").showModal();
}

DOM("#editnotes").onclose = e => {
	if (e.currentTarget.returnValue !== "save") return;
	const stream = e.currentTarget.stream;
	const newnotes = DOM("#editnotes textarea").value;
	fetch("/raidfinder", {
		method: "POST",
		headers: {"content-type": "application/json"},
		body: JSON.stringify({id: +stream.user_id, notes: newnotes}),
	}).then(res => {
		if (!res.ok) {console.error("ERROR SAVING NOTES"); console.error(res);} //This could include a 401 if the login has expired
		if (!stream.element) return res.json(); //Changing the highlights gets an actual response
		const btn = stream.element.querySelector(".notes");
		if (newnotes === "") {btn.className = "notes absent"; set_content(btn, "\u270D");}
		else {btn.className = "notes present"; set_content(btn, "\u270D \u2709");}
		stream.notes = newnotes;
	}).then(response => {
		if (!response) return; //Stream-specific notes have no response body.
		highlights = response.highlights;
		//The highlight IDs are there too if needed.
		console.log(response.highlightids);
	});
}

DOM("#highlights").onclick = () => {
	set_content("#notes_about_channel", [
		"List channels here, separated by spaces or on separate lines. They",
		BR(),
		"will be visibly highlighted next time you open this raid finder."
	]);
	DOM("#editnotes textarea").value = highlights || "";
	DOM("#editnotes").returnValue = "close";
	DOM("#editnotes").stream = {user_id: 0};
	DOM("#editnotes").showModal();
}

const tag_element = { };
function update_tag_display() {
	set_content("#tags ul", [
		Object.keys(tag_prefs).sort().map(tag => tag_element[tag] = LI({
			"data-tagid": tag, //Tags are identified by their text, there's no separate UUID
			className: "tagpref" + (tag_prefs[tag] || 0)
		}, [
			BUTTON({className: "disliketag"}, "-"),
			BUTTON({className: "liketag"}, "+"),
			" ",
			SPAN({className: "tag"}, tag),
		])),
		LI({"data-tagid": "", className: "tagpref0"}, [
			BUTTON({className: "disliketag"}, "-"),
			BUTTON({className: "liketag"}, "+"),
			" ",
			LABEL(["Add new tag: ", INPUT({id: "newtagname", size: 20})]),
		]),
	]);
}
function update_tagpref(e, delta) {
	const tagid = e.match.closest("li").dataset.tagid || DOM("#newtagname").value;
	if (tagid === "") return; //Should we say something if the user leaves the input blank?
	console.log(tagid);
	const newpref = (tag_prefs[tagid]|0) + delta;
	console.log("New pref:", tag_prefs[tagid], " + ", delta, " = ", newpref);
	if (newpref > MAX_PREF || newpref < MIN_PREF) return;
	fetch("/raidfinder", {
		method: "POST",
		headers: {"content-type": "application/json"},
		body: JSON.stringify({id: -1, notes: tagid + " " + newpref}),
	}).then(res => res.json()).then(resp => {
		//Update ALL prefs on any change. Helps to minimize desyncs.
		tag_prefs = resp.prefs;
		console.log("New prefs:", tag_prefs);
		update_tag_display();
	});
}
on("click", ".liketag", e => update_tagpref(e, 1));
on("click", ".disliketag", e => update_tagpref(e, -1));

//TODO: Have a quick way to promote/demote a tag that you see in your follow list
DOM("#tagprefs").onclick = () => {update_tag_display(); DOM("#tags").showModal();}

function adornment(type) {
	if (type === "partner") {
		//Return a purple check mark \u2705
		return SPAN({className: "bcasttype partner"}, "\xA0\u2714 ");
	}
	else if (type === "affiliate") {
		//Return a circle? \u2B24
		return SPAN({className: "bcasttype affiliate"}, "\xA0 \xA0 \xA0");
	}
}

function describe_uptime(stream, el) {
	if (!el) el = SPAN({
		className: "uptime",
		onclick: () => show_vod_lengths(stream.user_id, stream.id, stream.started_at),
	});
	//If no chat restrictions seen in cache, add a0f0c0 badge. If some seen, add ff0 badge.
	let restrictions = null;
	const cached = stream.chanstatus ? stream.chanstatus.cache_time : 0;
	want_streaminfo[stream.user_id] = cached;
	if (cached > new Date/1000 - 86400 * 14) {
		const set = stream.chanstatus.chat_settings;
		let warn = false, info = false;
		chat_restrictions.forEach(r => {if (set[r[0]]) {
			if (r[2]) info = true; else warn = true;
		}});
		if (warn)
			//There's at least one notable chat restriction set. Give a warning.
			restrictions = SPAN({className: "warning", title: "Chat restrictions active, click for details"}, "*");
		else if (info)
			//There's none of the serious ones, but at least one mild chat restriction set. Give an informational.
			restrictions = SPAN({className: "info", title: "Mild chat restrictions active, click for details"}, "*");
		else
			//No chat restrictions, and we saw this recently so it's probably safe to trust it.
			restrictions = SPAN({className: "allclear", title: "No chat restrictions active (click to recheck)"}, "*");
	}
	//If we have follower info for the one we're tracking, and they're not
	//following this channel, show a "new frond" icon (a palm tree).
	//This won't show on initial load but may show up if random loads happen.
	let frond = null;
	const fol = stream.chanstatus?.is_following;
	if (fol && +fol.from_id === on_behalf_of_userid && !fol.followed_at)
		frond = SPAN({className: "new_frond", title: "Might be a new frond! (click to confirm)"}, "\u{1f334}");

	//TODO: Colour the background of the word "Uptime" based on how close we are to the
	//average VOD duration.
	return set_content(el, [frond, restrictions, "Uptime " + uptime(stream.started_at)]);
}

function build_follow_list() {
	console.log(follows);
	function describe_raid(raids) {
		if (!raids.length) return null;
		const raiddesc = raids[raids.length - 1];
		const outgoing = raiddesc[0] === '>';
		return SPAN({
			className: outgoing ? "raid-outgoing" : "raid-incoming",
			onclick: () => show_raids(raids),
		}, [
			!outgoing && IMG({className: "emote", src: "https://static-cdn.jtvnw.net/emoticons/v1/62836/1.0"}), //twitchRaid
			/^[-0-9]+/.exec(raiddesc.slice(1))[0], //Just the date
			outgoing && IMG({className: "emote", src: "https://static-cdn.jtvnw.net/emoticons/v1/62836/1.0"}),
		]);
	}
	function describe_notes(stream) {
		const attr = {
			className: "notes absent",
			title: "Notes about this channel",
			type: "button",
			onclick: () => edit_notes(stream),
		};
		if (stream.notes) {
			attr.className = "notes present";
			return BUTTON(attr, "\u270D \u2709");
		}
		return BUTTON(attr, "\u270D");
	}
	function describe_size(stream) {
		//Pick a CSS class based on the size of your stream (right now) and this stream (right now).
		//Would be kinda nice if we could respect ongoing average viewership - particularly for a
		//stream that started 2 minutes ago, but will later on become way big. Also, if we have our
		//own viewership stats, it could be useful to have a 25/75 percentile mark and say "anyone
		//within this range is samesize".
		if (!your_stream) return ""; //If you're not online, show no size info
		const you = your_stream.viewer_count, them = stream.viewer_count;
		const dir = you > them ? "smaller" : "larger";
		const abs = you > them ? you - them : them - you;
		const rel = you > them ? you / them : them / you;
		if (abs < 2) return "samesize"; //2 viewers and 1 viewer are the same size, not "half my size"
		//Should these thresholds be tweaked based on the absolute difference?
		if (rel < 1.25) return "samesize";
		if (rel < 1.5) return "slightly_" + dir;
		if (rel < 2) return dir;
		return "much_" + dir;
	}
	function show_magic(magic) {
		const parts = [];
		for (let id in magic) {
			parts.push({score: Math.abs(magic[id]) * 2 + (magic[id] > 0), elem: LI([
				SPAN({className: "magic-score"}, ""+magic[id]),
				SPAN(" " + id),
			])});
		}
		parts.sort((a, b) => b.score - a.score);
		return UL(parts.map(p => p.elem));
	}
	function raidbtn(stream) {
		return BUTTON({class: "raidbtn", "data-target": stream.user_name, "data-targetid": stream.user_id,
			title: "Raid " + stream.user_name + "!"},
				IMG({class: "emote", src: "https://static-cdn.jtvnw.net/emoticons/v1/62836/1.0"}));
	}
	set_content("#streams", follows.map(stream => stream.element = DIV({className: describe_size(stream) + " " + (stream.highlight ? "highlighted" : "")},
		mode === "allfollows" ? [
			//Cut-down view for channels that might be offline.
			A({href: "https://twitch.tv/" + stream.login}, [
				IMG({className: "avatar", src: stream.profile_image_url}),
				adornment(stream.broadcaster_type),
				stream.user_name,
			]),
			describe_notes(stream),
		] : [
			A({href: stream.url}, IMG({src: stream.thumbnail_url.replace("{width}", 320).replace("{height}", 180)})),
			DIV({className: "inforow"}, [
				DIV({className: "img"}, A({href: stream.url}, IMG({className: "avatar", src: stream.profile_image_url}))),
				UL([
					LI([A({href: stream.url}, [adornment(stream.broadcaster_type), stream.user_name]), " - ", B(stream.category)]),
					LI({className: "streamtitle"}, stream.title),
					LI([describe_uptime(stream), ", " + stream.viewer_count + " viewers"]),
					LI({class: "no-indent"}, stream.tags && stream.tags.map(tag => [SPAN({className: "tag"}, tag), " "])),
					LI([describe_notes(stream), describe_raid(stream.raids), raidbtn(stream)]),
				]),
				DIV({className: "img"}, A({href: "raidfinder?categories=" + encodeURIComponent(stream.category)},
					IMG({src: "https://static-cdn.jtvnw.net/ttv-boxart/" + stream.category + "-40x54.jpg"})
				)),
			]),
			stream.magic_breakdown && show_magic(stream.magic_breakdown), //Will only exist if the back end decides to send it.
		]
	)));
	ws_sync.send({cmd: "interested", want_streaminfo});
	if (your_stream)
		set_content("#yourcat", [
			your_stream.user_name + " has " + your_stream.viewer_count + " viewers in " + your_stream.category,
		]).href = "raidfinder?categories=" + encodeURIComponent(your_stream.category);
	else set_content("#yourcat", "");
	if (!precache_timer) precache_timer = setInterval(precache_streaminfo, 2000);
}
if (mode === "vodlength") show_vod_lengths(vodinfo); else build_follow_list();

export function sockmsg_chanstatus(data) {
	const stream = follows.find(f => f.user_id === data.channelid);
	if (!stream) return; //Not of interest to us.
	stream.chanstatus = data.chanstatus;
	if (stream.element) describe_uptime(stream, stream.element.querySelector(".uptime"));
}

let raidtarget = null, raidtargetid = null;
on("click", ".raidbtn", e => {
	raidtarget = e.match.dataset.target;
	raidtargetid = e.match.dataset.targetid;
	set_content("#raid_command", "/raid " + raidtarget);
	const btn = DOM("#goraiding .clipbtn");
	btn.title = "Copy '/raid " + raidtarget + "' to the clipboard";
	btn.dataset.copyme = "/raid " + raidtarget;
	set_content("#raidnow", "Raid now!").disabled = false;
	DOM("#goraiding").showModal();
});

on("click", "#raidnow", e => {
	set_content("#raidnow", "Starting raid...").disabled = true;
	ws_sync.send({cmd: "raidnow", target: raidtargetid});
});

export function render(data) {
	if (data.raidstatus) set_content("#raidnow", data.raidstatus);
}
