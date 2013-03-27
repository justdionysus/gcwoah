## Conservative GC for Memory Disclosure

Seeing some cool memory disclosure work come out recently (e.g. [GDTR on Hashtable Timing Attacks](http://gdtr.wordpress.com/2012/08/07/leaking-information-with-timing-attacks-on-hashtables-part-1/) and [Timing Attacks against KASLR](http://www.reddit.com/r/netsec/comments/1a2kv0/)) I was motivated to try out an idea I've had for a bit but had never got around to testing.  I've spent quite a bit of time reading the source to various interpreter engines (Spider|Trace|IonMonkey, Tamarin, V8, and JavascriptCore).  One subsystem that always scares the pants off me is the garbage collection (GC) implementations.  In an effort to balance interactivity and reasonable memory footprints, modern garbage collection (I guess like everything else in a browser) is complex but finely tuned.  Optimizations are scattered throughout and, in any competitive engine, the code is always in motion.  Despite the complexity, most engines have done a good job of maintaining a high degree of stability in the GC portion. Maybe this is due to necessity; GC bugs would cause easy to notice problems (I'd imagine most are crashers). The part that tickles my security senses is the native stack walk necessary for conservative GC.  Let me explain.

All modern browser JS engines (ok, I don't know anything about IE) use a technique called mark and sweep.  There are variations and qualifiers to tweak how and when the algorithm does what it does, but I'll explain the gist of it without getting too comic-book-guy-ee.  Mark and sweep attempts to find all runtime objects that are in use, mark those, and then sweep anything not marked into the allocators dustpan.  To perform this marking operation, a set of *root* objects are used to seed a worklist.  As long as there are items in the worklist, the next object is taken off the list.  The object is examined to determine any references it is keeping to other objects.  For example, an Array object will iterate over the stored array marking each object and adding it to the worklist if it was not already marked.  Once this is complete, the allocator will walk allocated objects looking for unmarked objects to finalize and free.  There are nuances to this, but I think this short description will suffice (for more info, use google or mxr -- there are quite a few academic papers on garbage collection techniques as well).

I mentioned the notion of *root* objects above. Root objects are things like the scope stack(holding the scope -- a list of objects and identifiers -- for each method or function in the callstack down to the global scope), and a set of native objects (like timers hold JS callbacks, for example).  Unfortunately, a wrench is thrown into these plans when executing native code.  Native code, implementing the DOM or the built-in objects for example, takes these objects and may call back into JS through a callback interleaving native and managed code.  Without requiring native code to adhere to a strict protocol for rooting objects kept on the stack, the garbage collection is forced to scan the native stack looking for values that walk and talk like a runtime object reference.  Since this may lead to over-marking, this is called "conservative" garbage collection; the GC is conservative in what it marks erring on the side of over-marking since under-marking would lead to object lifetime bugs like use-after-frees.

The GC performs this marking by simply walking the stack from top to bottom running each aligned word through a heuristic and marking the object if it passed the check.  The heuristic is simple: is this value a pointer into an allocator page that is both allocated and not yet marked?  The idea is that if the attacker can detect when an object is garbage collected this knowledge can be converted into the heap address of that object.  Some engines provide elegant ways to detect if an object has been finalized. Other engines make it very difficult.  I should also say that some engines, like Chrome's V8, appear to use precise collection and escape this sort of disclosure.  Also, IonMonkey (Firefox's current engine) is on the way to precise stack marking (but not quite there yet).

Getting something on the stack is easy for most engines -- JITing engines tend to optimize argument passing and use the raw values for integers and doubles instead of the packed or tagged runtime representation.  Simply calling a script function with a few doubles was enough to observe this value being checked in both Tamarin and IonMonkey.

Let's do the easy one first.  Anyone want to guess?  Yes, that's right: Tamarin, the engine in Adobe Flash Player.  Tamarin supports the creation of "weak key" [Dictionary objects](http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/utils/Dictionary.html#Dictionary()).  A Dictionary is a mapping from Objects to Objects. If created with weak keys, the keys in the Dictionary are not considered a reference during GC. The Dictionary object also supports iteration.  These two features allow the attacker to disclose when an object is garbage collected by adding the object as a key in the weak dictionary and then checking the size (by iterating over it) to determine if the key has been removed from the Dictionary.

The general idea is to step through the address space guessing addresses.  One trial at a time we can place an address on the stack as a double floating point value. Since the GC algorithm has no way to determine the types of the values stored on the stack the guessed address is interpreted as two pointer values by the GC's heuristic (if that guessed address is allocated). We can determine that the guessed address is equal to an object address if one of the objects in our weak dictionary has not gone away after all of the *real* references to it have been removed by the GC.

Now, I can layout (roughly) the algorithm for performing the disclosure in Tamarin:

    // Iterate over possible heap addresses (complete guesses)
    for each address in candidateAddresses:
        strongs = []
        weaks = new Dictionary(true); // create it with weakKeys
    
        // Spray heap with objects.  Pin them in the GC by storing
        // them in a regular array.  Also put them in the weak Dictionary
        // to detect if they've been finalized.
        strongs = createABunchOfObjects();
        for each obj in strongs:
            weaks[obj] = 1;

        // Place the guessed address on the stack where the GC will 
        // mistakenly try to use it as an Object pointer. 
        putAddressOnStack(address);

        // Remove all "real" references to the sprayed Objects and
        // force a GC.  They should all get cleaned up.
        strongs = [];
        forceGC();

        // If all of the weak references were cleaned up, the stack value
        // didn't match one of those.  Otherwise, we probably pinned (marked)
        // one of the objects still left.
        if (countWeaks() > 0):
            savedObjects = strongs;
            reportHeapAddress(address);

In practice, it isn't *quite* that simple but almost.  The code is [here] and I have the PoC hosted [here](http://www.trapbit.com/demos/gcwoah/GCW.swf).  It seems to work for me on Windows with the latest Flash Player plugin in the 3 big browsers.  If it doesn't work the first time, reload.  It's not 100% but I think it could be tweaked.  Most of the time it takes < 5 seconds.

Next, I tried Firefox.  At first, it was promising.  There is a new ES6 datatype called [WeakMap](https://developer.mozilla.org/en-US/docs/JavaScript/Reference/Global_Objects/WeakMap).  Sounds juicy, right? And it is but smarter people than I have been hard at work predicting these sorts of shenanigans.  For example, see [this](http://wiki.ecmascript.org/doku.php?id=strawman:gc_semantics#confidentiality). To the point, the definition of a WeakMap does not allow iteration.  Another thought was if any unique identifiers, like the timer identifiers, are reused, it would be easy to determine when a timer was finalized -- in FF at least, this doesn't work.  I also considered objects that may have IO side-effects when finalized but I was unable to find anything like that in the short time I searched.  Finally, I went back to the WeakMap and looked at the implementation.

The WeakMap is implemented on top of the regular HashMap. This structure has been used in the past to leak heap addresses using a timing side channel exposed via hash collisions. Instead of the collision side-channel, I used the growth/rehash operation to determine the size of the WeakMap and expose when GC has taken place.  When a hash table reaches 75% capacity, the internal hash table storage is reallocated to double the size and each object is rehashed and copied to the new entry.  After the table becomes a certain size, this rehash is observable via timing.  Measuring the size is done by recording how many objects it takes in addition to the uncertain object before this rehash is observed.  This can be used in general to determine when an object has been finalized. Despite this technique, I was still unable to get a reliable disclosure from FF.  Another problem is the lack of a reliable way to trigger a garbage collection cycle.  My attempt is included here in the repo in case someone wants to take a further stab at it.  There are probably easier ways to go about this.

There is code to do the stack walk in the JavascriptCore GC implementation but I never got around to observing it myself like I did on the other two.  I also never looked at IE -- I'd love to hear if this is possible on IE.  Finally, other interpreters also use this form of GC or have in the past.  I've seen people saying the Hotspot VM used to do conservative GC but that's as far as I got before I lost interest.

This is "only" a heap address disclosure.  Maybe it's impractical to use this sort of technique in a "weaponized" exploit but I found the technique and widespread applicability (well, sort of) interesting enough to share.  Also, I can think of a lot of times knowing a heap address will level-up a vulnerability into something very useful.  Anyway, I hope this was interesting and I'm really curious to see where else this sort of thing pops up.

Oh, and if see any points I'm wrong about above, please let me know (mail to dion@trapbit.com) so I can fix my description.  I've only been goofing with this specific issue for a little more than a week -- I'm sure I've got some stuff incorrect.

