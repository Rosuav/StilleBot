//Generic websocket synchronization handler
//Relies on globals ws_type and ws_group

let handler = null;
let socket;
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
function connect()
{
	socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: ws_type, group: ws_group}));
	};
	socket.onclose = () => {
		socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (!handler) return;
		if (data.cmd === "update") handler.render(data);
	};
}
//When ready, import the handler code. It'll be eg "/subpoints.js" but with automatic mtime handling.
async function init() {handler = await import(ws_code); connect();}
if (document.readyState !== "loading") init();
else window.addEventListener("DOMContentLoaded", init);

export function send(msg) {if (socket) socket.send(JSON.stringify(msg));}
