import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DETAILS, DIV, FORM, H3, INPUT, LABEL, LI, OL, P, SPAN, SUMMARY, TABLE, TD, TH, TR} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

//TODO: Exclude anyone who's been banned, just in case

const id_to_info = { };
let mods = { };
let board_count = 15;

function remap_to_array(stats) {
	if (!stats) return stats;
	const people = Object.values(stats);
	//Sort by score descending, but break ties with earliest subgift for the month
	people.sort((a,b) => (b.score - a.score) || (a.firstsub - b.firstsub));
	if (people.length > board_count) people.length = board_count;
	return people;
}

function make_list(arr, desc, empty, eligible) {
	if (!arr || !arr.length) return DIV(empty);
	return OL(arr.map(p => {
		let className = "", title = "Not eligible for a badge in this month";
		if (p.user_id === "274598607") {className = "anonymous"; title = "Anonymous - ineligible for badge";}
		else if (mods[p.user_id]) {className = "is_mod"; title = "Moderator - already has a badge, won't take a VIP slot";}
		else if (eligible-- > 0) {className = "eligible"; title = "Eligible for a VIP badge for this month!";}
		return LI({className, title},
			[SPAN({className: "username"}, p.user_name), " with ", p.score, desc]
		);
	}));
}

const monthnames = ["???", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export function render(data) {
	if (data.all) data.all.forEach(s => id_to_info[s.giver.user_id] = s.giver);
	if (data.mods) mods = data.mods;
	const mod = ws_group.startsWith("control#"); //Hide the buttons if the server would reject the signals anyway
	if (data.board_count) board_count = data.board_count;
	if (data.monthly) {
		const rows = [];
		const now = new Date();
		let year = now.getUTCFullYear(), mon = now.getUTCMonth() + 1;
		for (let i = 0; i < 7; ++i) {
			const ym = year * 100 + mon;
			const subs = remap_to_array(data.monthly["subs" + ym]);
			const bits = data.monthly["bits" + ym];
			if (bits && bits.length > board_count) bits.length = board_count; //We display a limited number, but the back end tracks more
			//IDs are set so you can, in theory, deep link. I doubt anyone will though.
			rows.push(TR({"id": ym, "data-period": monthnames[mon] + " " + year}, TH({colSpan: 2}, [
				monthnames[mon] + " " + year,
				mod && BUTTON({className: "addvip", title: "Add VIPs"}, "💎"),
				mod && BUTTON({className: "remvip", title: "Remove VIPs"}, "X"),
			])));
			rows.push(TR([
				TD(make_list(subs, " subs", "(no subgifting data)", data.badge_count || 10)),
				TD(make_list(bits, " bits", "(no cheering data)", data.badge_count || 10)),
			]));
			if (!--mon) {--year; mon = 12;}
		}
		set_content("#monthly", TABLE({border: 1}, rows));
	}
	if (mod) {
		if (!DOM("#modcontrols").childElementCount) set_content("#modcontrols", DETAILS([
			SUMMARY("Configuration"),
			FORM({id: "configform"}, [
				H3("Leaderboard settings"),
				P("Tracking of gifted subscriptions is done only while the leaderboard is active. Cheers are tracked by Twitch themselves."),
				P([BUTTON({id: "activate", type: "button"}, "Activate"), BUTTON({id: "deactivate", type: "button"}, "Deactivate")]),
				P([
					LABEL([
						"How many badges should be given out per category? ",
						INPUT({name: "badge_count", type: "number", value: 10, min: 1, max: 25}),
					]),
					BR(),
					"The top N cheerers and the top N subgifters will receive badges.",
				]),
				P([
					LABEL([
						"How many names should be shown on the leaderboard, per category? ",
						INPUT({name: "board_count", type: "number", value: 15, min: 1, max: 25}),
					]),
					BR(),
					"These people will be visible on the leaderboard. This may include ineligible people such as mods",
					" (they're greater than VIPs and won't be demoted).",
				]),
				P(LABEL([
					INPUT({name: "private_leaderboard", type: "checkbox"}),
					" Hide the leaderboard from non-mods",
				])),
				P(BUTTON({type: "submit"}, "Save")),
			]),
		]));
		DOM("#activate").disabled = !!data.active;
		DOM("#deactivate").disabled = !data.active;
		for (let el of DOM("#configform").elements)
			if (el.name && data[el.name])
				el[el.type === "checkbox" ? "checked" : "value"] = data[el.name];
	} else {
		if (!DOM("#modcontrols").childElementCount) set_content("#modcontrols",
			BUTTON({class: "twitchlogin", type: "button"}, "Login"),
		);
	}
}

on("click", "#recalc", e => ws_sync.send({cmd: "recalculate"}));

on("click", ".addvip", simpleconfirm(
	e => "Add VIPs earned during " + e.match.closest("TR").dataset.period + "?",
	e => ws_sync.send({cmd: "addvip", "yearmonth": e.match.closest("TR").id}),
));

on("click", ".remvip", simpleconfirm(
	e => "Remove VIPs earned during " + e.match.closest("TR").dataset.period + "?",
	e => ws_sync.send({cmd: "remvip", "yearmonth": e.match.closest("TR").id}),
));

on("click", "#activate,#deactivate", e => ws_sync.send({cmd: "configure", "active": e.match.id === "activate"}));
on("submit", "#configform", e => {
	e.preventDefault();
	const msg = {cmd: "configure"};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
});
