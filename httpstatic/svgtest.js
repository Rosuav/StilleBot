import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {"svg:feBlend": FE_BLEND, "svg:feFlood": FE_FLOOD, "svg:filter": FILTER, "svg:rect": RECT, "svg:svg": SVG, "svg:text": TEXT} = choc; //autoimport
//Hard-coded URLs to allow this script to be hosted elsewhere. Makes it a demo of foreign access to a monitor.
import {ensure_font} from "https://sikorsky.mustardmine.com/static/utils.js";
import {connect} from "https://sikorsky.mustardmine.com/static/ws_sync.js";

function render(data) {
	const t = data.data;
	//CHEAT: These are parsed out of the thresholds and rendered text (see monitor.js)
	const mark = 48, text = "Next bug tier: 21", goal_text = "500", pos_text = "240";
	ensure_font(t.font);
	ensure_font('"Noto Color Emoji"'); //Hack - ensure that emojis work
	const elem = DOM("#display");
	elem.style.cssText = t.text_css;
	//This should be a complete copy of what's in monitor.js (modulo indentation).
	set_content(elem, SVG({style: "width: 100%; height: 100%", filter: t.invertfill && "url(#fillter)"}, [
		FILTER({id: "fillter"}, [ //badumtish
			//Simple inversion matrix. Works but would need a way to apply it to only the correct part
			//FE_COLOR_MATRIX({values: "-1 0 0 0 1   0 -1 0 0 1   0 0 -1 0 1   0 0 0 1 0"}),
			//So instead we make a flood-fill across the filled part, then blend that with the main graphic.
			FE_FLOOD({
				result: "fill", //Represents the filled part of the goal bar
				x: 0, y: 0, width: mark + "%", height: "100%",
				"flood-color": "#FFFFFF",
				"flood-opacity": 1,
			}),
			FE_BLEND({
				in: "SourceGraphic",
				in2: "fill",
				mode: "difference",
			}),
		]),
		RECT({id: "bar", width: "100%", height: "100%", fill: t.barcolor}),
		!t.invertfill && RECT({id: "fill", width: mark + "%", height: "100%", fill: t.fillcolor}),
		RECT({id: "needle", x: (mark-t.needlesize) + "%", width: t.needlesize + "%", height: "100%", fill: "red"}),
		//Text is in three pieces. It may be worth allowing the middle text to be omitted??
		//Baseline of 75% is a total guess but looks kinda okayish.
		TEXT({fill: t.color, y: "75%"}, text),
		TEXT({fill: t.color, y: "75%", x: "50%", "text-anchor": "middle"}, goal_text),
		TEXT({fill: t.color, y: "75%", x: "100%", "text-anchor": "end"}, pos_text),
	]));
}

connect("dLiYjuwOU4tHPbFh6lEcIazgXp7PBEoB409i#49497888", {
	ws_type: "chan_monitors",
	render,
});
