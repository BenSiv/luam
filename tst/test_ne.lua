-- != replaces ~= as the inequality operator.

assert(1 != 2, "!= should be true for unequal values")
assert((1 != 1) == false, "!= should be false for equal values")

print("PASS != operator check")
