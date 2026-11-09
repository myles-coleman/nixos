package proxy

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Request is the fixed-framed unit the main broker sends to the lab proxy.
type Request struct {
	Scheme       string   `json:"scheme"`
	Host         string   `json:"host"`
	Port         int      `json:"port"`
	Method       string   `json:"method"`
	Path         string   `json:"path"`
	AllowedCIDRs []string `json:"allowed_cidrs"`
	MaxBytes     int64    `json:"max_bytes"`
}

// Response is the proxy's fixed-framed answer.
type Response struct {
	Status  int               `json:"status"`
	Headers map[string]string `json:"headers"`
	Body    string            `json:"body"`
	Error   string            `json:"error,omitempty"`
}

// Serve listens on a Unix socket. It is the only listener in the lab netns.
func Serve(socket string) error {
	listener, err := net.Listen("unix", socket)
	if err != nil {
		return fmt.Errorf("listen %s: %w", socket, err)
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if err != nil {
			return fmt.Errorf("accept: %w", err)
		}
		go handle(conn)
	}
}

func handle(conn net.Conn) {
	defer conn.Close()
	var request Request
	if err := readFrame(conn, &request); err != nil {
		_ = writeFrame(conn, Response{Error: err.Error()})
		return
	}
	_ = writeFrame(conn, do(request))
}

// Do sends a request to the proxy over its Unix socket.
func Do(socket string, request Request) (Response, error) {
	conn, err := net.DialTimeout("unix", socket, 5*time.Second)
	if err != nil {
		return Response{}, fmt.Errorf("dial proxy: %w", err)
	}
	defer conn.Close()
	if err := writeFrame(conn, request); err != nil {
		return Response{}, err
	}
	var response Response
	if err := readFrame(conn, &response); err != nil {
		return Response{}, err
	}
	return response, nil
}

func do(request Request) Response {
	if request.Scheme == "" {
		request.Scheme = "http"
	}
	if request.Scheme != "http" && request.Scheme != "https" {
		return Response{Error: "only http and https are allowed"}
	}
	if request.Method != "GET" && request.Method != "HEAD" {
		return Response{Error: "only GET and HEAD are allowed"}
	}
	if !strings.HasPrefix(request.Path, "/") || strings.Contains(request.Path, "://") {
		return Response{Error: "path must be relative to the target"}
	}

	// Resolve once, validate every answer, then dial the pinned address.
	addresses, err := net.LookupIP(request.Host)
	if err != nil {
		return Response{Error: fmt.Sprintf("resolve %s: %v", request.Host, err)}
	}
	if len(addresses) == 0 {
		return Response{Error: "no addresses for target"}
	}
	for _, address := range addresses {
		if !inCIDRs(address, request.AllowedCIDRs) {
			return Response{Error: fmt.Sprintf("address %s is out of scope", address)}
		}
	}
	pinned := addresses[0]

	dialer := &net.Dialer{Timeout: 5 * time.Second}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, network, net.JoinHostPort(pinned.String(), strconv.Itoa(request.Port)))
		},
	}
	client := &http.Client{
		Transport: transport,
		Timeout:   10 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return fmt.Errorf("too many redirects")
			}
			if req.URL.Hostname() != request.Host {
				return fmt.Errorf("redirect to a different host is not allowed")
			}
			return nil
		},
	}

	url := fmt.Sprintf("%s://%s:%d%s", request.Scheme, request.Host, request.Port, request.Path)
	httpRequest, err := http.NewRequest(request.Method, url, nil)
	if err != nil {
		return Response{Error: err.Error()}
	}
	httpResponse, err := client.Do(httpRequest)
	if err != nil {
		return Response{Error: err.Error()}
	}
	defer httpResponse.Body.Close()

	maxBytes := request.MaxBytes
	if maxBytes <= 0 {
		maxBytes = 1 << 20
	}
	body, err := io.ReadAll(io.LimitReader(httpResponse.Body, maxBytes))
	if err != nil {
		return Response{Error: err.Error()}
	}

	headers := map[string]string{}
	for key, values := range httpResponse.Header {
		headers[key] = strings.Join(values, ", ")
	}
	return Response{Status: httpResponse.StatusCode, Headers: headers, Body: string(body)}
}

func inCIDRs(ip net.IP, cidrs []string) bool {
	for _, cidr := range cidrs {
		_, network, err := net.ParseCIDR(cidr)
		if err != nil {
			continue
		}
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func readFrame(conn net.Conn, value any) error {
	var length uint32
	if err := binary.Read(conn, binary.BigEndian, &length); err != nil {
		return fmt.Errorf("read frame length: %w", err)
	}
	if length > 4<<20 {
		return fmt.Errorf("frame too large")
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(conn, data); err != nil {
		return fmt.Errorf("read frame: %w", err)
	}
	if err := json.Unmarshal(data, value); err != nil {
		return fmt.Errorf("decode frame: %w", err)
	}
	return nil
}

func writeFrame(conn net.Conn, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("encode frame: %w", err)
	}
	if err := binary.Write(conn, binary.BigEndian, uint32(len(data))); err != nil {
		return fmt.Errorf("write frame length: %w", err)
	}
	_, err = conn.Write(data)
	return err
}
