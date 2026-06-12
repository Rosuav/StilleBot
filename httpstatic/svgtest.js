import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {"svg:rect": RECT, "svg:svg": SVG, "svg:text": TEXT} = choc; //autoimport
import {ensure_font} from "$$static||utils.js$$";

function render(data) {
	//Parsed out of the thresholds and rendered text
	const mark = 48, text = "Next bug tier: 21", goal_text = "500", pos_text = "240";
	ensure_font(data.font);
	ensure_font('"Noto Color Emoji"'); //Hack - ensure that emojis work
	set_content("#display", SVG({style: data.text_css}, [
		RECT({id: "bar", width: data.width, height: data.height, fill: data.barcolor}),
		RECT({id: "fill", width: data.width * mark / 100, height: data.height, fill: data.fillcolor}),
		//Text is in three pieces
		TEXT({fill: data.color, y: data.height * .75}, text),
		TEXT({fill: data.color, y: data.height * .75, x: "50%", "text-anchor": "middle"}, goal_text),
		TEXT({fill: data.color, y: data.height * .75, x: "100%", "text-anchor": "end"}, pos_text),
	]));
}

//Directly from the server
render({
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
