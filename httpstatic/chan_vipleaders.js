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

let badge_count = {}, badge_streak = {};
function make_list(arr, fmt, empty, eligible, which) {
	if (!arr || !arr.length) return DIV(empty);
	if (arr.length > board_count) arr.length = board_count; //We display a limited number, but the back end tracks more
	return OL(arr.map(p => {
		let className = "", title = "Not eligible for a badge in this month";
		if (p.user_id === "274598607") {className = "anonymous"; title = "Anonymous - ineligible for badge";}
		else if ("" + +p.user_id !== "" + p.user_id) {className = ""; title = "Not a Twitch user - no badge awarded";}
		else if (mods[p.user_id]) {className = "is_mod"; title = "Moderator - already has a badge, won't take a VIP slot";}
		else if (eligible-- > 0) {
			className = "eligible";
			if (which === 0) title = "Eligible for a VIP badge for this month!";
			else {
				title = "Received a VIP badge for this month!";
				if (which === 1) badge_count[p.user_id] = badge_streak[p.user_id] = 1;
				else {
					badge_count[p.user_id] = (badge_count[p.user_id] || 0) + 1;
					if (badge_streak[p.user_id] === which - 1) badge_streak[p.user_id] = which;
				}
			}
		}
		return LI({className, title, "data-uid": p.user_id, "data-which": which, "data-streak": badge_streak[p.user_id]},
			[SPAN({className: "username"}, p.user_name), " with ", fmt(p.score)]
		);
	}));
}

const currency_formatter = new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"});
function cents_formatter(cents) {
	if (cents >= 0 && !(cents % 100)) return "$" + (cents / 100); //Abbreviate the display to "$5" for 500
	return currency_formatter.format(cents / 100);
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
		let which_month = 0;
		badge_count = {}; badge_streak = {}; //Reset the counters
		for (let i = 0; i < 7; ++i) {
			const ym = year * 100 + mon;
			const subs = remap_to_array(data.monthly["subs" + ym]);
			const kofi = remap_to_array(data.monthly["kofi" + ym]);
			const bits = data.monthly["bits" + ym];
			//IDs are set so you can, in theory, deep link. I doubt anyone will though.
			rows.push(TR({"id": ym, "data-period": monthnames[mon] + " " + year}, TH({colSpan: 3}, [
				monthnames[mon] + " " + year,
				mod && BUTTON({className: "addvip", title: "Add VIPs"}, "💎"),
				mod && BUTTON({className: "remvip", title: "Remove VIPs"}, "X"),
				mod && data.displayformat && BUTTON({className: "fmtvip", title: "Show summary"}, "📃"),
			])));
			rows.push(TR([
				TD(make_list(subs, s => [s, " subs"], "(no subgifting data)", data.badge_count || 10, which_month)),
				TD(make_list(bits, s => [s, " bits"], "(no cheering data)", data.badge_count || 10, which_month)),
				(data.use_kofi || data.use_streamlabs) && TD(make_list(kofi, cents_formatter, "(no tipping data)", data.badge_count || 10, which_month)),
			]));
			if (!--mon) {--year; mon = 12;}
			++which_month;
		}
		set_content("#monthly", TABLE({border: 1}, rows));
		Object.entries(badge_count).forEach(([id, count]) => {
			const streak = badge_streak[id];
			document.querySelectorAll('li[data-uid="' + id + '"]').forEach(li => {
				if (li.dataset.which === "0") {
					//It's the current month. Show things slightly differently.
					li.title += " - potentially " + (count + 1) + " badges";
					if (streak) {
						li.title += ", " + (streak + 1) + " streak";
						li.append(` (month ${streak + 1})`);
					}
					return;
				}
				li.title += " - " + count + " badges";
				if (streak > 1 && streak >= +li.dataset.which) {
					li.title += ", " + streak + " streak";
					li.append(` (month ${streak + 1 - li.dataset.streak})`);
				}
			});
		});
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
				P(LABEL([
					INPUT({name: "use_kofi", type: "checkbox"}),
					" Show Ko-fi donations on a third leaderboard (requires Ko-fi Integration)",
				])),
				P(LABEL([
					INPUT({name: "use_streamlabs", type: "checkbox"}),
					" Show StreamLabs donations on a third leaderboard (combined with Ko-fi if applicable)",
				])),
				P([
					"Want a summary of VIP leaders for social media? ",
					BUTTON({type: "button", class: "showdialog", "data-dlg": "formatdlg"}, "Configure it here!"),
				]),
				P(BUTTON({type: "submit"}, "Save")),
			]),
		]));
		DOM("#activate").disabled = !!data.active;
		DOM("#deactivate").disabled = !data.active;
		for (let el of DOM("#configform").elements)
			if (el.name && data[el.name])
				el[el.type === "checkbox" ? "checked" : "value"] = data[el.name];
		if (data.displayformat) DOM("#formattext").value = data.displayformat;
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

on("click", ".showdialog", e => DOM("#" + e.match.dataset.dlg).showModal());
on("click", "#formatsave", e => {
	ws_sync.send({cmd: "configure", displayformat: DOM("#formattext").value});
	DOM("#formatdlg").close();
});
on("click", ".fmtvip", e => {
	set_content("#formatdate", e.match.closest("TR").dataset.period);
	ws_sync.send({cmd: "formattext", monthyear: e.match.closest("TR").id});
});
export function sockmsg_formattext(msg) {
	DOM("#displaytext").value = msg.text;
	DOM("#displaydlg").showModal();
}
