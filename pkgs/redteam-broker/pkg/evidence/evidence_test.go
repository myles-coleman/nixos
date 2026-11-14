package evidence

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeEvents(t *testing.T, count int) (string, string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "events.jsonl")
	head := filepath.Join(dir, "head.json")
	writer, err := Open(path, head)
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < count; index++ {
		if err := writer.Emit(Event{
			ActionHash:   "hash",
			ScopeVersion: 1,
			TechniqueID:  "http.get",
			Decision:     "allow",
			Reason:       "allowed",
			Destination:  "10.99.0.2",
		}); err != nil {
			t.Fatal(err)
		}
	}
	return path, head
}

func readLines(t *testing.T, path string) []string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}

func writeLines(t *testing.T, path string, lines []string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestChainVerifies(t *testing.T) {
	path, head := writeEvents(t, 3)
	report, err := Verify(path, head)
	if err != nil {
		t.Fatal(err)
	}
	if !report.OK || report.Records != 3 {
		t.Fatalf("unexpected report: %+v", report)
	}
}

func TestInteriorEditDetected(t *testing.T) {
	path, head := writeEvents(t, 3)
	lines := readLines(t, path)
	var record Record
	if err := json.Unmarshal([]byte(lines[1]), &record); err != nil {
		t.Fatal(err)
	}
	record.Content = json.RawMessage(`{"action_hash":"tampered"}`)
	lines[1] = string(mustJSON(t, record))
	writeLines(t, path, lines)

	report, err := Verify(path, head)
	if err != nil {
		t.Fatal(err)
	}
	if report.OK || report.Failure != "edit" || report.Seq != 2 {
		t.Fatalf("unexpected report: %+v", report)
	}
}

func TestReorderDetected(t *testing.T) {
	path, head := writeEvents(t, 3)
	lines := readLines(t, path)
	lines[1], lines[2] = lines[2], lines[1]
	writeLines(t, path, lines)

	report, err := Verify(path, head)
	if err != nil {
		t.Fatal(err)
	}
	if report.OK || report.Failure != "reorder" {
		t.Fatalf("unexpected report: %+v", report)
	}
}

func TestTailTruncationDetected(t *testing.T) {
	path, head := writeEvents(t, 3)
	lines := readLines(t, path)
	writeLines(t, path, lines[:2])

	report, err := Verify(path, head)
	if err != nil {
		t.Fatal(err)
	}
	if report.OK || report.Failure != "truncated" {
		t.Fatalf("unexpected report: %+v", report)
	}
}

func TestPartialTailRecovery(t *testing.T) {
	path, head := writeEvents(t, 2)
	file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := file.WriteString(`{"seq":3,"prev_hash":"`); err != nil {
		t.Fatal(err)
	}
	file.Close()

	writer, err := Open(path, head)
	if err != nil {
		t.Fatal(err)
	}
	if err := writer.Emit(Event{
		ActionHash:   "hash",
		ScopeVersion: 1,
		TechniqueID:  "http.get",
		Decision:     "deny",
		Reason:       "approval_required",
		Destination:  "10.99.0.2",
	}); err != nil {
		t.Fatal(err)
	}

	report, err := Verify(path, head)
	if err != nil {
		t.Fatal(err)
	}
	if !report.OK || report.Records != 3 {
		t.Fatalf("unexpected report: %+v", report)
	}
}

func mustJSON(t *testing.T, value any) []byte {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return data
}
