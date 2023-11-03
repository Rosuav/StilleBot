import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, TIME, UL} = lindt; //autoimport

function TIME_T(time_t) {
	const date = new Date(time_t * 1000);
	return TIME({datetime: date.toISOString()}, date.toLocaleTimeString());
}

export function render(data) {
	replace_content("#nextad", [
		//TODO: Time tape
		UL([
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
