import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, IMG} = choc; //autoimport
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

const styleinfo = { }; //Retained info for when the styles need to change based on data (for goal bars)

function countdown_ticker(elem, id) {
	//"##:##" for min:sec
	//"#:##" for min:sec w/o leading zero
	//"##" for seconds, padded to two places with zeroes (ditto "###" or "#")
	let time = elem._stillebot_countdown_target;
	//Times below a gigasecond are paused times, times above that are time_t when it hits zero
	if (time > 1e9) time = Math.floor(time - new Date() / 1000);
	if (time <= 0) {
		//If you have special text for "in the past", use that the moment we hit zero.
		if (styleinfo[id].textcompleted) return set_content(elem, styleinfo[id].textcompleted);
		time = 0; //Leave it stuck on 00:00 after it expires
	}
	if (time > 3600) { //TODO: Make this boundary configurable
		if (styleinfo[id].textinactive) return set_content(elem, styleinfo[id].textinactive);
	}
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
		if (hashes.length < time.length) return time;
		return ("0".repeat(hashes.length) + time).slice(-hashes.length);
	});
	set_content(elem, parts.join(":"));
}

let lastvis = "hidden";
function vischange() {
	if (lastvis === "hidden" && document.visibilityState === "visible") {
		//We've just become visible. Signal the server to start the timer.
		ws_sync.send({cmd: "sceneactive"});
	}
	lastvis = document.visibilityState;
}

export function render(data) {update_display(DOM("#display"), data.data);}
let prevpos = 100, prevname = null, prevcredit = null;
export function update_display(elem, data) { //Used for the preview as well as the live display
	//Update styles. The server provides a single "text_css" attribute covering most of the easy
	//stuff; all we have to do here is handle the goal bar position.
	if (data.text_css || data.text_css === "") {
		elem.style.cssText = data.text_css;
		if (data.type) styleinfo[data.id] = {type: data.type}; //Reset all type-specific info when type is sent
		if (data.thresholds) styleinfo[data.id].t = (data.thresholds_rendered || data.thresholds).split(" ").map(x => +x).filter(x => x && x === x); //Suppress any that fail to parse as numbers
		if (data.needlesize) styleinfo[data.id].needlesize = +data.needlesize;
		["barcolor", "fillcolor", "format", "progressive", "textcompleted", "textinactive"].forEach(
			key => data[key] && (styleinfo[data.id][key] = data[key]));
		ensure_font(data.font);
	}
	const type = styleinfo[data.id] && styleinfo[data.id].type;
	if (elem._stillebot_countdown_interval) {
		clearInterval(elem._stillebot_countdown_interval);
		elem._stillebot_countdown_interval = 0;
	}
	if (type === "goalbar") {
		const t = styleinfo[data.id];
		if (t.format === "hitpoints") {
			const m = /^([0-9]+):([^ ]*) (.*)$/.exec(data.display);
			if (!m) {console.error("Something's misconfigured (see monitor.js goalbar regex) -- display", data.display); return;}
			const maxhp = t.t[0];
			const curhp = maxhp - m[1], avatar = m[2], name = m[3];
			const pos = curhp/maxhp * 100;
			elem.style.display = "flex";
			let img = elem.querySelector("img");
			if (name !== prevname || img?.src !== avatar) {
				//New boss! Save the previous boss credit for the cross-fade, and make ourselves
				//a new image for the avatar. Note that if an additional change occurs within the
				//transition animation, the "previous" will not be changed. This allows for the
				//name and avatar to change independently, but also means that rapid-fire boss
				//replacements (what's going on, BOFH got angry?) will transition from the oldest
				//directly to the newest.
				prevname = name;
				prevcredit = prevcredit || elem.querySelector(".bosscredit");
				if (prevcredit) {
					prevcredit.classList.remove("bosscredit");
					prevcredit.classList.add("waning");
				}
				img = null;
				setTimeout(() => prevcredit = null, 2000);
			}
			if (!img) img = IMG({class: "avatar", src: avatar});
			if (img.src !== avatar) img.src = avatar; //Avoid flicker
			/* Wide format
			set_content(elem, [
				img,
				DIV({class: "goalbar", style: `display: flex; --oldpos: ${prevpos}%; --newpos: ${pos}%;`}, [
					DIV(name), DIV(), DIV(curhp + "/" + maxhp),
				]),
			]);
			*/
			//Stacked format
			elem.style.flexDirection = "row";
			set_content(elem, [
				img,
				DIV({style: "display: flex; flex-direction: column; flex-grow: 1"}, [
					DIV({class: "goalbar", style: `--oldpos: ${prevpos}%; --newpos: ${pos}%;`}, [
						DIV({style: "padding: 2px 6px"}, curhp + "/" + maxhp),
					]),
					DIV({style: "position: relative"}, [
						DIV({class: prevcredit ? "bosscredit waxing" : "bosscredit", style: "text-wrap: nowrap; width: 100%; text-align: left"}, name),
						prevcredit,
					]),
				]),
			]);
			prevpos = pos;
			return;
		}
		const thresholds = t.t;
		const m = /^([0-9]+):(.*)$/.exec(data.display);
		if (!m) {console.error("Something's misconfigured (see monitor.js goalbar regex) -- display", data.display); return;}
		let pos = m[1], text, mark, goal;
		for (let which = 0; which < thresholds.length; ++which) {
			if (pos < thresholds[which]) {
				//Found the point to work at.
				text = m[2].replace("#", which + 1);
				if (t.progressive && which) mark = (pos - thresholds[which - 1]) / (thresholds[which] - thresholds[which - 1]) * 100;
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
		//TODO: Is it worth changing this to use CSS variables instead of interpolation? See bit boss code above for example.
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
		elem._stillebot_countdown_interval = setInterval(countdown_ticker, 1000, elem, data.id);
		countdown_ticker(elem, data.id);
		if (data.startonscene && ws_group[0] !== '#') //Don't do this on the control/preview connection
			(document.onvisibilitychange = vischange)();
		else document.onvisibilitychange = null; //Note: Using this instead of on() for idempotency
	}
	else set_content(elem, data.display);
}
