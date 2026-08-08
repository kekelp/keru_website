<!-- Keru new library

It's got to the point where people are almost annoyed when a new GUI library shows up, because they assume that it's low quality slop and shit, so rather than showing how simple the code for hello world is, I will start with a post about layout.

It uses a new dependency based algorithm for layout. It's better than what CSS and clay do, in the sense that the outputs are straight up better. CSS and clay layout are pretty limited and they just give up very easily when a moderately hard problem shows up.
Show the giraffe.

The dependency system is a much more general solution. -->


This blog post is about the experimental layout system in Keru. It uses a fairly unorthodox layout algorithm based on explicit dependencies between nodes.

When I first started writing Keru, I actually had no strong opinions about layout, and I implemented a very simple system inspired by some blog posts describing SwiftUI's one (it was 2024, so you couldn't ask AI to vomit it out). Unsurprisingly, it had some limitations, and I returned to layout some time later.

This time, I finally discovered that layout is an art more than a science: a layout library offers some layout primitives that the user can compose, but when it comes to solving them and producing real rectangle coordinates, it's sort of common for libraries to do a fairly half-hearted attempt, give out a clearly inconsistent answer, and declare that particular layout unsupported. The example I found was innocent looking giraffe layout, from this blog post: https://mortoray.com/why_ui_layout_calculations_are_slow/

![Giraffe](mortoray-giraffe.webp)

The multi-line paragraph fits to the width of the single-line label. The giraffe fits the height of the whole right section, and its width is half of its height, to preserve the aspect ratio of the bitmap image.

The first thing I did was trying to implementing the `clay` algorithm in Keru, and despite sabotaging myself with a lot of AI assistance, I think I understood its algorithm well enough to conclude that it couldn't possibly solve this case.

To be clear, I don't think this is necessarily a problem: especially in the case of `clay`, which is a library focused on performance and simplicity, there's nothing wrong with sticking to a simpler and faster algorithm if it works for the specific application, and there's plenty of GUI programs which only use simple layouts that don't run into any of these problems. 
Maybe it could have a section on its site explaining which cases are supported and which aren't, but I don't blame them for not going through this effort.

I also did some experiments with CSS layout, and concluded that it couldn't solve it either. This is a lot harder because of how incredibly complicated CSS is: it's still entirely possible that CSS can solve this problem just fine, and I just wasn't able to get it to work.

However, my conclusion for now is that layout algorithms work by a series of top-down or bottom-up tree traversals, and the dependencies in the giraffe example just don't line up with the traversals. As the original giraffe blog post notes, solving an complicated dependency graph by doing multiple passes until everything is solved leads to exponential complexity, so the algorithms cut some corners. Sometimes they get away with memoization, but sometimes they just give up.

To 





## The data layout matters?

Keru is an experimental library that hasn't gone through any real-world testing, so there might still be many good reasons why you shouldn't do your layout like this after all. However, I was still surprised that I couldn't find anyone discussing an approach like this even in blog posts or internet discussions.
The common wisdom just seems to be that layout algorithms are implemented with a series of tree-order traversals, usually with some memoization.

One exception is the old Cassowary constraint solver. It seems to have a bit of a bad reputation as an over-engineered historical oddity compared to the modern approaches, so it's probably fair to not consider it part of the current-day common wisdom. And in any case, its constraint system didn't look much like the dependency algorithm in Keru either.

Obviously there's no single answer for why this ended up being the case, but it leads me to an interesting consideration about how the way in which the data layout of the tree may affect the choice of algorithms.

In the dark ages of programming, there was a common idea that the way to build a tree of nodes was to put each node in a separate heap allocation, and have the node's parent hold the pointer to it, because it "owns" it.

This means that a node is literally only accessible from its parent. In this situation, it's not surprising that most algorithms end up looking like a sequence of tree-order traversals!

In the style of programming that I use, on the other hand, all nodes are stored in a top-level container like a slotmap, slab, hashmap, or even a plain Vec in simpler cases. Then, parent-child relationships are encoded by non-owning `NodeI`s, which are indices of keys into the container.

This is what allows us to model dependencies as simple `{ dependent: NodeI, depends_on: NodeI }` structs, and to access and solve the nodes in arbitrary order when going through the dependencies.

More generally, the idea is to allow the programmer to always have a full bird's eye view on the whole state of the program, and to always have the freedom to access any of it. This is extremely helpful when experimenting with unusual algorithms or when debugging.

There are many other factors in this kind of decision, most importantly the impact on performance of using many separate allocations, and the loss of RAII on the other side. But this is an example that shows how a slotmap-based layout can actually improve the ergonomics, flexibility and understandability of the code as well.


## Performance

Layout is considered to be a fairly slow part of a GUI library's pipeline, so it's natural to wonder about the performance of a new algorithm. 

Unfortunately I don't have a lot of useful information here, as I didn't run any serious benchmarks. 

From an algorithmic complexity point of view, Keru's algorithm doesn't have any major quadratic or exponential scaling on the global number of nodes, and it still boils down to the same per-node calculations, so it's reasonable to expect it to work "fine".

However, I was still curious, so I ran some unserious ones, and compared the results with the ones from this blog post from the PanGui project: https://www.pangui.io/blog/05-layout-rework-and-benchmarks/

PanGui is a C# GUI library which appears to completely evaporate the mature CSS layout implementations in C++ and Rust, Yoga and Taffy. It's not open source yet, so it's not very useful to speculate, but this huge variance is probably caused by much stricter data-oriented programming and cache optimization on PanGui's side, and the pain of strict compliance with the CSS standard on the other. 

What does this mean for us? Again, it's hard to tell without knowing what PanGui is actually doing, but it probably means that any reasonable algorithm is likely fine, as long as it's well-optimized.

Unfortunately, Keru's current implementation of the algorithm is not at all optimized. I usually try to use the heap responsibly, which is often enough to get pretty good performance without much effort. In this case, I didn't even follow my own rule, and made each node hold a heap-allocated `Vec` with a list of the nodes that depend on it.
In addition, the layout algorithm runs on the full GUI nodes, which are huge structs containing a lot of information about the node's display and behavior. Of course, this is not very cache friendly.
These two factors alone are enough to conclude that the current implementation has no hope of utilizing the CPU efficiently.

Another thing to remember, of course, is that I am comparing Keru's numbers from my own CPU with the numbers that they obtained on their completely different CPU. Mine is a AMD Ryzen 7 5800H, running in a laptop from 2021. It's probably a fair bit slower, and Keru might look a bit better compared to Yoga or Taffy in a fairer comparison, but the orders of magnitude wouldn't change.

After all this handwaving, it's still reassuring to see Keru's numbers being in the same order of magnitude Yoga and Taffy:

## Total layout time (lower is better)

| Benchmark                  |   Nodes |     PanGui |       Clay |      Taffy |       Yoga |       keru |
|:---------------------------|--------:|-----------:|-----------:|-----------:|-----------:|-----------:|
| wide_no_wrap_simple_few    |   1,001 |  0.0412 ms |  0.0343 ms |  0.2507 ms |  0.1921 ms |  0.2286 ms |
| wide_no_wrap_simple_many   | 100,001 |  4.6859 ms |          — | 48.6879 ms | 28.5494 ms | 51.0822 ms |
| flex_expand_equal_weights  |  15,001 |  1.0659 ms |  0.6220 ms |  5.3728 ms |  4.8458 ms |  7.4206 ms |
| nested_vertical_stack      |  10,001 |  0.6461 ms |  0.3551 ms |  3.7867 ms |  2.9214 ms |  3.6699 ms |
| percentage_and_ratio       |  10,001 |  0.4398 ms |          ? |  3.3133 ms |  2.9622 ms |  3.1916 ms |
| expand_with_max_constraint |   3,001 |  0.2077 ms |          — |  1.6222 ms |  1.6559 ms |  1.0274 ms |
| fit_nesting                | 101,111 |  6.6357 ms |  4.0009 ms |110.9751 ms | 60.0391 ms | 98.3934 ms |

## Time per node (lower is better)

| Benchmark                  |   Nodes |    PanGui |      Clay |     Taffy |      Yoga |      keru |
|:---------------------------|--------:|----------:|----------:|----------:|----------:|----------:|
| wide_no_wrap_simple_few    |   1,001 |  41.16 ns |  34.27 ns | 250.45 ns | 191.91 ns | 228.40 ns |
| wide_no_wrap_simple_many   | 100,001 |  46.86 ns |         — | 486.87 ns | 285.49 ns | 510.82 ns |
| flex_expand_equal_weights  |  15,001 |  71.06 ns |  41.46 ns | 358.16 ns | 323.03 ns | 494.68 ns |
| nested_vertical_stack      |  10,001 |  64.60 ns |  35.51 ns | 378.63 ns | 292.11 ns | 366.96 ns |
| percentage_and_ratio       |  10,001 |  43.98 ns |         ? | 331.30 ns | 296.19 ns | 319.13 ns |
| expand_with_max_constraint |   3,001 |  69.21 ns |         — | 540.55 ns | 551.78 ns | 342.36 ns |
| fit_nesting                | 101,111 |  65.63 ns |  39.57 ns |1097.56 ns | 593.79 ns | 973.12 ns |


To see how an optimized version of this algorithm does, we'll have to wait a bit.