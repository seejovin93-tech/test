package main

import (
	"flag"
	"log"

	"prufwerk/evidence"
)

func main() {
	var (
		outPath       string
		eventType     string
		decision      string
		imageRef      string
		demoStep      string
		correlationID string
	)

	flag.StringVar(&outPath, "out", "evidence/logs/i1/demo_i1_events.jsonl", "output JSONL path")
	flag.StringVar(&eventType, "event_type", "ADMISSION_DECISION", "event type")
	flag.StringVar(&decision, "decision", "", "decision: ALLOW or DENY")
	flag.StringVar(&imageRef, "image_ref", "", "container image ref")
	flag.StringVar(&demoStep, "demo_step", "", "demo step label")
	flag.StringVar(&correlationID, "correlation_id", "", "correlation ID for this demo run")
	flag.Parse()

	if decision == "" {
		log.Println("decision is required (ALLOW or DENY)")
		return
	}

	evt := evidence.I1Event{
		ActorType:     "system",
		ActorID:       "i1log-cli",
		EventType:     eventType,
		Decision:      decision,
		ImageRef:      imageRef,
		DemoStep:      demoStep,
		CorrelationID: correlationID,
	}

	if err := evidence.AppendI1Event(outPath, evt); err != nil {
		log.Fatalf("append event: %v", err)
	}
}
