---
layout: post
title: "Vibe Coding"
date: 2026-05-01T19:00:00.000+01:00
categories: review book
version: 1.0.1
---

I desperately wanted something from this book it failed to provide.

A measured, engineer-led analysis of AI tooling and its use in practical engineering.
Not so much an antidote to the endless 2026 hype train, but something that just ignored it.
That neither bellowed fear nor favour. That gave me the dispassionate engineer's guide to productivity improvements in this new domain.

## How I got here

That desire is born from the encounters I've had with these tools over the last few years.

The impressive toy of Dall-E and ChatGPT 3, quickly turned to the question "Is this useful?"
Early answers didn't seem great to me. Impressive snippets of code did seem to quickly surpass stack overflow searches - but just as often as SO, ended up in dead ends. Disheartened I became a fan of the [stochastic parrot critique](https://pluralistic.net/tag/stochastic-parrots/). These word guessing machines, recombinant idiots.

I never really stopped using it though, just achieved very little of value. During this time the technology crept forward, from chat windows and copy pasting into my Integrated Development Environment. The IDE move was a step change, with greater access, context it felt like I could do more. It certainly showed itself capable of ejecting vast quantities of reasonable looking code, but the outcomes never seemed to arrive.

In parallel the great hype train thundered around me. AI was forcibly injected into every tool, largely irrespective of user demand or needs. Optimism abounded, often from the most senior roles about productivity leaps - or workforce rearrangements.

AI marketing pulled off the hushed tones of reverence and even fear for their own products. AI safety managing to satisfy both, I think, a genuinely held fear of the smart technologists who work on the tools - and a meme of awesome power to get their products on the minds of consumers. Daytime TV used to abound with demonstrations of knives so sharp they could "cut cans". AI gets presented with an air of reverence:

> Take this knife, it's very sharp, it will cut anything you want. In fact, beware! Fear the knife! If improperly handled it could slice through the floor and plummet to the very centre of the world.

The technology is so new and the early demos so startling, so easily confused with actual intelligence due to [ELIZA effects](https://en.wikipedia.org/wiki/ELIZA_effect) this hype felt believable.

I think this hype has ultimately been toxic for the tool and its adoption with many technologists. Two things are simultaneously true. The first is that we should beware the claims of radical productivity transformation following Fred Brooks:

> there is no single development, in either technology or management technique, which by itself promises even one order of magnitude [tenfold] improvement within a decade in productivity, in reliability, in simplicity.

and even

> we cannot expect ever to see two-fold gains every two years

I think these remain true, despite AI.

None the less, it is also true that there have been productivity advances.

Compilers, Integrated Development Environments, High Level Languages, the invention of HTML. Conceptual advances in architecture and the arrangement of our code for better maintenance, encapsulation, ports and adaptors. Quality drives that shift our woes to the left where they can be quietly and quickly plugged before they can be shared more broadly.

What strikes me most is that the AI debate is presented as an entirely ahistorical development in software. A breakthrough of magnificent proportions that will upend Brooks's law. I may be wrong in my skepticism, but we must see that as an extraordinary claim in this industry, one I have yet to see extraordinary and conclusive evidence to support.

Without that evidence, we have a paradox. Our most senior leaders, seem to hold few views on the productivity gains of pairing, test driven development, feature rich and well tuned developer environments, deploy chains. These are delegated, nerd chat. Yet the enormous pressure to adopt _this_ tool stands out. It speaks to an absolute rift in certainty - that they are the ushers and vanguard for a historical break, and I am merely trying to figure out what this new knife will cut.

The hype has been toxic for a certain class of technologist. An imposition, a violation of subsidiarity, a groupthink of wishful thinking from a place of optimism. I fell largely into that and toyed with AI but rarely attempted meaningful projects with it.

Until March 2026, when I tried the generation of terminal based tools like `claude` and `codex`. The terminal forms the root of nearly all my work and interaction with my machine. Anything I can do via a graphical user interface there's usually a way to do via terminal. On top of that it can work across and through all these programmes in one place, chaining together inputs and outputs in ways that require manual copy paste at a higher level.

Exposing good AI tooling in this space has been a gamechanger, and it can be seen in my GitHub contribution burn chart. Mostly a list of projects, long deferred until I "had a free afternoon", became progressible in increments of 30 mins. Outcomes appeared, things shipped and I began to feel a sense of joy and enthusiasm for the act of _making things_ I realise I haven't felt now since the early days of learning to develop software.

I still think we ought to take great care over these feelings. We must walk the line of doublethink - seeing an opportunity here, but I believe one of evolution not revolution. One that could leave the door open to radical changes, like our non-coding peers gradually moving to write and ship more code. Perhaps our jobs transforming as a result.

That can be true without being ahistorical, without violating Brooks's law. Without turning out to have merited all the senior managerial optimism, and indeed all the investment - and so being both a benefit and a disappointment.

## What I didn't get

I desperately wanted something from this book it failed to provide.

I wanted a discussion among peer engineers, free of the hype - neither desperate to convince me to use AI, nor apologetic about its use. I wanted something like a discussion of how to get the most out of my vim bindings, how to orchestrate my IDE, friendly comparison of CI/CD pipelines. I thought the authors of the Phoenix project, hands that contributed to my beloved DORA suite of metrics, contributions from within the engineering workforce would get me there.

But it largely didn't.

This is not a good book, it marvels at the involvement of AI in its own writing - but feels like a stolid AI chat output. It _insists_ on telling you what it will tell you, telling you it, then telling you what it told you. It does so in a repetitious and nested way, each point wrapped in padding at the chapter, section and book level. It often felt like more bubblewrap than content.

The first parts are overwhelmingly hype - their own version of my story above.

It left me asking, who is this book for? Potential converts? Swing voters? The converted?
I don't know if the book knows itself, and not having a clear audience muddled its recommendations.

I came away thinking, as I have with a few books lately, this could have been a blog post.

## What I did

There are few useful concepts in here that I will go forward with. The core analogy of moving from "line cook" to "head chef" is an appealing vision. I've certainly done my fair share of what feels like the engineering equivalent of peeling potatoes and chopping onions. How much time has been spent on low cognitive boiler plate, and how much on real subjective problem solving. I can see a route to outsource that. I am intrigued by the agentic implications and playing more with those options. Though it's still unclear to me how well these tools orchestrate at scale, how maintainable the outputs are and how cost effective this will be in the long run.

There was a small section in the later chapters on context management. It has gotten me intrigued in a tendency for models to lower the quality of output the more context they have to wrangle. My previous attempts were to dump as much as I possibly can into the chat, cling to long conversation histories and make offhand references to earlier parts of the chat to progress.

Context management now leads me to small concise tasks, often farmed out to sub agents, punctuated by recordable outputs. Go investigate {x}, report back findings, discuss, now write me an issue then pack up. Next agent takes the issue afresh, has all it needs, makes a change with fierce limits on scope and clear CI/CD guidelines to pass. A third agent reviews and offers suggestions. A fourth debates back, discusses with me if we agree or should resolve the responses.

I still feel a limited set of empirical tools to test if this works better, but it _feels_ like it does. Though with a literal cost in additional token usage (one that begins to bite at high usage in 2026 constraints), and the potential of more time taken.

Those contributions make the book worth having read, but not worth recommending to read. The insights can likely be picked up more quickly and cheaply from blogposts or short posts at the same resolution, but much quicker.

I still feel a pining for an adult, empirical, technically informed conversation with peers about AI and tooling. Until then I muddle through with my own experiments and try to tune out the ecosystem noise.

I am disappointed to not find what I needed from this book.
