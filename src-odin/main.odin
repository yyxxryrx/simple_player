package main

@(export = true)
add :: proc "c" (a, b: i32) -> i32 {
	return a + b
}
