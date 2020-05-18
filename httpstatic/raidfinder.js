import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, DIV, IMG, P, UL, LI, SPAN} = choc;

const sortfunc = {
	Viewers: (s1, s2) => s1.viewers - s2.viewers,
	Category: (s1, s2) => s1.game.localeCompare(s2.game),
	Uptime: (s1, s2) => new Date(s2.created_at) - new Date(s1.created_at),
	Raided: (s1, s2) => (s1.raids[s1.raids.length-1]||"").localeCompare(s2.raids[s2.raids.length-1]||""),
}

on("click", "#sort li", e => {
	const pred = sortfunc[e.match.innerText];
	if (!pred) {console.error("No predicate function for " + e.match.innerText); return;}
	follows.sort(pred);
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
	if (time >= 86400) ret = Math.floor(time / 86400) + "days, " + ret;
	return ret;
}

function show_raids(raids) {
	const ul = set_content("#raids ul", raids.map(desc => LI(
		{className: desc.includes("You raided") ? "raid-outgoing" : "raid-incoming"},
		desc,
	)));
	DOM("#raids").showModal();
	ul.scrollTop = ul.scrollHeight;
}

console.log(follows);
function build_follow_list() {
	function describe_raid(raids) {
		if (!raids.length) return null;
		const raiddesc = raids[raids.length - 1];
		const outgoing = raiddesc.includes("You raided");
		return LI({
			className: outgoing ? "raid-outgoing" : "raid-incoming",
			onclick: () => show_raids(raids),
		}, [
			!outgoing && IMG({className: "emote", src: "https://static-cdn.jtvnw.net/emoticons/v1/62836/1.0"}), //twitchRaid
			/^[-0-9]+/.exec(raiddesc)[0], //Just the date
			outgoing && IMG({className: "emote", src: "https://static-cdn.jtvnw.net/emoticons/v1/62836/1.0"}),
		]);
	}
	//TODO: Show when stream.viewers is a long way above or below your_viewers
	set_content("#streams", follows.map(stream => stream.element = DIV([
		A({href: stream.channel.url}, IMG({src: stream.preview.medium})),
		DIV({className: "inforow"}, [
			DIV({className: "img"}, A({href: stream.channel.url}, IMG({className: "avatar", src: stream.channel.logo}))),
			UL([
				LI([A({href: stream.channel.url}, stream.channel.display_name), " - ", stream.game]),
				LI({className: "streamtitle"}, stream.channel.status),
				LI("Uptime " + uptime(stream.created_at) + ", " + stream.viewers + " viewers"),
				LI(stream.tags.map(tag => SPAN({className: "tag"}, tag.name + " "))),
				describe_raid(stream.raids),
			]),
			//TODO: Make this a link to the category.
			DIV({className: "img"}, IMG({src: "https://static-cdn.jtvnw.net/ttv-boxart/" + stream.game + "-40x54.jpg"})),
		]),
	])));
	//TODO maybe: Have this link back to raidfinder with a marker saying "your cat",
	//and thus get all the recent raid info etc.
	set_content("#yourcat",
		["You have ", ""+your_viewers, " viewers in ", your_category],
	).href = "https://www.twitch.tv/directory/game/" + your_category;
}
build_follow_list();

//Compat shim lifted from Mustard Mine
//For browsers with only partial support for the <dialog> tag, add the barest minimum.
//On browsers with full support, there are many advantages to using dialog rather than
//plain old div, but this way, other browsers at least have it pop up and down.
document.querySelectorAll("dialog").forEach(dlg => {
	if (!dlg.showModal) dlg.showModal = function() {this.style.display = "block";}
	if (!dlg.close) dlg.close = function() {this.style.removeProperty("display");}
});
on("click", ".dialog_cancel,.dialog_close", e => e.match.closest("dialog").close());
