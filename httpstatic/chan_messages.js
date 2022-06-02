import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, IMG, LI, SPAN} = choc;
import {waitlate} from "$$static||utils.js$$";

/* PROBLEM: With two connections (personal and mod-shared), there's no easy way
to know which socket to send signals on. Each socket needs to get signals for
its own group. Will need some facility inside ws_sync itself for distinguishing
send destinations.
*/

const full_date_format = new Intl.DateTimeFormat('default', {
	weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
	hour: 'numeric', minute: 'numeric', second: 'numeric',
});
const date_format = new Intl.DateTimeFormat('default', {
	weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
});
const time_format = new Intl.DateTimeFormat('default', {
	hour: 'numeric', minute: 'numeric', second: 'numeric',
});
function date_display(date) {
	let shortdate;
	if (date.toLocaleDateString() === new Date().toLocaleDateString())
		//Message is from today. Show the timestamp only.
		shortdate = time_format.format(date);
	else
		//Older message. Show the date only. Either way, hover for full timestamp.
		shortdate = date_format.format(date);
	return SPAN({className: "date", title: full_date_format.format(date)}, " [" + shortdate + "] ");
}

const ctx_personal = {lastread: -1, parent: DOM("#messages")};
const ctx_mod = {lastread: -1, parent: DOM("#modmessages")};
let mod_sock = null;
function is_unread(id, ctx) {
	if (ctx.lastread === -1) return false; //How should messages display before we know whether they're unread or read?
	return (+id) > ctx.lastread;
}

export const render_parent = DOM("#messages");
function render_message(msg, ctx) {
	set_content("#loading", "");
	return LI({"data-id": msg.id, className: is_unread(msg.id, ctx) ? "unread" : ""}, [
		BUTTON({type: "button", className: "confirmdelete"}, "🗑"),
		date_display(new Date(msg.received * 1000)),
		msg.parts ? SPAN(msg.parts.map(p =>
			typeof(p) === "string" ? p :
			p.type === "link" ? A({href: p.href || p.text}, p.text) :
			p.type === "image" ? IMG({src: p.url, title: p.text, alt: p.text}) :
			p.text //Shouldn't happen, but if we get an unknown type, just emit the text
		)) : msg.message,
		msg.acknowledgement && " ",
		msg.acknowledgement && BUTTON({type: "button", className: "acknowledge", title: "Will respond with: " + msg.acknowledgement}, "Got it, thanks!"),
	]);
}
export function render_item(msg) {return render_message(msg, ctx_personal);}

function mark_as_read(data, ctx) {
	//On startup, we ask the server to mark everything as Read, but we keep the unread
	//status from prior to this mark.
	if (data.why === "startup") ctx.lastread = data.was;
	else ctx.lastread = data.now;
	ctx.parent.querySelectorAll("[data-id]").forEach(el => {
		el.className = is_unread(el.dataset.id, ctx) ? "unread" : "";
	});
}
export function sockmsg_mark_read(data) {mark_as_read(data, ctx_personal);}

export function render_empty() {set_content("#loading", "You have no personal messages from this channel.");}
export function render(data) {
	if (ctx_personal.lastread === -1) ws_sync.send({cmd: "mark_read", why: "startup"});
}

on("click", ".confirmdelete", waitlate(750, 5000, "Delete?", e => {
	const li = e.match.closest("li");
	if (!li.dataset.id) li.replaceWith();
	else if (!li.closest("#modmessages")) ws_sync.send({cmd: "delete", id: li.dataset.id});
	else if (mod_sock) mod_sock.send(JSON.stringify({cmd: "delete", id: li.dataset.id}));
}));

on("click", "#mark_read", e => {
	ws_sync.send({cmd: "mark_read", why: "explicit"});
	if (mod_sock) mod_sock.send(JSON.stringify({cmd: "mark_read", why: "explicit"}));
});

on("click", ".acknowledge", e => {
	const li = e.match.closest("li");
	const id = li.dataset.id; if (!id) return;
	delete li.dataset.id;
	li.classList.add("soft-deleted");
	if (!li.closest("#modmessages")) ws_sync.send({cmd: "acknowledge", id});
	else mod_sock.send(JSON.stringify({cmd: "acknowledge", id}));
});

if (ws_extra_group) ws_sync.connect(ws_extra_group, {
	ws_type: "chan_messages", ws_sendid: "modmsgs",
	render_parent: DOM("#modmessages"),
	render_item: msg => render_message(msg, ctx_mod),
	render: function(data) {if (ctx_mod.lastread === -1) mod_sock.send(JSON.stringify({cmd: "mark_read", why: "startup"}));},
	socket_connected: sock => mod_sock = sock,
	sockmsg_mark_read: data => mark_as_read(data, ctx_mod),
});
