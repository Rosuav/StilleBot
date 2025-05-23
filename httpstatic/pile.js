const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
//NOTE: For debugging and testing, background and fillStyle are both colours. For
//production, they should be transparent, with actual elements for interaction purposes.
const visible_walls = false;
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: visible_walls ? "aliceblue" : "transparent", width, height,
}});
const Rectangle = Matter.Bodies.rectangle;
//The ground and walls. TODO: Add config to specify which walls should have barriers.
//NOTE: The position appears to be the *middle* of the object, not the top-left.
//The floor should have some thickness to it, to prevent weird bouncing.
//TODO: Make the height of the side walls configurable
Matter.Composite.add(engine.world, Rectangle(width / 2, height + 28, width + 10, 60,
	{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
Matter.Composite.add(engine.world, Rectangle(-28, height * 7 / 8, 60, height / 4 + 10,
	{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
Matter.Composite.add(engine.world, Rectangle(width + 28, height * 7 / 8, 60, height / 4 + 10,
	{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;
window.renderer = renderer; //For debugging, eg toggle wireframes mode

//Map a category ID to the array of things
const thingcategories = { };
//Map category ID to the server-provided information about it
let thingtypes = { };
let fadeouttime = 0, fader = 0;
export function render(data) {
	if (data.data?.fadeouttime) fadeouttime = +data.data?.fadeouttime;
	if (data.data?.things) thingtypes = Object.fromEntries(data.data.things.map(t => [t.id, t]));
	if (data.newcount) Object.entries(data.newcount).forEach(([thingtype, newcount]) => {
		const cat = thingtypes[thingtype];
		if (!cat) return;
		if (!thingcategories[thingtype]) thingcategories[thingtype] = [];
		const things = thingcategories[thingtype];
		while (things.length > newcount) Matter.Composite.remove(engine.world, things.pop());
		while (things.length < newcount) {
			const img = cat.images[Math.floor(Math.random() * cat.images.length)] || default_thing_image;
			const scale = cat.xsize / img.xsize;
			const obj = Rectangle(Math.floor(Math.random() * (width - cat.xsize - 30) + cat.xsize / 2 + 15), Math.floor(Math.random() * 100 + 10), cat.xsize, Math.ceil(img.ysize * scale), {
				render: {sprite: {
					texture: img.url,
					//xOffset: cat.xoffset || 0, yOffset: cat.yoffset || 0, //Not currently configured on the back end
					xScale: scale, yScale: scale, 
				}},
				restitution: 0.25, //Make 'em a little bit bouncier
			});
			//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
			//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
			//taken into account). Provide each newly-added element with a bit of rotation, either direction.
			Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
			Matter.Composite.add(engine.world, obj);
			things.push(obj);
			//A new thing has been added! Make the pile visible.
			document.body.classList.remove("invisible");
			clearTimeout(fader);
			if (fadeouttime) fader = setTimeout(() => {fader = 0; document.body.classList.add("invisible")}, fadeouttime * 60000 - 5000);
		}
	});
}
ws_sync.send({cmd: "querycounts"});

//Demo mode? Emote dropping mode?
if (0) setInterval(() => {
	const cat = thingtypes.emotes; //TODO: User selection from the available categories
	if (!cat) return;
	const img = cat[Math.floor(Math.random() * cat.length)];
	const obj = Rectangle(Math.floor(Math.random() * width), Math.floor(Math.random() * 100 + 10), img.xsize, img.ysize, {
		render: {sprite: {texture: img.url, xOffset: img.xoffset, yOffset: img.yoffset}},
	});
	//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
	//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
	//taken into account). Provide each newly-added element with a bit of rotation, either direction.
	Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
	Matter.Composite.add(engine.world, obj);
}, 2000);
//TODO: If stable mode is selected, then after adding something, set a quarter-second interval timer to
//check the newly created thing's speed, and if it's low enough, setStatic() on it.
//Alternatively, set everything to Sleeping? Wake them up when something new is added?
/* Next steps:

* Create an object type ("category", need a good name for it)
* Upload an image for an object type - may be done more than once. If not done, will use Mustard Mine squavatar.
* Builtin to manipulate objects
  - Needs a type. Will only manipulate objects of that type.
  - Add N (default to 1), remove N (default to 1), or set to N on screen
    - "+1", "-1", "1"?
* Handle objects falling off the bottom?
* On the edit dlg, button to add/remove objects given a type

*/
