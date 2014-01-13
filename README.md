# Emacs Lisp Caliper

This library provides exactly one function, `caliper-object-size`.
Give it any lisp object and it will deeply compute the total number of
bytes of memory consumed by that object (list, string, vector, etc.).
It could be used to optmize memory usage of an elisp program.

It's not possible to get exact byte counts for complex built-in types,
such as hash-tables, buffers, and char-tables so only a rough estimate
is returned based on the elisp-accessible contents.

Requires the predicate dispatch
[predd](https://github.com/skeeto/predd) package.

## Usage

All examples are from x86_64 Debian.

```el
;; Multibyte strings are properly counted.
(caliper-object-size "naïveté")
;; => 41

(caliper-object-size [1 2 3])
;; => 48

(caliper-object-size 1.0)
;; => 8

(caliper-object-size 1)
;; => 0  (elisp uses tagged integers)

(caliper-object-size :foo)
;; => 84

;; Any particular object is only counted once within a composite
;; object, allowing for circular data.
(caliper-object-size '#1=(0 . #1#))
;; => 16

;; Previously seen objects only counted once:
(caliper-object-size '(:foo . :bar))  ;; => 184
(caliper-object-size '(:foo . :foo))  ;; => 100
```
