package main

import (
	"flag"
	"fmt"
	"log"

	"prufwerk/evidence"
)

func main() {
	outPath := flag.String("out", "", "path to I1 evidence JSONL file")
	correlationID := flag.String("correlation_id", "", "correlation id for this demo run")
	decision := flag.String("decision", "", "decision (ALLOW or DENY)")
	imageRef := flag.String("image_ref", "", "container image reference (e.g. docker.io/seejovin93/prufwerk:latest)")
	demoStep := flag.String("demo_step", "", "demo step label (e.g. C6_SIGNED_PATH, C7_UNSIGNED_PATH)")

	flag.Parse()

	if *outPath == "" {
		log.Fatal("missing required flag: -out <evidence-file-path>")
	}
	if *decision == "" {
		log.Fatal("missing required flag: -decision (ALLOW or DENY)")
	}
	if *imageRef == "" {
		log.Fatal("missing required flag: -image_ref")
	}
	if *demoStep == "" {
		log.Fatal("missing required flag: -demo_step")
	}

	if err := evidence.AppendAdmissionDecision(
		*outPath,
		*correlationID,
		*decision,
		*imageRef,
		*demoStep,
	); err != nil {
		log.Fatalf("append admission decision evidence: %v", err)
	}

	fmt.Printf(
		"[I1] Appended event: decision=%s image=%s step=%s correlation_id=%s -> %s\n",
		*decision,
		*imageRef,
		*demoStep,
		*correlationID,
		*outPath,
	)
}
