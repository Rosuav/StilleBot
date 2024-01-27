//Generic websocket synchronization handler
//Relies on globals ws_type and ws_group
//NOTE: While it is certainly possible to connect to multiple sockets, reconnection
//information is global. So the progressive back-off will work a little oddly, and
//more importantly, we assume that ALL sockets can be redirected safely to the same
//destination.

let default_handler = null;
let send_socket, send_sockets = { }; //If populated, send() is functional.
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
let pending_message = null; //Allow at most one message to be queued on startup (will be sent after initialization)
let prefs = { }; //Updated from the server as needed
const prefs_hooks = [];
let reconnect_delay = 250;
let redirect_host = null, redirect_xfr = null;

let userid = 0;
export function get_userid() {
	if (userid) return userid;
	//Otherwise, see if the server provided a logged_in_as variable on startup.
	try {return logged_in_as;}
	catch (e) {return 0;}
}

export function connect(group, handler)
{
	if (!handler) handler = default_handler;
	const autorender = handler.autorender || { };
	if (handler.render_item && handler.render_parent) { //Compatibility
		autorender.item_parent = handler.render_parent;
		autorender.item = handler.render_item;
		autorender.item_empty = handler.render_empty;
	}
	if (!autorender.all) autorender.all = Object.keys(autorender).filter(k => autorender[k] && autorender[k + "_parent"]);
	const cfg = handler.ws_config || { };
	if (!cfg.quiet) cfg.quiet = { };
	function verbose(kwd, ...msg) {if (!cfg.quiet[kwd]) console.log(...msg)}
	let socket = new WebSocket(protocol + (redirect_host || window.location.host) + "/ws");
	socket.onopen = () => {
		reconnect_delay = 250;
		verbose("conn", "Socket connection established.");
		const msg = {cmd: "init", type: handler.ws_type || ws_type, group};
		if (redirect_host && redirect_xfr) msg.xfr = redirect_xfr;
		socket.send(JSON.stringify(msg));
		//NOTE: It's possible that the server is about to kick us (for any of a number of reasons,
		//including that the bot is shutting down, we need to be a mod, or the type/group is just
		//plain wrong). The socket_connected hook is still called in these situations, sending is
		//permitted, etc. There's currently no way to be 100% sure that you have a connection until
		//you receive some sort of message (most sockets will send cmd:update on startup).
		if (handler.socket_connected) handler.socket_connected(socket);
		else if (handler.ws_sendid) send_sockets[handler.ws_sendid] = socket;
		else send_socket = socket; //Don't activate send() until we're initialized
		if (pending_message) {socket.send(JSON.stringify(pending_message)); pending_message = null;}
		window.__socket__ = socket; window.__handler__ = handler;
	};
	socket.onclose = () => {
		if (handler.socket_connected) handler.socket_connected(null);
		else send_socket = null;
		verbose("conn", "Socket connection lost.");
		setTimeout(connect, reconnect_delay, group, handler);
		if (reconnect_delay < 5000) reconnect_delay *= 1.5 + 0.5 * Math.random(); //Exponential back-off with a (small) random base
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		if (!handler) {console.log("Got message from server:", data); return;}
		let unknown = "UNKNOWN ";
		if (data.cmd === "update") {
			//If partial rendering is possible, we need an item renderer and a parent, and
			//optionally *_empty() to special-case the "no items" display. If *_empty()
			//returns a DOM element, that element will be destroyed upon any future non-empty
			//render; otherwise, you are responsible to "un-empty" the display as appropriate.
			//Note that something rendered on empty may or may not be a child of the parent.
			if (data.id) {
				const type = data.type || "item", ren = autorender[type], par = autorender[type + "_parent"];
				if (ren && par) {
					const obj = par.querySelector(`[data-id="${data.id}"]`);
					const newobj = data.data && ren(data.data, obj);
					if (newobj) newobj.dataset.id = data.id;
					if (newobj && autorender[type + "_emptydesc"]) {autorender[type + "_emptydesc"].replaceWith(); autorender[type + "_emptydesc"] = null;}
					if (obj && newobj) obj.replaceWith(newobj); //They might be the same
					else if (newobj) par.appendChild(newobj);
					else if (obj) {
						//Delete this item. That might leave the parent empty.
						obj.replaceWith();
						if (autorender[type + "_empty"] && !par.querySelectorAll("[data-id]").length)
							autorender[type + "_emptydesc"] = autorender[type + "_empty"]();
					}
					//else it's currently absent, needs to be absent, nothing to do
				}
			} else autorender.all.forEach(type => {
				const items = data[type + "s"];
				if (items) {
					set_content(autorender[type + "_parent"], items.map(it => {
						const obj = autorender[type](it);
						if (obj) obj.dataset.id = it.id;
						return obj;
					}));
					if (!items.length && autorender[type + "_empty"]) autorender[type + "_emptydesc"] = autorender[type + "_empty"]();
					if (items.length && autorender[type + "_emptydesc"]) {autorender[type + "_emptydesc"].replaceWith(); autorender[type + "_emptydesc"] = null;}
				}
			});
			//Note that render() is called *after* render_item in all cases.
			handler.render(data, group);
			unknown = "";
		}
		else if (data.cmd === "prefs_replace") {
			const oldprefs = prefs;
			prefs = data.prefs;
			userid = data.userid;
			prefs_hooks.forEach(p => {
				if (!p.key) p.func(prefs);
				else if (prefs[p.key] !== oldprefs[p.key]) p.func(prefs[p.key]);
			});
			unknown = "";
		}
		else if (data.cmd === "prefs_update") {
			for (let k in data.prefs) prefs[k] = data.prefs[k];
			prefs_hooks.forEach(p => {
				//Note: We assume that the server only sends us what's changed, so we'll
				//push a change through for everything that's in the update message.
				if (!p.key) p.func(prefs);
				else if (data.prefs[p.key]) p.func(prefs[p.key]);
			});
			unknown = "";
		}
		else if (data.cmd === "*DC*") {
			verbose("conn", "Kicked by server", data);
			//The server's kicking us. If we're VERY fortunate, we'll be told of an alternative
			//place to connect. Otherwise, well, I guess it's back to the retry loop.
			socket.close();
			//If these are non-null, they can be used, otherwise we'll return to default.
			//A simple packet of {"cmd": "*DC*"} will cause us to revert to normal.
			redirect_host = data.redirect; redirect_xfr = data.xfr;
			return;
		}
		const f = handler["sockmsg_" + data.cmd];
		if (f) {f(data); unknown = "";}
		verbose(unknown ? "unkmsg" : "msg", "Got " + unknown + "message from server:", data);
	};
}
//When ready, import the handler code. It'll be eg "/subpoints.js" but with automatic mtime handling.
async function init() {default_handler = await import(ws_code); connect(ws_group);}
if (document.readyState !== "loading") init();
else window.addEventListener("DOMContentLoaded", init);

export function send(msg, sendid) {
	const quiet = default_handler?.ws_config?.quiet?.send;
	if (!quiet) console.log("Sending to " + (sendid ? sendid + " socket" : "server") + ":", msg);
	const sock = send_sockets[sendid] || send_socket;
	if (sock) sock.send(JSON.stringify(msg));
	else pending_message = msg; //NOTE: Pending-send always goes onto the first socket to get connected. Would be nice to separate by sendid.
}
//Usage: prefs_notify("favs", favs => {...})
//Or: prefs_notify(prefs => {...})
//With a key, will notify with the value of that key, when it changes
//Without a key, will notify on all changes to all prefs.
//Note that, on startup, keyless notifications are always called, but
//keyed notifications are only called if there is a value set.
export function prefs_notify(key, func) {
	if (!func) {func = key; key = null;}
	prefs_hooks.push({key, func});
}
export function get_prefs() {return prefs;}
