package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"prufwerk/evidence"
)

func main() {
	file := flag.String("file", "", "path to I1 evidence JSONL file")
	flag.Parse()

	if *file == "" {
		log.Fatal("usage: i1chaincheck -file <path-to-jsonl>")
	}

	count, err := evidence.VerifyHashChain(*file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[I1 hash-chain] FAIL: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[I1 hash-chain] OK: %d event(s) verified\n", count)
}
