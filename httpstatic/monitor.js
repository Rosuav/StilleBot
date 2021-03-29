import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV} = choc;

let socket;
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
//Map the CSS attributes on the server to the names used in element.style
const css_attribute_names = {color: "color", font: "fontFamily", fontweight: "fontWeight", fontstyle: "fontStyle", bordercolor: "borderColor", whitespace: "white-space"};

const currency_formatter = new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"});
function currency(cents) {
	if (cents >= 0 && !(cents % 100)) return "$" + (cents / 100); //Abbreviate the display to "$5" for 500
	return currency_formatter.format(cents / 100);
}

let thresholds = null, fillcolor, barcolor, needlesize = 0.375;
export default function update_display(elem, data, display) { //Used for the preview as well as the live display
	//Update styles. If the arbitrary CSS setting isn't needed, make sure it is "" not null.
	if (data.css || data.css === "") {
		elem.style.cssText = data.css;
		for (let attr in css_attribute_names) {
			if (data[attr]) elem.style[css_attribute_names[attr]] = data[attr];
		}
		if (data.thresholds && data.barcolor) {
			thresholds = data.thresholds.split(" ").map(x => x * 100).filter(x => x && x === x); //Suppress any that fail to parse as numbers
			barcolor = data.barcolor; fillcolor = data.fillcolor || data.barcolor;
			//The rest of the style handling is below, since it depends on the text
		}
		if (data.needlesize) needlesize = +data.needlesize;
		if (data.fontsize) elem.style.fontSize = data.fontsize + "px"; //Special-cased to add the unit
		//It's more-or-less like saying "padding: {padvert}em {padhoriz}em"
		if (data.padvert)  elem.style.paddingTop = elem.style.paddingBottom = data.padvert + "em";
		if (data.padhoriz) elem.style.paddingLeft = elem.style.paddingRight = data.padhoriz + "em";
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
	if (thresholds) {
		const m = /^([0-9]+):(.*)$/.exec(display || data.display || data.text);
		if (!m) {console.error("Something's misconfigured (see monitor.js regex)"); return;}
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
		elem.style.background = `linear-gradient(.25turn, ${fillcolor} ${mark-needlesize}%, red, ${barcolor} ${mark+needlesize}%, ${barcolor})`;
		elem.style.display = "flex";
		set_content(elem, [DIV(text), DIV(currency(pos)), DIV(currency(goal))]);
	}
	else set_content(elem, data.display || data.text);
}

function connect() {
	socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: "chan_monitors", group: window.nonce}));
	};
	socket.onclose = () => {
		socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (data.cmd === "update") update_display(document.getElementById("display"), data);
	};
}
if (window.nonce) connect();
