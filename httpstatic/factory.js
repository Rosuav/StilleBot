/* The Chocolate Factory (Thanks to DeviCat for the name!)

Documentation: https://rosuav.github.io/choc/

The MIT License (MIT)

Copyright (c) 2022 Chris Angelico

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

export function DOM(sel) {
	const elems = document.querySelectorAll(sel);
	if (elems.length > 1) throw new Error("Expected a single element '" + sel + "' but got " + elems.length);
	return elems[0]; //Will return undefined if there are no matching elements.
}

//Append one child or an array of children
function append_child(elem, child) {
	if (!child || child === "") return;
	if (Array.isArray(child)) {
		//TODO maybe: prevent infinite nesting (array inside itself)
		for (let c of child) append_child(elem, c);
		return;
	}
	if (typeof child === "string" || typeof child === "number") child = document.createTextNode(child);
	if (child instanceof Node) elem.appendChild(child);
	else throw new Error("Attempted to insert non-Node object into document",
		{cause: {elem, child}});
}

export function set_content(elem, children) {
	if (arguments.length > 2) console.warn("Extra argument(s) to set_content() - did you intend to pass an array of children?");
	if (typeof elem === "string") {
		const el = DOM(elem);
		if (!el) throw new Error("No element found for set_content: '" + elem + "'");
		elem = el;
	}
	while (elem.lastChild) elem.removeChild(elem.lastChild);
	append_child(elem, children);
	return elem;
}

const handlers = {};
export function on(event, selector, handler, options) {
	if (handlers[event]) return handlers[event].push([selector, handler]);
	handlers[event] = [[selector, handler]];
	document.addEventListener(event, e => {
		//Reimplement bubbling ourselves. Note that the cancelBubble attribute is
		//deprecated, but still seems to work (calling e.stopPropagation() will
		//set this attribute), so we use it.
		const top = e.currentTarget; //Generic in case we later allow this to attach to other than document
		let cur = e.target;
		while (cur && cur !== top && !e.cancelBubble) {
			e.match = cur; //We can't mess with e.currentTarget without synthesizing our own event object. Easier to make a new property.
			handlers[event].forEach(([s, h]) => cur.matches(s) && h(e));
			cur = cur.parentNode;
		}
		e.match = null; //Signal that you can't trust the match ref any more
	}, options);
	return 1;
}

//Apply some patches to <dialog> tags to make them easier to use. Accepts keyword args in a config object:
//	fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});
//For older browsers, this adds showModal() and close() methods
//If cfg.close_selector, will hook events from all links/buttons matching it to close the dialog
//If cfg.click_outside, any click outside a dialog will also close it. (May not work on older browsers.)
export function fix_dialogs(cfg) {
	if (!cfg) cfg = {};
	//For browsers with only partial support for the <dialog> tag, add the barest minimum.
	//On browsers with full support, there are many advantages to using dialog rather than
	//plain old div, but this way, other browsers at least have it pop up and down.
	let need_button_fix = false;
	document.querySelectorAll("dialog").forEach(dlg => {
		if (!dlg.showModal) {
			dlg.showModal = function() {this.style.display = "block";}
			dlg.close = function(ret) {
				if (ret) this.returnValue = ret;
				this.style.removeProperty("display");
				this.dispatchEvent(new CustomEvent("close", {bubbles: true}));
			};
			need_button_fix = true;
		}
	});
	//Ideally, I'd like to feature-detect whether form[method=dialog] actually
	//works, and do this if it doesn't; we assume that the lack of a showModal
	//method implies this being also unsupported.
	if (need_button_fix) on("click", 'dialog form[method="dialog"] button', e => {
		e.match.closest("dialog").close(e.match.value);
		e.preventDefault();
	});
	if (cfg.click_outside) on("click", "dialog", e => {
		//NOTE: Sometimes, clicking on a <select> will give spurious clientX/clientY
		//values. Since clicking outside is always going to send the message directly
		//to the dialog (not to one of its children), check for that case.
		if (e.match !== e.target) return;
		if (cfg.click_outside === "formless" && e.match.querySelector("form")) return;
		let rect = e.match.getBoundingClientRect();
		if (e.clientY < rect.top || e.clientY > rect.top + rect.height
				|| e.clientX < rect.left || e.clientX > rect.left + rect.width)
		{
			e.match.close();
			e.preventDefault();
		}
	});
	if (cfg.close_selector) on("click", cfg.close_selector, e => e.match.closest("dialog").close());
}

//Compatibility hack for those attributes where not ret[attr] <=> ret.setAttribute(attr). Might be made externally mutable? Maybe?
const attr_xlat = {classname: "class", htmlfor: "for"};
const attr_assign = {volume: 1, value: 1, disabled: 1, checked: 1}; //Another weird compat hack, no idea why

//Exported but with no guarantee of forward compatibility, this is (currently) for internal use.
export function _set_attr(elem, attr, val) {
	if (attr[0] === '.') elem[attr.slice(1)] = val; //Explicit assignment. Doesn't use xlat, though maybe it should do it in reverse?
	else if (attr[0] === '@') { //Explicit set-attribute
		attr = attr.slice(1);
		elem.setAttribute(attr_xlat[attr.toLowerCase()] || attr, val);
	}
	//Otherwise pick what we think is most likely to be right. It often won't matter,
	//in which case we'll setAttribute by default.
	else if (attr.startsWith("on") || attr_assign[attr]) elem[attr] = val; //Events should be created with on(), but can be done this way too.
	else elem.setAttribute(attr_xlat[attr.toLowerCase()] || attr, val);
}

export const xmlns_xlat = {svg: "http://www.w3.org/2000/svg"};

let choc = function(tag, attributes, children) {
	const parts = tag.split(":");
	const tagname = parts.pop(), ns = parts.join(":");
	const ret = ns
		? document.createElementNS(xmlns_xlat[ns] || ns, tagname) //XML element with namespace eg choc("svg:svg")
		: document.createElement(tagname); //HTML element
	//If called as choc(tag, children), assume all attributes are defaults
	if (typeof attributes === "string" || typeof attributes === "number" || attributes instanceof Array || attributes instanceof Element) {
		//But if called as choc(tag, child, child), that was probably an error.
		//It's also possible someone tried to call choc(tag, child, attr); in
		//that case, the warning will be slightly confusing, but still point to
		//the right place.
		if (children) console.warn("Extra argument(s) to choc() - did you intend to pass an array of children?");
		return set_content(ret, attributes);
	}
	if (attributes) for (let attr in attributes) _set_attr(ret, attr, attributes[attr]);
	if (children) set_content(ret, children);
	//Special case: A <select> element's value is valid only if one of its child <option>s
	//has that value. Which means that the value can only be set once it has its children.
	//So in that very specific case, we reapply the value here at the end.
	if (attributes && children && attributes.value && ret.tagName === "SELECT") {
		ret.value = attributes.value;
	}
	if (arguments.length > 3) console.warn("Extra argument(s) to choc() - did you intend to pass an array of children?");
	return ret;
}

export function replace_content(target, template) {
	if (typeof target === "string") target = DOM(target);
	let was = target ? target._CHOC_template : [];
	if (!was) {
		//The first time you use replace_template, it functions broadly like set_content.
		set_content(target, "");
		was = [];
	}
	if (!Array.isArray(template)) template = [template];
	//In recursive calls, we could skip this JSONification. Note that this breaks embedding
	//of DOM elements, functions in on* attributes, etc. It's best done externally if needed.
	//template = JSON.parse(JSON.stringify(template)); //Pay some overhead to ensure separation
	let nodes = 0; //Number of child nodes, including the contents of subarrays and pseudoelements.
	let pristine = true; //False if we make any change, no matter how slight. Err on the side of setting it false unnecessarily.
	function build_content(was, now) {
		let ofs = 0, limit = Math.abs(was.length - now.length);
		let delta = was.length < now.length ? -1 : 1;
		now._CHOC_keys = {};
		if (was.length !== now.length) pristine = false;
		function poke(t, pred) {
			//Flag everything that we've used, and refuse to use anything flagged,
			//because you can't step in the same river twice.
			if (t && !t.key && !t.river && pred(t)) {t.river = 1; return t;}
		}
		function search(i, pred) {
			//Attempt to find an unkeyed entry that matches the predicate
			let t;
			if (t = poke(was[i + ofs * delta], pred)) return t;
			pristine = false;
			//Search for a match in the direction of the array length change
			let prevofs = ofs;
			if (limit) for (++ofs; ofs <= limit; ++ofs)
				if (t = poke(was[i + ofs * delta], pred)) return t;
			ofs = prevofs; //If we don't find the thing, reset the search for next time.
		}
		return now.map((t, i) => {
			//Strings never get usefully matched. In theory we could search for
			//the corresponding text node, to avoid creating and destroying them,
			//but in practice, the risk of mismatch means we'd have to do a lot
			//of validation, reducing the savings, so we may as well stay simple.
			if (!t) {if (was[i]) pristine = false; return "";} //Skip any null entries of any kind
			//Strings and numbers get passed straight along to Choc Factory. Elements
			//will be kept as-is, so you can move things around by tossing DOM() into
			//your template.
			if (typeof t === "string" || typeof t === "number") {
				if (was[i] !== t) pristine = false;
				++nodes;
				return t;
			}
			if (t instanceof Element) {
				//DOM elements get passed through untouched, and removed from the template.
				if (was[i] !== null) pristine = false;
				now[i] = null;
				++nodes;
				return t;
			}
			if (Array.isArray(t)) {
				//Match an array against another array. Note that an "array with a key"
				//is actually represented as a keyed pseudoelement, not an array.
				//It is NOT recommended to have a variable number of unkeyed arrays in
				//an array, as any array will match any other array, potentially causing
				//widespread deletion and recreation. In this situation, give them keys.
				//Note that node counts are not affected by arrays themselves, only their contents.
				return build_content(search(i, Array.isArray) || [], t);
			}
			//Assume t is an object.
			if (t.key) {
				if (now._CHOC_keys[t.key]) console.warn("Duplicate key on element!", t); //No guarantees here.
				now._CHOC_keys[t.key] = t;
			}
			t.position = nodes;
			let match = null;
			if (t.key) {
				const prev = was._CHOC_keys && was._CHOC_keys[t.key];
				if (prev && prev.tag === t.tag) match = prev; //Has to match both key and tag.
			} else {
				//Attempt to find a match based on tag alone.
				const tag = t.tag;
				match = search(i, x => x.tag === tag);
			}
			//Four possibilities:
			//1) Match found, has tag. Update DOM element and return it.
			//2) Match found, no tag. Generate a pseudoelement, reusing as appropriate.
			//3) No match, has tag. Generate a DOM element.
			//4) No match, no tag. Generate a pseudoelement.
			if (match) {
				if (!t.tag) return build_content(match.children, t.children);
				const elem = target.childNodes[match.position];
				if (elem && elem.tagName === match.tag.toUpperCase()) {
					//Okay, we have a match. Update attributes, update content, return.
					let value = undefined;
					for (let old in match.attributes)
						//TODO: Translate these through attr_xlat and attr_assign somehow
						if (!(old in t.attributes)) {pristine = false; elem.removeAttribute(old);}
					for (let att in t.attributes)
						if (!(att in match.attributes) || t.attributes[att] !== match.attributes[att]) {
							if (elem.tagName === "INPUT" && att === "value") {
								//Special-case value to better handle inputs. If you update
								//the template to the value it currently has, it's not a
								//change; and if you don't update the value at all, it's not
								//a change either, to allow easy unmanaged inputs.
								if (elem.value === t.attributes[att]) continue;
							}
							pristine = false;
							_set_attr(elem, att, t.attributes[att]);
							if (elem.tagName === "SELECT" && att === "value") value = t.attributes.value;
						}
					//The element will retain its own record of its contents.
					++nodes;
					replace_content(elem, t.children);
					if (typeof value !== "undefined") elem.value = value;
					//Set focus back to an element that previously had it.
					if (elem === document.activeElement) setTimeout(() => elem.focus(), 0);
					return elem;
				}
				//Else fall through and make a new one. Any sort of DOM manipulation
				//that disrupts the position markers could cause a mismatch and thus
				//a lot of element creation and destruction, but that's better than
				//trying to set attributes onto the wrong type of thing.
			}
			if (!t.tag) return build_content([], t.children); //Pseudo-element - return the array as-is.
			pristine = false;
			++nodes;
			const elem = replace_content(choc(t.tag, t.attributes), t.children);
			if (elem.tagName === "SELECT" && "value" in t.attributes) elem.value = t.attributes.value;
			else if (elem.tagName === "SELECT" && ".value" in t.attributes) elem.value = t.attributes[".value"];
			return elem;
		});
	}
	if (!target) return build_content(was, template)[0];
	target._CHOC_template = template;
	//If absolutely nothing has changed - not even text - don't set_content.
	//This will be a common case for recursive calls to replace_content, where the
	//corresponding section of the overall template hasn't changed.
	const content = build_content(was, template);
	//If anything's left to be removed, though, it's not pristine. This includes
	//any DOM elements directly inserted (which won't have a .river attribute),
	//and any Lindt template objects that haven't been probed.
	was.forEach(t => {
		if (t && typeof t === "object" && !Array.isArray(t) && !t.river) pristine = false;
	});
	if (pristine) return target;
	return set_content(target, content);
}

//TODO: Unify lindt and choc. Maybe have choc call lindt and then render?
let lindt = function(tag, attributes, children) {
	if (arguments.length > 3) console.warn("Extra argument(s) to lindt() - did you intend to pass an array of children?");
	if (!children && typeof tag === "object") return lindt("", tag, attributes); //Pseudoelement - lindt({key: "..."}, [...])
	if (!attributes) attributes = { };
	if (typeof attributes === "string" || typeof attributes === "number" || Array.isArray(attributes) || attributes instanceof Element || attributes.tag) {
		if (children) console.warn("Extra argument(s) to lindt() - did you intend to pass an array of children?");
		children = attributes;
		attributes = { };
	}
	if (!children) children = [];
	else if (!Array.isArray(children)) children = [children];
	return {tag, attributes, children, key: attributes.key};
};

//Interpret choc.DIV(attr, chld) as choc("DIV", attr, chld)
//This is basically what Python would do as choc.__getattr__()
function autobind(obj, prop) {
	if (prop in obj) return obj[prop];
	return obj[prop] = obj.bind(null, prop);
}
choc = new Proxy(choc, {get: autobind});
lindt = new Proxy(lindt, {get: autobind});

choc.__version__ = "1.7.3";

//For modules, make the main entry-point easily available.
export default choc;
export {choc, lindt};

//For non-module scripts, allow some globals to be used. Also useful at the console.
window.choc = choc; window.set_content = set_content; window.on = on; window.DOM = DOM; window.fix_dialogs = fix_dialogs;
