import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {DIV, LI, TIME, UL} = lindt; //autoimport

const colors = {
	//Needles
	"No prerolls": "#ff0000",
	"Snoozable time": "#ff0000",
	"Next ad": "#ff0000",
	"Next snooze": "#ff0000",
	//Fields
	no_prerolls: "#a0f0c0",
	snoozable: "#ff88dd",
	ads: "#ffcc77",
};

function TIME_T(time_t) {
	const date = new Date(time_t * 1000);
	return TIME({datetime: date.toISOString()}, date.toLocaleTimeString());
}

export function render(data) {
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
	console.log(markers);
	let color = colors.ads;
	if (data.time_captured + data.preroll_free_time_seconds > now) color = colors.no_prerolls;
	else if (now >= data.next_ad_at && snoozable > now) color = colors.snoozable;
	let gradient = color + ", ";
	markers.push([span, ""]); //Elephant in Cairo
	markers.forEach(([dt, desc]) => {
		const pos = Math.floor(dt / span * 100); //todo don't floor
		if (colors[desc])
			//Show a needle at this point
			gradient += color + " " + (pos - 0.5) + "%, " + colors[desc] + " " + (pos - 0.125) + "%, ";
		else
			//Show a hairline (black) at this point
			gradient += color + " " + (pos - 0.125) + "%, #000000 " + (pos - 0.125) + "%, ";
		//todo dedup
		color = colors.ads;
		if (data.time_captured + data.preroll_free_time_seconds > now + dt) color = colors.no_prerolls;
		else if (now + dt >= data.next_ad_at && snoozable > now + dt) color = colors.snoozable;
		gradient += color + " " + pos + "%, ";
	});
	console.log(gradient);
	replace_content("#nextad", [
		DIV({style: "width: 100%; height: 1em; background: linear-gradient(.25turn, " + gradient.slice(0, -2) + ")"}),
		UL([
			//TODO: Add colour swatches to these, linking them to the regions on the tape
			LI(["No prerolls until ", TIME_T(data.time_captured + data.preroll_free_time_seconds)]),
			LI(["Last ad: ", TIME_T(data.last_ad_at)]),
			LI(["Next ad: ", TIME_T(data.next_ad_at), " - ", data.length_seconds, " seconds long"]),
			LI([
				"Snoozes: ", data.snooze_count,
				data.snooze_refresh_at && [" - next at ", TIME_T(data.snooze_refresh_at)],
			]),
		]),
	]);
}

on("click", "#snooze", e => ws_sync.send({cmd: "snooze"}));
on("click", "#runad", e => ws_sync.send({cmd: "runad"}));

export function sockmsg_adtriggered(msg) {
	replace_content("#adtriggered", [
		msg.length + " second ad triggered. ",
		msg.message,
	]);
	setTimeout(replace_content, msg.length * 1000, "#adtriggered", "");
}
