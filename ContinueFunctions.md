Asynchronicity, Concurrent.Future, and continue functions
=========================================================

Pike has excellent features for running asynchronous code, such as a server that
handles large numbers of clients, performs database requests, and so on. Useful
abstractions over the basics of callbacks include promises/futures and continue
functions, which work together to create elegant single-threaded code which looks
as clean and readable as threaded code.

(NOTE: All descriptions here are based on Pike 8.1.4 as of mid-2021. If someone
wants to adjust things to match a specific 8.0 or 8.2 release, feel free.)

Concurrent.Future and its friends
---------------------------------

Continue Functions
------------------

Asynchronous functions with yield points
----------------------------------------
