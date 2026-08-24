# The Luam Manifesto

Lua's own creators put it plainly: "From the start, Lua was designed to be simple, small, portable, fast, and easily embedded into applications. These design principles are still in force, and we believe that they account for Lua's success in industry." (Ierusalimschy, de Figueiredo, Celes, "The Evolution of Lua", HOPL III, 2007). Lua's own description of itself adds the mechanism behind that simplicity: "a fundamental concept in the design of Lua is to provide meta-mechanisms for implementing features, instead of providing a host of features directly in the language" (lua.org).

Luam doesn't start from a blank page against those goals. It starts by keeping every one of them as a hard constraint, unchanged, and then asks a narrower question: where did that same instinct stop short of the syntax itself? The tenets below are that question, answered one decision at a time -- both the ones Luam has already made and the standard a new one has to clear.

## 1. Borrow the goals before touching the language

Simple, small, portable, fast, embeddable -- Lua's four founding goals are Luam's four founding goals, verbatim. `doc/changelog.md` exists to measure them, not assume them: source size within 0.3% of upstream Lua 5.1, a stripped interpreter binary a few percent larger, checked against the real built artifact rather than estimated. Any change to Luam gets checked against those same numbers before it ships. If it can't be measured, it isn't done.

## 2. One mechanism, not a feature per need

Lua's own "vivid expression of its simplicity," in its creators' words, is that it offers a single data structure -- the table -- instead of a separate built-in for arrays, records, sets, and objects. Luam applies the identical instinct to syntax rather than data: one loop construct (`while`, no `repeat`/`until`), one way to introduce a variable (bare assignment, no `local`), one way to call a function on a table (`obj.method(obj, ...)`, no colon sugar). Where Lua unified data structures, Luam unifies the grammar around them.

## 3. Meta-mechanisms over built-in policy

Metatables, `getfenv`, and `setfenv` stay fully enabled in Luam -- not despite the drive toward simplicity, but because of it. Sandboxing untrusted code and supporting vendored libraries that expect Lua 5.1 semantics are needs Lua's own meta-mechanisms already meet; inventing a second, Luam-specific sandboxing primitive on top would be exactly the "host of features" Lua's design explicitly avoided. A real need gets met with the mechanism that's already there before anyone reaches for a new one.

## 4. Subtraction is allowed to be the feature

Lua's own history, by its creators' account, is additive: lexical scoping, coroutines, and anonymous functions were added because they closed a genuine expressiveness gap, never to offer a second way to do something Lua could already do. Luam, free of Lua's install base and backward-compatibility obligations, runs that identical discipline in the opposite direction: `repeat`/`until`, colon-call sugar, and truthy coercion aren't gaps -- they're second ways to do something Lua already had one way to do. Removing them is the same standard applied in reverse, not a break from it.

## 5. A restriction earns its place by removing a decision, not adding a rule

Implicit locals aren't a style-guide line that says "always write `local`" -- the second option is gone, so there's nothing left to enforce. Strict conditionals aren't a linter warning about truthy coercion -- there's no truthy value left to coerce. A proposed change that would need a paragraph in a style guide to be used correctly is a policy; the version worth shipping is the one that's a mechanism instead, where the wrong way to do it simply doesn't compile.

## 6. Small stays measured, not claimed

`doc/changelog.md` exists in its current, careful form because earlier drafts of these documents -- and a whole separate size-comparison doc, since deleted -- asserted numbers that didn't hold up against the real binary. Every claim about size, safety, or behavior gets verified against the actual built interpreter before it goes in a doc. This isn't a Luam invention; it's the same independent-benchmark habit Lua's own creators point to as part of why Lua earned trust in the first place.

## 7. Extend the library, not the language

New capability -- `bcrypt`, `sqlite`, `mariadb`, sockets, `yaml`, and the rest of `lib/` -- is added as a library, written in Lua/Luam and C, the same extension path Lua itself has always offered through its C API. It is never added as new syntax. The language core stays the fixed, small thing everyone can hold in their head; the surface area that's allowed to grow lives one layer up, opt-in per file that `require`s it.

## 8. One real need is the only justification for a change

Lua grew when its creators' own projects ran into genuine gaps, not because a feature seemed generally useful. Luam holds itself to the same standard, at the same source: no change lands speculatively, on the strength of "a general-purpose language should probably have this." It lands because a real, currently-blocked need -- daat's, or an equivalent -- demonstrated the gap first.
