import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, LI, OL, SPAN, TABLE, TD, TH, TR} = choc; //autoimport
import {waitlate} from "$$static||utils.js$$";

//TODO: Exclude anyone who's been banned, just in case

const id_to_info = { };
let mods = { };

function remap_to_array(stats) {
	if (!stats) return stats;
	const people = Object.entries(stats).map(e => ({id: e[0], ...(id_to_info[e[0]]||{}), qty: e[1]}));
	//FIXME: Would be better to use "oldest timestamp this month" but I don't
	//really have that available.
	people.sort((a,b) => b.qty - a.qty || a.login.localeCompare(b.login));
	if (people.length > 15) people.length = 15;
	return people;
}

function make_list(arr, desc, empty) {
	if (!arr || !arr.length) return DIV(empty);
	return OL(arr.map(p => LI(
		{className: p.id === "274598607" ? "anonymous" : mods[p.user_id || p.id] ? "is_mod" : ""},
		[SPAN({className: "username"}, p.displayname || p.user_name), " with ", desc(p)]
	)));
}

const monthnames = ["???", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export function render(data) {
	if (data.all) data.all.forEach(s => id_to_info[s.giver.user_id] = s.giver);
	if (data.mods) mods = data.mods;
	if (data.monthly) {
		const rows = [];
		const now = new Date();
		let year = now.getFullYear(), mon = now.getMonth() + 1;
		for (let i = 0; i < 7; ++i) {
			const ym = year * 100 + mon;
			const subs = remap_to_array(data.monthly["subs" + ym]);
			const bits = data.monthly["bits" + ym];
			if (bits && bits.length > 15) bits.length = 15; //We display fifteen, but the back end tracks ten more
			rows.push(TR(TH({colSpan: 2}, monthnames[mon] + " " + year)));
			rows.push(TR([
				TD(make_list(subs, p => p.qty + " subs", "(no subgifting data)")),
				TD(make_list(bits, p => p.score + " bits", "(no cheering data)")),
			]));
			if (!--mon) {--year; mon = 12;}
		}
		set_content("#monthly", TABLE({border: 1}, rows));
	}
}

on("click", "#recalc", e => ws_sync.send({cmd: "recalculate"}));
