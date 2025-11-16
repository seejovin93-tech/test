package evidence

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/google/uuid"
)

// EvidenceEvent is the core schema for I1 demo events.
// New fields for S1 Day 4:
//   - PrevHash: hash of the previous event line (or "" for first).
//   - Hash:     SHA-256 over the JSON of this event WITHOUT the Hash field.
type EvidenceEvent struct {
	EventID      string    `json:"event_id"`
	TimestampUTC time.Time `json:"timestamp_utc"`

	ActorType string `json:"actor_type"`
	ActorID   string `json:"actor_id"`

	EventType string `json:"event_type"`
	Decision  string `json:"decision"`

	CorrelationID string `json:"correlation_id,omitempty"`
	ImageRef      string `json:"image_ref,omitempty"`
	DemoStep      string `json:"demo_step,omitempty"`

	PrevHash string `json:"prev_hash,omitempty"`
	Hash     string `json:"hash,omitempty"`
}

// AppendAdmissionDecision appends a single ADMISSION_DECISION event
// to the given JSONL evidence file, maintaining a simple hash chain.
func AppendAdmissionDecision(path string, correlationID string, decision string, imageRef string, demoStep string) error {
	ev := EvidenceEvent{
		EventID:      uuid.NewString(),
		TimestampUTC: time.Now().UTC(),

		ActorType: "system",
		ActorID:   "i1log-cli",

		EventType: "ADMISSION_DECISION",
		Decision:  decision,

		CorrelationID: correlationID,
		ImageRef:      imageRef,
		DemoStep:      demoStep,
	}

	return appendWithHash(path, &ev)
}

// appendWithHash populates PrevHash + Hash and appends the JSON line.
func appendWithHash(path string, ev *EvidenceEvent) error {
	prevHash, err := lastHash(path)
	if err != nil {
		return fmt.Errorf("get last hash: %w", err)
	}
	ev.PrevHash = prevHash

	// Compute hash over JSON without the Hash field.
	evCopy := *ev
	evCopy.Hash = ""
	payload, err := json.Marshal(evCopy)
	if err != nil {
		return fmt.Errorf("marshal (no-hash): %w", err)
	}

	sum := sha256.Sum256(payload)
	ev.Hash = hex.EncodeToString(sum[:])

	final, err := json.Marshal(ev)
	if err != nil {
		return fmt.Errorf("marshal (with-hash): %w", err)
	}

	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return fmt.Errorf("open evidence file: %w", err)
	}
	defer f.Close()

	if _, err := f.Write(final); err != nil {
		return fmt.Errorf("write json: %w", err)
	}
	if _, err := f.Write([]byte("\n")); err != nil {
		return fmt.Errorf("write newline: %w", err)
	}

	return nil
}

// lastHash returns the Hash of the last non-empty line in the file,
// or "" if the file does not exist or has no events.
func lastHash(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	var lastLine string
	for scanner.Scan() {
		line := scanner.Text()
		if line != "" {
			lastLine = line
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}

	if lastLine == "" {
		return "", nil
	}

	var ev EvidenceEvent
	if err := json.Unmarshal([]byte(lastLine), &ev); err != nil {
		return "", fmt.Errorf("parse last evidence line: %w", err)
	}

	return ev.Hash, nil
}

// VerifyHashChain replays the file and checks:
//   - prev_hash for event N matches hash of event N-1 (or "" for first)
//   - hash matches SHA-256(payload_without_hash)
func VerifyHashChain(path string) (int, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)

	var (
		prevHash string
		index    int
	)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		index++

		var ev EvidenceEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			return index, fmt.Errorf("line %d: invalid json: %w", index, err)
		}

		// prev_hash check
		expectedPrev := ""
		if index > 1 {
			expectedPrev = prevHash
		}
		if ev.PrevHash != expectedPrev {
			return index, fmt.Errorf("line %d: prev_hash mismatch: have %q want %q", index, ev.PrevHash, expectedPrev)
		}

		// hash check (recompute)
		evCopy := ev
		evCopy.Hash = ""
		payload, err := json.Marshal(evCopy)
		if err != nil {
			return index, fmt.Errorf("line %d: marshal no-hash: %w", index, err)
		}

		sum := sha256.Sum256(payload)
		expectedHash := hex.EncodeToString(sum[:])
		if ev.Hash != expectedHash {
			return index, fmt.Errorf("line %d: hash mismatch: have %q want %q", index, ev.Hash, expectedHash)
		}

		prevHash = ev.Hash
	}
	if err := scanner.Err(); err != nil {
		return index, err
	}

	return index, nil
}
