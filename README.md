# ZigString
A prototype for a zig lang String class.
Uses SIMD or linear operations.
For index it uses a String.Index struct{gr,cp} instead of a usize number to do O(1) instead of O(n) while presenting the user with a grapheme interface,
so the user is only interested in the `Index.gr` (grapheme index) field.

Does everything checking grapheme cluster boundaries.. recently I found
a function that doesn't.. gonna fix it soon.
