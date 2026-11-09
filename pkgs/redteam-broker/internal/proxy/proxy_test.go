package proxy

import (
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func startProxy(t *testing.T) string {
	t.Helper()
	socket := filepath.Join(t.TempDir(), "proxy.sock")
	go func() { _ = Serve(socket) }()
	for i := 0; i < 50; i++ {
		if _, err := net.Dial("unix", socket); err == nil {
			return socket
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("proxy did not start")
	return ""
}

func TestDoAllowed(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}))
	defer server.Close()
	host, port, _ := net.SplitHostPort(server.Listener.Addr().String())
	portNumber, _ := net.LookupPort("tcp", port)

	socket := startProxy(t)
	response, err := Do(socket, Request{
		Host:         host,
		Port:         portNumber,
		Method:       "GET",
		Path:         "/",
		AllowedCIDRs: []string{"127.0.0.0/8"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if response.Error != "" || response.Status != 200 || response.Body != "ok" {
		t.Fatalf("unexpected response: %+v", response)
	}
}

func TestDoOutOfScope(t *testing.T) {
	socket := startProxy(t)
	response, err := Do(socket, Request{
		Host:         "127.0.0.1",
		Port:         3000,
		Method:       "GET",
		Path:         "/",
		AllowedCIDRs: []string{"10.99.0.0/24"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if response.Error == "" {
		t.Fatal("expected out-of-scope rejection")
	}
}

func TestDoRejectsFreeForm(t *testing.T) {
	socket := startProxy(t)
	for _, request := range []Request{
		{Host: "127.0.0.1", Port: 3000, Method: "POST", Path: "/", AllowedCIDRs: []string{"127.0.0.0/8"}},
		{Host: "127.0.0.1", Port: 3000, Method: "GET", Path: "http://evil.example/", AllowedCIDRs: []string{"127.0.0.0/8"}},
		{Host: "127.0.0.1", Port: 3000, Method: "GET", Path: "/", Scheme: "ftp", AllowedCIDRs: []string{"127.0.0.0/8"}},
	} {
		response, err := Do(socket, request)
		if err != nil {
			t.Fatal(err)
		}
		if response.Error == "" {
			t.Fatalf("expected rejection for %+v", request)
		}
	}
}
