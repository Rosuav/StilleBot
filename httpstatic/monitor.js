import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV} = choc;

//Map the CSS attributes on the server to the names used in element.style
const css_attribute_names = {color: "color", font: "fontFamily", fontweight: "fontWeight", fontstyle: "fontStyle", bordercolor: "borderColor", whitespace: "white-space"};

const currency_formatter = new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"});
const formatters = {
	currency: cents => {
		if (cents >= 0 && !(cents % 100)) return "$" + (cents / 100); //Abbreviate the display to "$5" for 500
		return currency_formatter.format(cents / 100);
	},
}

const styleinfo = { }; //Retained info for when the styles need to change based on data (for goal bars)
export function render(data) {update_display(DOM("#display"), data.data);}
export default function update_display(elem, data) { //Used for the preview as well as the live display
	//Update styles. If the arbitrary CSS setting isn't needed, make sure it is "" not null.
	if (data.css || data.css === "") {
		elem.style.cssText = data.css;
		for (let attr in css_attribute_names) {
			if (data[attr]) elem.style[css_attribute_names[attr]] = data[attr];
		}
		if (data.type) styleinfo[data.id] = {type: data.type}; //Reset all type-specific info when type is sent
		if (data.thresholds) styleinfo[data.id].t = data.thresholds.split(" ").map(x => +x).filter(x => x && x === x); //Suppress any that fail to parse as numbers
		if (data.barcolor) styleinfo[data.id].barcolor = data.barcolor;
		if (data.fillcolor) styleinfo[data.id].fillcolor = data.fillcolor;
		if (data.format) styleinfo[data.id].format = data.format;
		if (data.needlesize) styleinfo[data.id].needlesize = +data.needlesize;
		if (data.fontsize) elem.style.fontSize = data.fontsize + "px"; //Special-cased to add the unit
		//It's more-or-less like saying "padding: {padvert}em {padhoriz}em"
		if (data.padvert)  elem.style.paddingTop = elem.style.paddingBottom = data.padvert + "em";
		if (data.padhoriz) elem.style.paddingLeft = elem.style.paddingRight = data.padhoriz + "em";
		if (data.width)  elem.style.width = data.width + "px";
		if (data.height) elem.style.height = data.height + "px";
		//If you set a border width, assume we want a solid border. (For others, set the
		//entire border definition in custom CSS.)
		if (data.borderwidth) {elem.style.borderWidth = data.borderwidth + "px"; elem.style.borderStyle = "solid";}
		if (data.font) {
			//Attempt to fetch fonts from Google Fonts if they're not installed already
			//This will be ignored by the browser if you have the font, so it's no big
			//deal to have it where it's unnecessary. If you misspell a font name, it'll
			//do a fetch, fail, and then just use a fallback font.
			const id = "fontlink_" + encodeURIComponent(data.font);
			if (!document.getElementById(id)) {
				const elem = document.createElement("link");
				elem.href = "https://fonts.googleapis.com/css2?family=" + encodeURIComponent(data.font) + "&display=swap";
				elem.rel = "stylesheet";
				elem.id = id;
				document.body.appendChild(elem);
			}
		}
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
		}
		elem.style.background = `linear-gradient(.25turn, ${t.fillcolor} ${mark-t.needlesize}%, red, ${t.barcolor} ${mark+t.needlesize}%, ${t.barcolor})`;
		elem.style.display = "flex";
		const f = formatters[t.format] || (x => ""+x);
		set_content(elem, [DIV(text), DIV(f(pos)), DIV(f(goal))]);
	}
	else set_content(elem, data.display);
}
