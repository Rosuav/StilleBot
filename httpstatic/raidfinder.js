import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, DIV, IMG, P, UL, LI} = choc;

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

console.log(follows);
function build_follow_list() {
	function describe_raid(raids) {
		if (!raids.length) return null;
		const raiddesc = raids[raids.length - 1];
		//TODO: Retain the full array and make this clickable
		return LI({className: raiddesc.includes("You raided") ? "raid-outgoing" : "raid-incoming"}, raiddesc);
	}
	set_content("#streams", follows.map(stream => stream.element = DIV([
		A({href: stream.channel.url}, IMG({src: stream.preview.medium})),
		DIV({className: "inforow"}, [
			//TODO: Make these links. Duh.
			DIV({className: "img"}, A({href: stream.channel.url}, IMG({className: "avatar", src: stream.channel.logo}))),
			UL([
				A({href: stream.channel.url}, LI(stream.channel.display_name)),
				LI(stream.channel.status),
				LI(stream.game),
				LI("Uptime " + uptime(stream.created_at) + ", " + stream.viewers + " viewers"),
				LI(stream.tags.join(", ")),
				//TODO: Show the one most recent raid. If they've raided us since we
				//raided them, put a CSS class on it so we can highlight it. If this
				//is clicked, pop up a dialog with a full list of raids (scrolled to
				//the bottom initially but allowing upward scrolling).
				describe_raid(stream.raids),
			]),
			DIV({className: "img"}, IMG({src: "https://static-cdn.jtvnw.net/ttv-boxart/" + stream.game + "-40x54.jpg"})),
		]),
	])));
}
build_follow_list();
