MeshChat
========

MeshChat for AREDN (in Lua). MeshChat has become the defacto standard
chat application for AREDN networks. A number of features make it easy
to implement and use:

* Installable on AREDN firmware and most any Linux distribution
* Automatic synchronization between nodes using the same service name
* No account creation necessary--users access using call sign
* Simple user interface

History of MeshChat
-------------------

This is the history of the various MeshChat versions that have existed--at
least to the best of my knowledge.

### MeshChat v0.4 - v1.02

This was the original version of MeshChat written by Trevor Paskett (K7FPV)
around 2015. It was written in Perl and worked well on the limited resources
of the AREDN nodes. Around 2018 Trevor was not able to or not interested
in supporting MeshChat any longer, it is unclear which but the project
became stagnant at version v1.01 in August of 2018. There was a final
release of v1.02 in September 2022 that mostly added a few patches and
support for Debian Stretch.

The K7FPV code base still exists at https://github.com/tpaskett/meshchat.

In addition Trevor wrote a good amount of documentation for his versions
which is still pretty well covers the current versions of MeshChat.
The documentation can be found over at his blog, https://github.com/tpaskett/meshchat.

### MeshChat v2.0 - v2.8

When AREDN firmware v3.22.6.0 was released in June 2022, the AREDN development
team stopped including Perl in the distribution in favor of LUA. In preparation
of this change Tim Wilkinson (KN6PLV) started rewriting MeshChat in LUA
March 2022 with the first release of the new code base in April 2022. The
new MeshChat code continued to receive bug fixes for a year. At which
time Tim's involvement on the AREDN development team prevented him from
continuing to maintain MeshChat.

### Future of MeshChat

That brings the story upto the current time, September 2023, where I,
Gerard Hickey (WT0F), have started to be the maintainer of the MeshChat
code base. There has already been work to restructure the repository to
make working with the code more effective and to automatically build
packages when a release occurs.

There are a number of bug fixes and incremental improvements that will be
released in v2.9.

If you are looking for a feature to be implemented or find a bug, please
be sure to [create an issue](https://github.com/hickey/meshchat/issues/new)
in the project so that it can be prioritized.


