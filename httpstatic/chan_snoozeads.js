import {choc, lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {DIV, LI, SPAN, TIME, UL} = lindt; //autoimport
import {cmd_configure} from "$$static||command_editor.js$$";

cmd_configure({
	get_command_basis: command => {
		const basis = {type: "anchor_special"};
		set_content("#advanced_view h3", ["Edit special response ", choc.CODE("!" + command.id.split("#")[0])]);
		const params = {"{username}": "The broadcaster", "{uid}": "ID of that person"};
		basis._provides = {
			"{advance_warning}": "advance_warning", //FIXME
		};
		basis._desc = "An ad is scheduled to start soon";
		basis._shortdesc = "An ad starts soon";
		return basis;
	},
});
ws_sync.send({cmd: "subscribe", type: "cmdedit", group: "!!adsoon"});

const colors = {
	//Needles
	"Next ad": "#ff0000",
	"Next snooze": "#0000ff",
	//Fields
	no_prerolls: "#a0f0c0",
	snoozable: "#ff88dd",
	ads: "#ffcc77",
};

function TIME_T(time_t) {
	const date = new Date(time_t * 1000);
	return TIME({datetime: date.toISOString()}, date.toLocaleTimeString());
}

let rerender = 0;
export function render(data) {
	DOM("#advance_warning").value = data.advance_warning;
	clearInterval(rerender);
	rerender = setInterval(render, 60000, data);
	//For the time tape, pick out some useful markers and organize them.
	const now = Math.floor(new Date/1000);
	const times = [
		[data.time_captured + data.preroll_free_time_seconds, "No prerolls"],
		[data.next_ad_at, "Next ad"],
		[data.snooze_refresh_at || 0, "Next snooze"],
	];
	let snoozable = data.next_ad_at + 300 * data.snooze_count;
	if (snoozable > data.snooze_refresh_at) snoozable += 300; //Effectively, you'll get one more snooze out of this. (Not bothering to handle DOUBLE snooze refresh, which would not be a normal situation!)
	times.push([snoozable, "Snoozable time"]);
	for (let h = 0; h < 48; ++h) times.push([data.online_since + h * 3600, h + ":00"]);
	times.sort((a,b) => a[0] - b[0]);
	//Any marker prior to the "Now" point is irrelevant; everything else is
	//defined by its delta-time.
	const span = 3600 * 2, cutoff = now + span; //Don't bother showing too much data. (Maybe even 1 hour?)
	const markers = [];
	times.forEach(([tm, desc]) => tm > now && tm < cutoff && markers.push([tm - now, desc]));
	function pick_color(dt) {
		//Note that both of these could be true simultaneously. Currently there's simply a
		//prioritization, but maybe there should be a different colour for "both"?
		if (now + dt >= data.next_ad_at && snoozable > now + dt) return colors.snoozable;
		if (data.time_captured + data.preroll_free_time_seconds > now + dt) return colors.no_prerolls;
		return colors.ads;
	}
	let color = pick_color(0);
	let gradient = color + ", ";
	const above = [], below = [];
	let above_dt = 0, below_dt = 0;
	markers.forEach(([dt, desc]) => {
		const pos = dt / span * 100;
		//Blank entry at the end should get both added
		if (desc.endsWith(":00")) { //Tick marks above the tape, with hairlines
			let title = new Date((dt + now) * 1000).toLocaleTimeString();
			above.push(DIV({style: "flex-grow: " + (dt - above_dt)}), DIV({title}, desc));
			above_dt = dt;
			gradient += color + " " + (pos - 0.125) + "%, #000000 " + (pos - 0.125) + "%, ";
		} else if (colors[desc]) { //Labels below the tape, with wider markers
			let title = new Date((dt + now) * 1000).toLocaleTimeString();
			if (desc === "Next ad") title += " - snoozable for " + ((snoozable - data.next_ad_at) / 60) + ":00";
			below.push(
				DIV({style: "flex-grow: " + (dt - below_dt)}),
				DIV({style: "flex-basis: 0; white-space: nowrap", title}, desc),
			);
			below_dt = dt;
			gradient += color + " " + (pos - 0.5) + "%, " + (colors[desc] || "#fff") + " " + (pos - 0.125) + "%, ";
		} else {
			gradient += color + " " + pos + "%, ";
		}
		color = pick_color(dt);
		gradient += color + " " + pos + "%, ";
	});
	gradient += color + " 100%";
	above.push(DIV({style: "flex-grow: " + (span - above_dt)}));
	below.push(DIV({style: "flex-grow: " + (span - below_dt)}));
	replace_content("#nextad", [
		DIV({style: "display: flex"}, above),
		DIV({style: "height: 1em; background: linear-gradient(.25turn, " + gradient + ")"}),
		DIV({style: "display: flex"}, below),
		UL([
			LI("Time markers above the tape show stream uptime; times shown here are your local time."),
			LI(SPAN({style: "background: " + colors.no_prerolls}, ["No prerolls until ", TIME_T(data.time_captured + data.preroll_free_time)])),
			LI(["Last ad: ", TIME_T(data.last_ad_at)]),
			LI(["Next ad: ", TIME_T(data.next_ad_at), " - ", data.duration, " seconds long"]),
			LI(SPAN({style: "background: " + colors.snoozable}, [
				"Snoozes: ", data.snooze_count || "None",
				data.snooze_refresh_at && [" - next at ", TIME_T(data.snooze_refresh_at)],
			])),
		]),
	]);
}

on("click", "#snooze", e => ws_sync.send({cmd: "snooze"}));
on("click", "#runad", e => ws_sync.send({cmd: "runad"}));
on("change", "#modsnooze", e => ws_sync.send({cmd: "modsnooze", value: e.match.value}));
on("change", "#advance_warning", e => ws_sync.send({cmd: "advance_warning", value: e.match.value}));

export function sockmsg_adtriggered(msg) {
	replace_content("#adtriggered", [
		msg.length + " second ad triggered. ",
		msg.message,
	]);
	setTimeout(replace_content, msg.length * 1000, "#adtriggered", "");
}
