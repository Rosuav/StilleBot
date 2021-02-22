//Generic websocket synchronization handler
//Relies on globals ws_type and ws_group

let handler = null;
let send_socket; //If present, send() is functional.
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
function connect(group)
{
	let socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: ws_type, group}));
		send_socket = socket; //Don't activate send() until we're initialized
	};
	socket.onclose = () => {
		send_socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250, group);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (!handler) return;
		if (data.cmd === "update") handler.render(data, group);
	};
}
//When ready, import the handler code. It'll be eg "/subpoints.js" but with automatic mtime handling.
async function init() {handler = await import(ws_code); connect(ws_group);}
if (document.readyState !== "loading") init();
else window.addEventListener("DOMContentLoaded", init);

export function send(msg) {if (send_socket) send_socket.send(JSON.stringify(msg));}
