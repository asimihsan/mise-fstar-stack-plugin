module Coincidence

// A simple F* module to test that F*, Z3, and ulib all work together

let add (x y : int) : int = x + y

// Simple proof that add is commutative
let add_comm (x y : int) : Lemma (add x y = add y x) = ()
