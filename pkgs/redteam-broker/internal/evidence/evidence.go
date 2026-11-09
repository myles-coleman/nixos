package evidence

import (
	"encoding/json"
	"os"
	"sync"
	"time"
)

// Event is one broker decision. Task 5 replaces this simple emitter with the
// hash-chained JSONL writer; the interface is stable.
type Event struct {
	Seq          int64  `json:"seq"`
	Time         string `json:"time"`
	ActionHash   string `json:"action_hash"`
	ScopeVersion int    `json:"scope_version"`
	TechniqueID  string `json:"technique_id"`
	Decision     string `json:"decision"`
	Reason       string `json:"reason"`
	Destination  string `json:"destination"`
	Nonce        string `json:"nonce,omitempty"`
}

// Emitter is the broker's evidence sink.
type Emitter interface {
	Emit(Event) error
}

// Noop discards events. It keeps the broker buildable before Task 5 lands.
type Noop struct{}

func (Noop) Emit(Event) error { return nil }

// JSONL is a simple append-only sink for Stage 1. Task 5 adds the hash chain.
type JSONL struct {
	Path string
	mu   sync.Mutex
	seq  int64
}

func (j *JSONL) Emit(event Event) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.seq++
	event.Seq = j.seq
	event.Time = time.Now().UTC().Format(time.RFC3339Nano)

	file, err := os.OpenFile(j.Path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()

	data, err := json.Marshal(event)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		return err
	}
	return file.Sync()
}
