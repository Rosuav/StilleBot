/*
1) Maintain a counter. Zero it at start of stream? If not, have a command to force it. May also be necessary for other situations.
2) On seeing a chat message from Streamlabs "Tchaikovsky just tipped $9.50!", add 950 to the counter.
3) On seeing any cheer, add the number of bits to the counter.
4) Maintain an array of per-mile thresholds, and (internally) partial sums.
5) Know which mile we are currently on. If that increments, give chat message: "devicatLvlup Mile #2 complete!! noobsGW"
6) Have a web integration. The maintained values will be variables and can go through that system. Full customization via web.
   - Bar colour, font/size, text colour, fill colour
   - Height, width? Or let OBS define that?
   - Do everything through the same websocket that monitor.js uses
*/
