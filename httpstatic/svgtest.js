import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {"svg:feBlend": FE_BLEND, "svg:feFlood": FE_FLOOD, "svg:filter": FILTER, "svg:rect": RECT, "svg:svg": SVG, "svg:text": TEXT} = choc; //autoimport
import {ensure_font} from "$$static||utils.js$$";

function render(t) {
	//Parsed out of the thresholds and rendered text
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

//Directly from the server
render({
	invertfill: 1,
	"active": true,
	"altcolor": "#000000",
	"barcolor": "#9bfffd",
	"bit": "1",
	"bordercolor": "#000000",
	"borderradius": "",
	"color": "#000000",
	"css": "",
	"display": "20480:Next bug tier: #",
	"fillcolor": "#34c02a",
	"follow": "0",
	"font": "\"Odibee Sans\"",
	"fontsize": "32",
	"fontstyle": "normal",
	"fontweight": "normal",
	"format": "plain",
	"format_style": "2",
	"fw_dono": "",
	"fw_gift": "",
	"fw_member": "",
	"fw_shop": "",
	"height": "40",
	"id": "dLiYjuwOU4tHPbFh6lEcIazgXp7PBEoB409i",
	"infinitier": true,
	"kofi_commission": "",
	"kofi_dono": "1",
	"kofi_member": "",
	"kofi_renew": "",
	"kofi_shop": "1",
	"lvlupcmd": "",
	"needlesize": "0.375",
	"previewbg": "#000fb6",
	"sub_t1": "250",
	"sub_t2": "500",
	"sub_t3": "1250",
	"text": "$bugs$:Next bug tier: #",
	"text_css": "color: #000000;font-weight: normal;font-style: normal;border-color: #000000;font-size: 32px;width: 780px;height: 40px;border-radius: px;font-family: \"Odibee Sans\";padding-top: 0em; padding-bottom: 0em;padding-left: 0em; padding-right: 0em;--barcolor: #9bfffd;--fillcolor: #34c02a;--altcolor: #000000;",
	"thresholds": "1000",
	"thresholds_rendered": "1000",
	"tip": "1",
	"type": "goalbar",
	"width": "780",
});
