let socket;
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
//Map the CSS attributes on the server to the names used in element.style
const css_attribute_names = {color: "color", font: "fontFamily", whitespace: "white-space"};

function update_display(elem, data) {
	while (elem.lastChild) elem.removeChild(elem.lastChild);
	elem.appendChild(document.createTextNode(data.text));
	//Update styles. If the arbitrary CSS setting isn't needed, make sure it is "" not null.
	if (data.css || data.css === "") {
		elem.style.cssText = data.css;
		for (let attr in css_attribute_names) {
			if (data[attr]) elem.style[css_attribute_names[attr]] = data[attr];
		}
		if (data.fontsize) elem.style.fontSize = data.fontsize + "px"; //Special-cased to add the unit
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
