Rewriting my blog using Hakyll, GHCJS
=====================================

(Originally posted by Justin Le [http://blog.jle.im/])

It’s been almost a year since my last post! Things have been a bit
hectic with research and related things, and with the unrelenting
publishing cycle, any time I can get to write or explore has been a
great escape.

Admittedly, I’ve also run into some friction updating my blog because it
was a compiled web server with some delicate dependencies and required
environment configuration to build/deploy. It was written/built at a
time when a lot of the infrastructure we have now in the Haskell
ecosystem either wasn’t there, or wasn’t mature. We didn’t have easy
[Heroku deployment](https://haskellonheroku.com/), and we didn’t have
great tools like [stack](http://haskellstack.org/) to let us create
reproducible builds. One of my [first
posts](http://blog.jle.im/entry/deploying-medium-to-large-haskell-apps-to-heroku.html)
in 2013 was actually about hoops to jump through *just* to get a simple
Heroku deployment. I’ve had to maintain a virtual machine just to
compile and push changes!

My blog was one of my first Haskell projects ever, and if I had started
it now, in 2016, things would definitely be a bit different. But, it’s
been long enough and the slight inconveniences have been building up
enough that I thought it’d be time to sit down and finally migrate my
“first large-ish Haskell project” and bring it into modern times, by
using [hakyll](https://jaspervdj.be/hakyll/) and
[ghcjs](https://github.com/ghcjs/ghcjs). Here are my thoughts and
observations on how the migration went, with insight on Haskell
migrations in general!

Hakyll
------

To be fair, there was little actual practical reasons why my site wasn’t
static to begin with. The main reason, feature-wise, was for me to be
able to schedule blog posts and updates without requiring me to actually
re-render and re-push every time I wanted to make a post. But, the real
underlying reason was that it was my first Haskell project, and I wanted
to take the opportunity to be able to learn how to interface with
databases in Haskell.

Now that that learning process is behind me, I felt free to throw it all
out the window and rewrite things to be a completely 100% static site!

[Hakyll](https://jaspervdj.be/hakyll/) was great; it’s basically like a
very specialized *make*-like tool for building sites. It takes a bit of
time to get used to “thinking in Hakyll” — generating standalone pages
instead of just ones based off of files, getting used to the
identifier/snapshot system — but once you do, things go pretty smoothly.
I started thinking about snapshots as customized “object files” that you
can leave behind in the process of creating pages that other pages can
use. Hakyll manages all the dependencies for you, so pages that depend
on the things left from other pages will be sequenced properly, and
rebuilding your website only requires rebuilding pages that depend on
files you changed. Neat!

Before, I had gotten the impression that Hakyll was mostly for
generating “simple”, pre-built blog layouts, but I was able to use
Hakyll (without much friction, at all) to generate the complex,
intricate, and arbitrary site map that I had designed on my first run. I
definitely recommend it for any static site generating needs, blogs or
not.

An unforeseen consequence of the static-site-hosted-by-github-pages
approach, however, is that I don’t have any control over MIME types
anymore (or 301 redirects), so I had to do some migrations to move pages
over to “.html” and set up redirects and stuff, but those were made
super simple with Hakyll.

Migrating Haskell
-----------------
