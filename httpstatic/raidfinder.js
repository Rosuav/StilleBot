import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, B, BR, BUTTON, DIV, IMG, P, UL, LI, SPAN} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

const sortfunc = {
	Viewers: (s1, s2) => s1.viewers - s2.viewers,
	Category: (s1, s2) => s1.game.localeCompare(s2.game),
	Uptime: (s1, s2) => new Date(s2.created_at) - new Date(s1.created_at),
	Raided: (s1, s2) => (s1.raids[s1.raids.length-1]||"").localeCompare(s2.raids[s2.raids.length-1]||""),
	"Channel Creation": (s1, s2) => s1.created_at.localeCompare(s2.created_at),
	"Follow Date": (s1, s2) => s1.order - s2.order,
	"Name": (s1, s2) => s1.channel.display_name.localeCompare(s2.channel.display_name),
}
let lastsort = "";
on("click", "#sort li", e => {
	const pred = sortfunc[e.match.innerText];
	if (!pred) {console.error("No predicate function for " + e.match.innerText); return;}
	if (e.match.innerText === lastsort) follows.reverse(); //Poor man's sort order toggle
	else {follows.sort(pred); lastsort = e.match.innerText;}
	follows.forEach((stream, idx) => stream.element.style.order = idx);
});

function uptime(startdate) {
	const time = Math.floor((new Date() - new Date(startdate)) / 1000);
	if (time < 60) return time + " seconds";
	const hh = Math.floor((time / 3600) % 24);
	const mm = ("0" + Math.floor((time / 60) % 60)).slice(-2);
	const ss = ("0" + Math.floor(time % 60)).slice(-2);
	let ret = mm + ":" + ss;
	if (time >= 3600) ret = hh + ":" + ret;
	if (time >= 86400) ret = Math.floor(time / 86400) + " days, " + ret;
	return ret;
}

function show_raids(raids) {
	const ul = set_content("#raids ul", raids.map(desc => LI(
		{className: desc[0] === '>' ? "raid-outgoing" : "raid-incoming"},
		desc.slice(1),
	)));
	DOM("#raids").showModal();
	ul.scrollTop = ul.scrollHeight;
}

function edit_notes(stream) {
	set_content("#notes_about_channel", [
		"Channel notes: ",
		adornment(stream.channel.broadcaster_type),
		stream.channel.display_name,
		BR(),
		IMG({className: "avatar", src: stream.channel.logo}),
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
		body: JSON.stringify({id: stream.channel._id, notes: newnotes}),
	}).then(res => {
		if (!res.ok) {console.error("ERROR SAVING NOTES"); console.error(res);} //TODO
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
	DOM("#editnotes").stream = {channel: {_id: 0}};
	DOM("#editnotes").showModal();
}

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

console.log(follows);
function build_follow_list() {
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
	//TODO: Show when stream.viewers is a long way above or below your_viewers
	set_content("#streams", follows.map(stream => stream.element = DIV({className: stream.highlight ? "highlighted" : ""},
		mode === "allfollows" ? [
			//Cut-down view for channels that might be offline. Also, most of this is Helix info not Kraken.
			A({href: "https://twitch.tv/" + stream.login}, [
				IMG({className: "avatar", src: stream.channel.logo}),
				adornment(stream.channel.broadcaster_type),
				stream.channel.display_name,
			]),
			describe_notes(stream),
		] : [
			A({href: stream.channel.url}, IMG({src: stream.preview.medium})),
			DIV({className: "inforow"}, [
				DIV({className: "img"}, A({href: stream.channel.url}, IMG({className: "avatar", src: stream.channel.logo}))),
				UL([
					LI([A({href: stream.channel.url}, [adornment(stream.channel.broadcaster_type), stream.channel.display_name]), " - ", B(stream.game)]),
					LI({className: "streamtitle"}, stream.channel.status),
					LI("Uptime " + uptime(stream.created_at) + ", " + stream.viewers + " viewers"),
					LI(stream.tags.map(tag => SPAN({className: "tag"}, tag.name + " "))),
					LI([describe_notes(stream), describe_raid(stream.raids)]),
				]),
				//TODO: Make this a link to the category.
				DIV({className: "img"}, IMG({src: "https://static-cdn.jtvnw.net/ttv-boxart/" + stream.game + "-40x54.jpg"})),
			]),
		]
	)));
	//TODO maybe: Have this link back to raidfinder with a marker saying "your cat",
	//and thus get all the recent raid info etc, rather than just linking to the cat.
	if (your_stream)
		set_content("#yourcat", [
			your_stream.user_name + " has " + your_stream.viewer_count + " viewers in " + your_stream.category,
		]).href = "https://www.twitch.tv/directory/game/" + your_stream.category;
	else set_content("#yourcat", "");
}
build_follow_list();
