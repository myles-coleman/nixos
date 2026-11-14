package evidence

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"
)

// Event is the canonical content of one broker decision.
type Event struct {
	Time         string            `json:"time"`
	ActionHash   string            `json:"action_hash"`
	ScopeVersion int               `json:"scope_version"`
	TechniqueID  string            `json:"technique_id"`
	Decision     string            `json:"decision"`
	Reason       string            `json:"reason"`
	Destination  string            `json:"destination"`
	Nonce        string            `json:"nonce,omitempty"`
	Rationale    string            `json:"rationale,omitempty"`
	Artifacts    map[string]string `json:"artifacts,omitempty"`
}

// Record is one line of the chain.
type Record struct {
	Seq      int64           `json:"seq"`
	PrevHash string          `json:"prev_hash"`
	Content  json.RawMessage `json:"content"`
	Hash     string          `json:"hash"`
}

// Head is the sidecar that lets the verifier detect a clean tail truncation.
type Head struct {
	Seq  int64  `json:"seq"`
	Hash string `json:"hash"`
}

// Emitter is the broker's evidence sink.
type Emitter interface {
	Emit(Event) error
}

// Noop discards events. It keeps tests and early wiring simple.
type Noop struct{}

func (Noop) Emit(Event) error { return nil }

// Report is the verifier's result.
type Report struct {
	OK      bool   `json:"ok"`
	Records int64  `json:"records"`
	Head    string `json:"head,omitempty"`
	Failure string `json:"failure,omitempty"`
	Seq     int64  `json:"seq,omitempty"`
}

// Writer appends records to the chain and maintains the head sidecar.
type Writer struct {
	Path     string
	HeadPath string

	mu   sync.Mutex
	seq  int64
	head [32]byte
}

func canonicalEvent(event Event) ([]byte, error) {
	if event.Artifacts == nil {
		event.Artifacts = map[string]string{}
	}
	value := map[string]any{
		"action_hash":   event.ActionHash,
		"artifacts":     event.Artifacts,
		"decision":      event.Decision,
		"destination":   event.Destination,
		"nonce":         event.Nonce,
		"rationale":     event.Rationale,
		"reason":        event.Reason,
		"scope_version": event.ScopeVersion,
		"technique_id":  event.TechniqueID,
		"time":          event.Time,
	}

	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// Open recovers the chain's last valid record and truncates a partial tail.
func Open(path, headPath string) (*Writer, error) {
	writer := &Writer{Path: path, HeadPath: headPath}
	if err := writer.recover(); err != nil {
		return nil, err
	}
	return writer, nil
}

func (w *Writer) recover() error {
	file, err := os.OpenFile(w.Path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return fmt.Errorf("open evidence: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	var offset int64
	var seq int64
	var prev [32]byte
	var lastHash string

	for scanner.Scan() {
		line := scanner.Bytes()
		var record Record
		if err := json.Unmarshal(line, &record); err != nil {
			// A partial tail is a crash, not a rewrite: truncate it and resume.
			if err := file.Truncate(offset); err != nil {
				return fmt.Errorf("truncate partial tail: %w", err)
			}
			break
		}
		if record.Seq != seq+1 {
			return fmt.Errorf("evidence sequence gap at %d", record.Seq)
		}
		if record.PrevHash != hex.EncodeToString(prev[:]) {
			return fmt.Errorf("evidence prev_hash mismatch at %d", record.Seq)
		}
		expected := hashContent(record.Content, prev)
		if record.Hash != hex.EncodeToString(expected[:]) {
			return fmt.Errorf("evidence hash mismatch at %d", record.Seq)
		}
		seq = record.Seq
		prev = expected
		lastHash = record.Hash
		offset += int64(len(line)) + 1
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("scan evidence: %w", err)
	}

	w.seq = seq
	w.head = prev
	if lastHash != "" {
		return w.writeHead()
	}
	return nil
}

// Emit appends one canonical event and fsyncs it.
func (w *Writer) Emit(event Event) error {
	w.mu.Lock()
	defer w.mu.Unlock()

	if event.Time == "" {
		event.Time = time.Now().UTC().Format(time.RFC3339Nano)
	}
	canonical, err := canonicalEvent(event)
	if err != nil {
		return err
	}

	prev := w.head
	sum := hashContent(canonical, prev)
	record := Record{
		Seq:      w.seq + 1,
		PrevHash: hex.EncodeToString(prev[:]),
		Content:  canonical,
		Hash:     hex.EncodeToString(sum[:]),
	}
	data, err := json.Marshal(record)
	if err != nil {
		return err
	}

	file, err := os.OpenFile(w.Path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("open evidence for append: %w", err)
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		_ = file.Close()
		return fmt.Errorf("append evidence: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync evidence: %w", err)
	}
	if err := file.Close(); err != nil {
		return err
	}

	w.seq++
	w.head = sum
	return w.writeHead()
}

func (w *Writer) writeHead() error {
	if w.HeadPath == "" {
		return nil
	}
	head := Head{Seq: w.seq, Hash: hex.EncodeToString(w.head[:])}
	data, err := json.Marshal(head)
	if err != nil {
		return err
	}
	temp := w.HeadPath + ".tmp"
	if err := os.WriteFile(temp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(temp, w.HeadPath)
}

func hashContent(content []byte, prev [32]byte) [32]byte {
	payload := make([]byte, 0, len(content)+len(prev))
	payload = append(payload, content...)
	payload = append(payload, prev[:]...)
	return sha256.Sum256(payload)
}

// Verify checks the chain and, when a head sidecar exists, the tail.
func Verify(path, headPath string) (Report, error) {
	file, err := os.Open(path)
	if err != nil {
		return Report{}, fmt.Errorf("open evidence: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	var prev [32]byte
	var seq int64
	var lastHash string

	for scanner.Scan() {
		var record Record
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			return Report{Failure: "invalid_json", Seq: seq + 1}, nil
		}
		if record.Seq != seq+1 || record.PrevHash != hex.EncodeToString(prev[:]) {
			return Report{Failure: "reorder", Seq: record.Seq}, nil
		}
		expected := hashContent(record.Content, prev)
		if record.Hash != hex.EncodeToString(expected[:]) {
			return Report{Failure: "edit", Seq: record.Seq}, nil
		}
		seq = record.Seq
		prev = expected
		lastHash = record.Hash
	}
	if err := scanner.Err(); err != nil {
		return Report{}, err
	}

	if headPath != "" {
		data, err := os.ReadFile(headPath)
		if err == nil {
			var head Head
			if json.Unmarshal(data, &head) == nil && (head.Seq != seq || head.Hash != lastHash) {
				return Report{Failure: "truncated", Seq: seq}, nil
			}
		}
	}

	return Report{OK: true, Records: seq, Head: lastHash}, nil
}
