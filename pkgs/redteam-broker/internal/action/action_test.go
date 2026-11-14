package action

import "testing"

func TestCanonicalHashIsStable(t *testing.T) {
	first := Action{
		EngagementID: "stage1-demo",
		ScopeVersion: 1,
		TechniqueID:  "http.get",
		Target:       "10.99.0.2",
		Parameters:   map[string]string{"path": "/ftp/", "method": "GET"},
	}
	second := Action{
		EngagementID: "stage1-demo",
		ScopeVersion: 1,
		TechniqueID:  "http.get",
		Target:       "10.99.0.2",
		Parameters:   map[string]string{"method": "GET", "path": "/ftp/"},
	}

	firstHash, err := first.Hash()
	if err != nil {
		t.Fatal(err)
	}
	secondHash, err := second.Hash()
	if err != nil {
		t.Fatal(err)
	}
	if firstHash != secondHash {
		t.Fatalf("map order changed the hash: %s != %s", firstHash, secondHash)
	}

	first.Parameters["path"] = "/rest/admin/application-version"
	changedHash, err := first.Hash()
	if err != nil {
		t.Fatal(err)
	}
	if changedHash == firstHash {
		t.Fatal("changing a parameter did not change the hash")
	}
}

func TestCanonicalBytesMatchVector(t *testing.T) {
	a := Action{
		EngagementID: "e",
		ScopeVersion: 1,
		TechniqueID:  "http.get",
		Target:       "10.99.0.2",
		Parameters:   map[string]string{"path": "/"},
	}
	got, err := a.Canonical()
	if err != nil {
		t.Fatal(err)
	}
	want := `{"engagement_id":"e","parameters":{"path":"/"},"scope_version":1,"target":"10.99.0.2","technique_id":"http.get"}`
	if string(got) != want {
		t.Fatalf("canonical bytes mismatch:\n got: %s\nwant: %s", got, want)
	}
}
