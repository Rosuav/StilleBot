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
		ensure_font(data.font);
	}
	const type = styleinfo[data.id] && styleinfo[data.id].type;
	if (type === "goalbar") {
		const t = styleinfo[data.id];
		const thresholds = t.t;
		const m = /^([0-9]+):(.*)$/.exec(data.display);
		if (!m) {console.error("Something's misconfigured (see monitor.js regex) -- display", data.display); return;}
		let pos = m[1], text, mark, goal;
		for (let which = 0; which < thresholds.length; ++which) {
			if (pos < thresholds[which]) {
				//Found the point to work at.
				text = m[2].replace("#", which + 1);
				mark = pos / thresholds[which] * 100;
				goal = thresholds[which];
				break;
			}
			else pos -= thresholds[which];
		}
		if (!text) {
			//We're beyond the last threshold!
			text = m[2].replace("#", thresholds.length);
			mark = 100;
			goal = thresholds[thresholds.length - 1];
			pos += goal; //After blowing past the last goal, we're clearly past that goal
		}
		elem.style.background = `linear-gradient(.25turn, ${t.fillcolor} ${mark-t.needlesize}%, red, ${t.barcolor} ${mark+t.needlesize}%, ${t.barcolor})`;
		elem.style.display = "flex";
		const f = formatters[t.format] || (x => ""+x);
		set_content(elem, [DIV(text), DIV(f(pos)), DIV(f(goal))]);
	}
	else set_content(elem, data.display);
}
