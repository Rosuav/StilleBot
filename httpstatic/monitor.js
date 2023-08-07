import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV} = choc;
import {ensure_font} from "$$static||utils.js$$";

const currency_formatter = new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"});
export const formatters = {
	currency: cents => {
		if (cents >= 0 && !(cents % 100)) return "$" + (cents / 100); //Abbreviate the display to "$5" for 500
		return currency_formatter.format(cents / 100);
	},
	subscriptions: cents => {
		if (cents >= 0 && !(cents % 500)) return "" + (cents / 500);
		return (cents / 500).toFixed(3);
	},
}

function countdown_ticker(elem) {
	//"##:##" for min:sec
	//"#:##" for min:sec w/o leading zero
	//"##" for seconds, padded to two places with zeroes (ditto "###" or "#")
	let time = elem._stillebot_countdown_target;
	//Times below a gigasecond are paused times, times above that are time_t when it hits zero
	if (time > 1e9) time = Math.floor(time - new Date() / 1000);
	if (time < 0) time = 0; //Leave it stuck on 00:00 after it expires
	if (window.RICEBOT) {time = window.RICEBOT(time); if (typeof time === "string") return set_content(elem, time);}
	const parts = elem._stillebot_countdown_format.split(":##");
	//For every ":##" in the string, fracture off one sixtieth of the time (thus seconds and minutes)
	//Then a hash in the first part of the string gets whatever's left,
	//padded to the number of hashes.
	for (let i = parts.length - 1; i > 0; --i) { //From the end, back to all but the last - err I mean first
		const cur = time % 60;
		time = Math.floor(time / 60); //Why doesn't JS just have a simple divmod...
		parts[i] = ("0" + cur).slice(-2) + parts[i];
	}
	//The first part should have some number of hashes in it. Pad the number to
	//that many, but allow more digits if needed.
	time = "" + time;
	parts[0] = parts[0].replace(/#+$/, hashes => {
		if (hashes.length > time.length) return time;
		return ("0".repeat(hashes.length) + time).slice(-hashes.length);
	});
	set_content(elem, parts.join(":"));
}

const styleinfo = { }; //Retained info for when the styles need to change based on data (for goal bars)
export function render(data) {update_display(DOM("#display"), data.data);}
export function update_display(elem, data) { //Used for the preview as well as the live display
	//Update styles. The server provides a single "text_css" attribute covering most of the easy
	//stuff; all we have to do here is handle the goal bar position.
	if (data.text_css || data.text_css === "") {
		elem.style.cssText = data.text_css;
		if (data.type) styleinfo[data.id] = {type: data.type}; //Reset all type-specific info when type is sent
		if (data.thresholds) styleinfo[data.id].t = data.thresholds.split(" ").map(x => +x).filter(x => x && x === x); //Suppress any that fail to parse as numbers
		if (data.barcolor) styleinfo[data.id].barcolor = data.barcolor;
		if (data.fillcolor) styleinfo[data.id].fillcolor = data.fillcolor;
		if (data.format) styleinfo[data.id].format = data.format;
		if (data.needlesize) styleinfo[data.id].needlesize = +data.needlesize;
		if (data.progressive) styleinfo[data.id].progressive = data.progressive;
		ensure_font(data.font);
	}
	const type = styleinfo[data.id] && styleinfo[data.id].type;
	if (elem._stillebot_countdown_interval) {
		clearInterval(elem._stillebot_countdown_interval);
		elem._stillebot_countdown_interval = 0;
	}
	if (type === "goalbar") {
		const t = styleinfo[data.id];
		const thresholds = t.t;
		const m = /^([0-9]+):(.*)$/.exec(data.display);
		if (!m) {console.error("Something's misconfigured (see monitor.js goalbar regex) -- display", data.display); return;}
		let pos = m[1], text, mark, goal;
		for (let which = 0; which < thresholds.length; ++which) {
			if (pos < thresholds[which]) {
				//Found the point to work at.
				text = m[2].replace("#", which + 1);
				if (t.progressive && which) mark = (pos - thresholds[which - 1]) / thresholds[which] * 100;
				else mark = pos / thresholds[which] * 100;
				goal = thresholds[which];
				break;
			}
			else if (!t.progressive) pos -= thresholds[which];
		}
		if (!text) {
			//We're beyond the last threshold!
			text = m[2].replace("#", thresholds.length);
			mark = 100;
			goal = thresholds[thresholds.length - 1];
			if (!t.progressive) pos += goal; //After blowing past the last goal, we're clearly past that goal
		}
		elem.style.background = `linear-gradient(.25turn, ${t.fillcolor} ${mark-t.needlesize}%, red, ${t.barcolor} ${mark+t.needlesize}%, ${t.barcolor})`;
		elem.style.display = "flex";
		const f = formatters[t.format] || (x => ""+x);
		set_content(elem, [DIV(text), DIV(f(pos)), DIV(f(goal))]);
	}
	else if (type === "countdown") {
		const m = /^([0-9]+):(.*)$/.exec(data.display);
		if (!m) {console.error("Something's misconfigured (see monitor.js countdown regex) -- display", data.display); return;}
		elem._stillebot_countdown_target = +m[1];
		elem._stillebot_countdown_format = m[2];
		elem._stillebot_countdown_interval = setInterval(countdown_ticker, 1000, elem);
		countdown_ticker(elem);
	}
	else set_content(elem, data.display);
}
